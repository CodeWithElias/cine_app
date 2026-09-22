import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/cine_models.dart';
import '../services/auth_service.dart';
import '../services/cine_api.dart';
import '../services/pagos_stripe.dart';
import '../state/cine_state.dart';
import '../state/ui_control.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

/// Un cobro que no se pudo completar, con el evento que se le cuenta al agente.
class _PagoFallido implements Exception {
  final String evento; // rechazado | error
  final String mensaje;
  _PagoFallido(this.evento, this.mensaje);
}

enum _Metodo { tarjeta, efectivo }

enum _Fase { editando, procesando, exito }

/// Convierte lo que informa el campo seguro de Stripe en el estado de cada campo que entiende el agente
/// (`completo`, `vacio`, `error`). NUNCA lleva lo escrito: los datos de la tarjeta viven solo dentro del campo de Stripe.
/// Solo un dato INVALIDO cuenta como error para la voz; "incompleto" es normal mientras se escribe.
Map<String, Map<String, dynamic>> camposDeTarjeta(CardFieldInputDetails? d) {
  Map<String, dynamic> campo(
    CardValidationState? estado,
    bool escrito,
    String mensaje,
  ) => {
    'completo': estado == CardValidationState.Valid,
    'vacio':
        !escrito &&
        estado != CardValidationState.Valid &&
        estado != CardValidationState.Invalid,
    'error': estado == CardValidationState.Invalid ? mensaje : null,
  };
  return {
    'numero': campo(
      d?.validNumber,
      (d?.last4 ?? '').isNotEmpty ||
          d?.validNumber == CardValidationState.Invalid,
      'El número de tarjeta no es válido.',
    ),
    'vencimiento': campo(
      d?.validExpiryDate,
      d?.expiryMonth != null ||
          d?.validExpiryDate == CardValidationState.Invalid,
      'La fecha de vencimiento no es válida.',
    ),
    'cvc': campo(
      d?.validCVC,
      d?.validCVC == CardValidationState.Invalid,
      'El código de seguridad no es válido.',
    ),
  };
}

/// Paso de pago de la compra. Un mismo formulario para dos caminos:
///  - tactil: el cliente elige tarjeta o efectivo, acepta la politica de no reembolso y toca "Pagar";
///  - por voz: el agente ya creo la venta (RF19) y guia campo por campo; "pagar" se dice o se toca.
/// La tarjeta se paga con el campo seguro de Stripe (los datos nunca pasan por la app ni por el agente) y la venta
/// solo queda pagada cuando el SERVIDOR confirma con Stripe. Espejo de `SeccionPago.tsx`.
class PagoView extends StatefulWidget {
  final CineState cine;
  final UiControl ui;
  final PagosStripe pagos;

  /// Como va el formulario de tarjeta (solo el estado de cada campo) para que el agente guie.
  final void Function(int idVenta, Map<String, dynamic> campos)? onCampos;

  /// Como termino el intento de pago (confirmado | rechazado | cancelado | error).
  final void Function(int idVenta, String evento, [String? mensaje])? onEvento;

  const PagoView({
    super.key,
    required this.cine,
    required this.ui,
    required this.pagos,
    this.onCampos,
    this.onEvento,
  });

  @override
  State<PagoView> createState() => _PagoViewState();
}

class _PagoViewState extends State<PagoView> {
  static const _pausaExito = Duration(milliseconds: 1400);

  late _Metodo _metodo = widget.pagos.habilitado
      ? _Metodo.tarjeta
      : _Metodo.efectivo;
  bool _acepta = false;
  _Fase _fase = _Fase.editando;
  String? _aviso;
  bool _avisoEsError = true;
  bool _enCurso = false;
  Map<String, Map<String, dynamic>> _campos = camposDeTarjeta(null);
  Timer? _pausaCampos;
  late int _atendido;
  late final TextEditingController _titular = TextEditingController(
    text: (AuthService.instance.usuario?.nombre ?? '').toUpperCase(),
  );

  CineState get _cine => widget.cine;
  CineApi get _api => widget.cine.api;

  /// La venta pendiente SOLO vale si corresponde a lo que se ve ahora (mismas butacas y dulceria).
  Venta? get _vigente => _cine.pendienteVigente ? _cine.ventaPendiente : null;
  bool get _porVoz => _vigente?.tipoRegistro == 'voz';
  bool get _camposCompletos =>
      _campos.values.every((c) => c['completo'] == true);

  @override
  void initState() {
    super.initState();
    _atendido =
        widget.ui.solicitudPago?.n ??
        0; // los pedidos anteriores a que se abriera esta pantalla no valen
    widget.ui.addListener(_alPedidoDePago);
    widget.pagos.addListener(_alCambiarStripe);
  }

  @override
  void dispose() {
    widget.ui.removeListener(_alPedidoDePago);
    widget.pagos.removeListener(_alCambiarStripe);
    _pausaCampos?.cancel();
    _titular.dispose();
    super.dispose();
  }

  void _alCambiarStripe() {
    if (mounted) setState(() {});
  }

  /// El cliente dijo "pagar" o "cancelar" durante el pago.
  void _alPedidoDePago() {
    final s = widget.ui.solicitudPago;
    if (s == null || s.n <= _atendido) return;
    _atendido = s.n;
    if (s.accion == 'enviar') {
      _pagar();
    } else {
      _cancelar(porVoz: true);
    }
  }

  // ------------------------------------------------------------------ lo que se le cuenta al agente

  void _avisar(int? idVenta, String evento, [String? mensaje]) {
    if (idVenta != null) widget.onEvento?.call(idVenta, evento, mensaje);
  }

  void _alCambiarTarjeta(CardFieldInputDetails? detalle) {
    setState(() => _campos = camposDeTarjeta(detalle));
    final id = _vigente?.idVenta;
    if (!_porVoz || id == null) return;
    _pausaCampos?.cancel();
    _pausaCampos = Timer(
      const Duration(milliseconds: 250),
      () => widget.onCampos?.call(id, _campos),
    );
  }

  // ------------------------------------------------------------------ crear la venta (una sola vez)

  Future<int> _obtenerIdVenta() async {
    if (_cine.pendienteVigente) {
      return _cine
          .ventaPendiente!
          .idVenta; // reintento tras un rechazo: no se crea otra venta
    }
    if (_cine.ventaPendiente != null) {
      // Cambio lo elegido desde que se reservo: esa venta ya no corresponde. Se cancela y se liberan sus asientos.
      await _api
          .cancelarVentaPendiente(_cine.ventaPendiente!.idVenta)
          .catchError((Object _) {});
      _cine.limpiarPendiente();
    }
    final f = _cine.funcionSeleccionada;
    if (f == null) throw _PagoFallido('error', 'No hay una función elegida.');
    final venta = await _api.crearVenta(
      idFuncion: f.idFuncion,
      idAsientos: _cine.butacas.map((b) => b.idAsiento).toList(),
      dulceria: _cine.dulceria,
    );
    _cine.setVentaPendiente(venta);
    return venta.idVenta;
  }

  // ------------------------------------------------------------------ cobrar con tarjeta (Stripe)

  Future<Venta> _cobrarConTarjeta(int idVenta) async {
    final InicioPagoStripe inicio;
    try {
      inicio = await _api.iniciarPagoStripe(idVenta);
    } on ApiException catch (e) {
      if (e.status == 409) {
        _cine.limpiarPendiente();
        throw _PagoFallido(
          'error',
          'Tu reserva venció o ya no está disponible. Vuelve a elegir tus asientos.',
        );
      }
      rethrow;
    }

    try {
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: inicio.clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: BillingDetails(
              name: _titular.text.trim().isEmpty ? null : _titular.text.trim(),
            ),
          ),
        ),
      );
    } on StripeException catch (e) {
      // Que el servidor tambien registre el rechazo (el webhook puede tardar); si esta consulta falla no importa.
      unawaited(
        _api
            .verificarPagoStripe(inicio.idPago)
            .then((_) {}, onError: (Object _) {}),
      );
      throw _PagoFallido(
        'rechazado',
        e.error.localizedMessage ??
            e.error.message ??
            'La tarjeta fue rechazada.',
      );
    }

    // Lo que diga la app no cuenta: el SERVIDOR le pregunta a Stripe y la venta solo queda pagada si Stripe lo confirmo.
    for (var intento = 0; intento < 6; intento++) {
      final v = await _api.verificarPagoStripe(inicio.idPago);
      if (v.venta.estado == 'pagada') return v.venta;
      if (v.estado == 'fallido' || v.estado == 'cancelado') {
        throw _PagoFallido(
          'rechazado',
          v.mensaje ?? 'El pago no se pudo completar.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    throw _PagoFallido(
      'error',
      'Stripe todavía no confirmó el pago. Espera unos segundos y vuelve a tocar Pagar.',
    );
  }

  // ------------------------------------------------------------------ pagar

  Future<void> _pagar() async {
    if (_enCurso || !mounted) return;
    final idVoz = _porVoz ? _vigente!.idVenta : null;

    if (idVoz == null && !_acepta) {
      setState(() {
        _aviso =
            'Para continuar tienes que aceptar que las entradas no tienen reembolso.';
        _avisoEsError = true;
      });
      return;
    }
    if (_metodo == _Metodo.tarjeta && !_camposCompletos) {
      setState(() {
        _aviso =
            'Completa el número, el vencimiento y el código de seguridad de la tarjeta.';
        _avisoEsError = true;
      });
      return;
    }

    _enCurso = true;
    setState(() {
      _fase = _Fase.procesando;
      _aviso = null;
    });
    try {
      final idVenta = await _obtenerIdVenta();
      final venta = _metodo == _Metodo.efectivo
          ? await _api.pagarEnEfectivo(idVenta)
          : await _cobrarConTarjeta(idVenta);

      // Se ve "Pago exitoso" un momento; despues se pasa a la compra completada y el agente dice "gracias".
      if (!mounted) return;
      setState(() => _fase = _Fase.exito);
      await Future<void>.delayed(_pausaExito);
      _cine.completarCompra(venta);
      _avisar(idVoz, 'confirmado');
    } catch (e) {
      final mensaje = e is _PagoFallido
          ? e.mensaje
          : (e is ApiException
                ? e.message
                : 'No se pudo completar el pago. Intenta de nuevo.');
      if (mounted) {
        setState(() {
          _aviso = mensaje;
          _avisoEsError = true;
          _fase = _Fase.editando;
        });
      }
      _avisar(
        idVoz ?? _cine.ventaPendiente?.idVenta,
        e is _PagoFallido ? e.evento : 'error',
        mensaje,
      );
    } finally {
      _enCurso = false;
    }
  }

  // ------------------------------------------------------------------ cancelar

  Future<void> _cancelar({required bool porVoz}) async {
    if (_enCurso || !mounted) return;
    final pendiente = _cine.ventaPendiente;
    if (pendiente != null) {
      _enCurso = true;
      try {
        await _api.cancelarVentaPendiente(pendiente.idVenta);
      } catch (e) {
        // Si ya estaba pagada (409) no se toca nada: se le dice tal cual.
        final texto = e is ApiException
            ? e.message
            : 'No se pudo cancelar el pago.';
        if (mounted) {
          setState(() {
            _aviso = texto;
            _avisoEsError = true;
          });
        }
        if (pendiente.tipoRegistro == 'voz') {
          _avisar(pendiente.idVenta, 'error', texto);
        }
        _enCurso = false;
        return;
      }
      _enCurso = false;
      _cine.limpiarPendiente();
      if (pendiente.tipoRegistro == 'voz') {
        _avisar(pendiente.idVenta, 'cancelado');
      }
      if (mounted) {
        setState(() {
          _aviso =
              'Cancelaste el pago. Tus asientos volvieron a quedar libres.';
          _avisoEsError = false;
        });
      }
    }
    // Desde la pantalla (sin voz) "cancelar" tambien vuelve al paso anterior; por voz se queda aca y el agente dice como seguir.
    if (!porVoz) _cine.setEstadoCompra(EstadoCompra.seleccionandoCandybar);
  }

  // ------------------------------------------------------------------ interfaz

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cine,
      builder: (context, _) {
        final vigente = _vigente;
        final total =
            vigente?.total ??
            _cine
                .total; // con la venta creada manda su total real (incluye promociones)
        final ocupado = _fase != _Fase.editando;
        final aceptado =
            _porVoz ||
            _acepta; // por voz ya se acepto al decir "confirmo" (RF03/RF19)
        final campoGuia =
            (_porVoz && _fase == _Fase.editando && _metodo == _Metodo.tarjeta)
            ? const {
                    'numero': 'el número',
                    'vencimiento': 'la fecha de vencimiento',
                    'cvc': 'el código de seguridad',
                  }.entries
                  .where((e) => _campos[e.key]!['completo'] != true)
                  .firstOrNull
                  ?.value
            : null;
        final bloqueado =
            ocupado ||
            !aceptado ||
            (_metodo == _Metodo.tarjeta && !_camposCompletos);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _encabezado(),
              const SizedBox(height: 10),
              _resumen(total),
              const SizedBox(height: 12),
              if (widget.pagos.habilitado) _selectorMetodo(ocupado),
              const SizedBox(height: 10),
              if (_fase == _Fase.exito)
                _exito()
              else if (_metodo == _Metodo.tarjeta)
                _tarjeta(campoGuia, ocupado)
              else
                _efectivo(),
              if (!_porVoz)
                CheckboxListTile(
                  value: _acepta,
                  onChanged: ocupado
                      ? null
                      : (v) => setState(() => _acepta = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: LumenColors.primary,
                  title: const Text(
                    'Entiendo que las entradas no tienen reembolso.',
                    style: TextStyle(
                      color: LumenColors.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_aviso != null) _cajaAviso(),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _enCurso || ocupado
                        ? null
                        : () => _cancelar(porVoz: false),
                    child: Text(vigente != null ? 'Cancelar pago' : 'Volver'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: bloqueado ? null : _pagar,
                      child: _fase == _Fase.procesando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _metodo == _Metodo.tarjeta
                                  ? 'Pagar ${bs(total)}'
                                  : 'Confirmar pago en efectivo',
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'También puedes decirle al asistente «pagar» o «cancelar».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _encabezado() => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: LumenColors.primaryContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.lock_outline,
          color: LumenColors.primary,
          size: 20,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pago seguro',
              style: TextStyle(
                color: LumenColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'LUMEN CHECKOUT',
              style: TextStyle(
                color: LumenColors.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
      if (_porVoz)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: LumenColors.primaryContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 14, color: LumenColors.primary),
              SizedBox(width: 4),
              Text(
                'Lumen te guía',
                style: TextStyle(
                  color: LumenColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _resumen(double total) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LumenColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        _linea('Entradas (${_cine.butacas.length})', bs(_cine.totalEntradas)),
        for (final i in _cine.dulceria)
          _linea('${i.cantidad} × ${i.nombre}', bs(i.precio * i.cantidad)),
        const Divider(color: LumenColors.outlineVariant),
        _linea('Total', bs(total), fuerte: true),
      ],
    ),
  );

  Widget _linea(String a, String b, {bool fuerte = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: TextStyle(
              color: fuerte
                  ? LumenColors.onSurface
                  : LumenColors.onSurfaceVariant,
              fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          b,
          style: TextStyle(
            color: fuerte ? LumenColors.primary : LumenColors.onSurface,
            fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
            fontSize: fuerte ? 17 : 14,
          ),
        ),
      ],
    ),
  );

  Widget _selectorMetodo(bool ocupado) {
    Widget opcion(_Metodo m, IconData icono, String texto) {
      final activo = _metodo == m;
      return Expanded(
        child: GestureDetector(
          onTap: ocupado ? null : () => setState(() => _metodo = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: activo
                  ? LumenColors.primary.withValues(alpha: 0.14)
                  : LumenColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: activo ? LumenColors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icono,
                  size: 19,
                  color: activo
                      ? LumenColors.primary
                      : LumenColors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  texto,
                  style: TextStyle(
                    color: activo ? LumenColors.primary : LumenColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        opcion(_Metodo.tarjeta, Icons.credit_card, 'Tarjeta'),
        const SizedBox(width: 10),
        opcion(_Metodo.efectivo, Icons.payments_outlined, 'Efectivo'),
      ],
    );
  }

  Widget _tarjeta(String? campoGuia, bool ocupado) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LumenColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (campoGuia != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: LumenColors.primaryContainer.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Ahora: $campoGuia',
              style: const TextStyle(
                color: LumenColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        const Text(
          'TITULAR',
          style: TextStyle(
            color: LumenColors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _titular,
          enabled: !ocupado,
          maxLength: 26,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: LumenColors.onSurface),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'NOMBRE COMO EN LA TARJETA',
            hintStyle: const TextStyle(color: LumenColors.outline),
            filled: true,
            fillColor: LumenColors.surfaceContainerLowest,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'DATOS DE LA TARJETA',
          style: TextStyle(
            color: LumenColors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        // Campo seguro de Stripe: numero, vencimiento y codigo. Lo escrito nunca pasa por la app ni por el agente.
        IgnorePointer(
          ignoring: ocupado,
          child: CardField(
            enablePostalCode: false,
            onCardChanged: _alCambiarTarjeta,
            cursorColor: LumenColors.primary,
            style: const TextStyle(color: LumenColors.onSurface, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: LumenColors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (widget.pagos.modoPrueba) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: LumenColors.secondaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Modo de prueba: no se cobra dinero real. Usa la tarjeta 4242 4242 4242 4242, cualquier fecha futura y cualquier código de 3 dígitos.',
              style: TextStyle(
                color: LumenColors.secondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
        if (_campos.values.any((c) => c['error'] != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _campos.values.firstWhere((c) => c['error'] != null)['error']
                  as String,
              style: const TextStyle(color: LumenColors.error, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _efectivo() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LumenColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: LumenColors.primary.withValues(alpha: 0.5)),
    ),
    child: const Row(
      children: [
        Icon(Icons.payments_outlined, color: LumenColors.primary),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pago en efectivo',
                style: TextStyle(
                  color: LumenColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Tu compra queda registrada y pagas en boletería.',
                style: TextStyle(
                  color: LumenColors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _exito() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26),
    decoration: BoxDecoration(
      color: LumenColors.tertiaryContainer.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Column(
      children: [
        Icon(Icons.check_circle, size: 46, color: LumenColors.tertiary),
        SizedBox(height: 8),
        Text(
          '¡Pago exitoso!',
          style: TextStyle(
            color: LumenColors.tertiary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _cajaAviso() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 6, bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color:
          (_avisoEsError
                  ? LumenColors.errorContainer
                  : LumenColors.surfaceContainerHigh)
              .withValues(alpha: _avisoEsError ? 0.35 : 1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _aviso!,
      style: TextStyle(
        color: _avisoEsError ? LumenColors.error : LumenColors.onSurface,
        fontSize: 13,
      ),
    ),
  );
}
