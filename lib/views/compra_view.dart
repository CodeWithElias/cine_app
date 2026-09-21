import 'package:flutter/material.dart';

import '../models/cine_models.dart';
import '../services/pagos_stripe.dart';
import '../state/cine_state.dart';
import '../state/ui_control.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/poster.dart';
import 'pago_view.dart';

/// Proceso de compra: asientos -> dulceria -> pago -> compra completada. Lo
/// mueve el toque del cliente y tambien el agente (`compra.*`, `navegar`).
/// Espejo de `views/ProcesoCompra.tsx` (el pago esta en pago_view.dart).
class CompraView extends StatelessWidget {
  final CineState cine;
  final UiControl ui;
  final PagosStripe pagos;
  final void Function(int idVenta, Map<String, dynamic> campos)? onPagoCampos;
  final void Function(int idVenta, String evento, [String? mensaje])? onPagoEvento;

  const CompraView({super.key, required this.cine, required this.ui, required this.pagos, this.onPagoCampos, this.onPagoEvento});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cine,
      builder: (context, _) {
        if (cine.peliculaSeleccionada == null || cine.funcionSeleccionada == null) {
          return _SinFuncion(cine: cine);
        }
        if (cine.estadoCompra == EstadoCompra.completado) {
          return _Completado(cine: cine);
        }
        return Column(
          children: [
            _Pasos(estado: cine.estadoCompra),
            _Encabezado(cine: cine),
            Expanded(
              child: switch (cine.estadoCompra) {
                EstadoCompra.seleccionandoAsientos => _Asientos(cine: cine),
                EstadoCompra.seleccionandoCandybar => _Dulceria(cine: cine),
                _ => PagoView(cine: cine, ui: ui, pagos: pagos, onCampos: onPagoCampos, onEvento: onPagoEvento),
              },
            ),
            if (cine.estadoCompra != EstadoCompra.pago) _BarraInferior(cine: cine),
          ],
        );
      },
    );
  }
}

TextStyle _etiqueta(Color c) => TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8);

// ------------------------------------------------------------------------ sin funcion

class _SinFuncion extends StatelessWidget {
  final CineState cine;
  const _SinFuncion({required this.cine});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_seat_outlined, size: 44, color: LumenColors.outline),
            const SizedBox(height: 12),
            const Text('Aún no elegiste una función.\nPídele una película al asistente o elígela en la cartelera.',
                textAlign: TextAlign.center, style: TextStyle(color: LumenColors.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => cine.irA(Pantalla.cartelera),
              icon: const Icon(Icons.local_movies_outlined),
              label: const Text('Ver cartelera'),
            ),
          ]),
        ),
      );
}

// ------------------------------------------------------------------------ pasos y encabezado

class _Pasos extends StatelessWidget {
  final EstadoCompra estado;
  const _Pasos({required this.estado});

  @override
  Widget build(BuildContext context) {
    const nombres = ['Asientos', 'Dulcería', 'Pago'];
    final actual = switch (estado) {
      EstadoCompra.seleccionandoAsientos => 0,
      EstadoCompra.seleccionandoCandybar => 1,
      _ => 2,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        for (var i = 0; i < nombres.length; i++) ...[
          Expanded(
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= actual ? LumenColors.primary : LumenColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Text(nombres[i].toUpperCase(),
                  style: _etiqueta(i == actual ? LumenColors.primary : LumenColors.onSurfaceVariant).copyWith(fontSize: 10)),
            ]),
          ),
          if (i < nombres.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final CineState cine;
  const _Encabezado({required this.cine});

  @override
  Widget build(BuildContext context) {
    final p = cine.peliculaSeleccionada!;
    final f = cine.funcionSeleccionada!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: LumenColors.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Poster(url: p.posterUrl, width: 40, height: 58, radius: 8),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LumenColors.onSurface, fontWeight: FontWeight.w700)),
            Text(
              '${diaLargo(f.fecha)} · ${hora(f.horaInicio)}${cine.salaSeleccionada != null ? ' · ${cine.salaSeleccionada!.nombre}' : ''}',
              style: const TextStyle(color: LumenColors.secondary, fontSize: 12),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------------ barra inferior

class _BarraInferior extends StatelessWidget {
  final CineState cine;
  const _BarraInferior({required this.cine});

  @override
  Widget build(BuildContext context) {
    final enAsientos = cine.estadoCompra == EstadoCompra.seleccionandoAsientos;
    final puedeSeguir = !enAsientos || cine.butacas.isNotEmpty;
    final seguir = enAsientos
        ? 'Continuar'
        : cine.dulceria.isEmpty
            ? 'Omitir dulcería'
            : 'Continuar';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(color: LumenColors.surfaceContainerLow),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(
              cine.butacas.isEmpty ? 'Sin asientos elegidos' : 'Asientos: ${cine.butacas.map((b) => b.id).join(', ')}',
              style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Text(bs(cine.total), style: const TextStyle(color: LumenColors.primary, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton(
            onPressed: () {
              if (enAsientos) {
                cine.resetearCompra();
                cine.irA(Pantalla.cartelera);
              } else {
                cine.setEstadoCompra(EstadoCompra.seleccionandoAsientos);
              }
            },
            child: Text(enAsientos ? 'Cancelar' : 'Volver'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: puedeSeguir
                  ? () => cine.setEstadoCompra(enAsientos ? EstadoCompra.seleccionandoCandybar : EstadoCompra.pago)
                  : null,
              child: Text(seguir),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------------ asientos

class _Asientos extends StatelessWidget {
  final CineState cine;
  const _Asientos({required this.cine});

  @override
  Widget build(BuildContext context) {
    if (cine.cargandoDisponibilidad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cine.disponibilidad.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_busy, size: 36, color: LumenColors.outline),
          const SizedBox(height: 8),
          Text(
            cine.errorDisponibilidad != null ? 'No se pudieron cargar las butacas.\n${cine.errorDisponibilidad}' : 'No hay butacas para mostrar todavía.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: LumenColors.onSurfaceVariant),
          ),
          TextButton(onPressed: cine.recargarDisponibilidad, child: const Text('Reintentar')),
        ]),
      );
    }

    final filas = <String, List<AsientoDisponibilidad>>{};
    for (final a in cine.disponibilidad) {
      filas.putIfAbsent(a.fila, () => []).add(a);
    }
    final claves = filas.keys.toList()..sort();
    for (final f in filas.values) {
      f.sort((a, b) => a.numero.compareTo(b.numero));
    }
    final maxPorFila = filas.values.map((l) => l.length).fold<int>(1, (a, b) => a > b ? a : b);

    return LayoutBuilder(builder: (context, c) {
      const etiqueta = 22.0;
      const espacio = 5.0;
      final disponible = c.maxWidth - 32 - etiqueta - 8;
      final lado = ((disponible - espacio * (maxPorFila - 1)) / maxPorFila).clamp(20.0, 36.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(children: [
          const _PantallaCine(),
          const SizedBox(height: 18),
          for (final fila in claves)
            Padding(
              padding: const EdgeInsets.only(bottom: espacio),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: etiqueta,
                  child: Text(fila, textAlign: TextAlign.center, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                for (final a in filas[fila]!)
                  Padding(padding: const EdgeInsets.only(right: espacio), child: _Butaca(a: a, lado: lado, cine: cine)),
              ]),
            ),
          const SizedBox(height: 12),
          const Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
            _Leyenda(color: LumenColors.surfaceContainerHigh, texto: 'Libre'),
            _Leyenda(color: LumenColors.primaryContainer, texto: 'Elegido'),
            _Leyenda(color: LumenColors.surfaceContainerLow, texto: 'Ocupado', tachado: true),
          ]),
        ]),
      );
    });
  }
}

class _PantallaCine extends StatelessWidget {
  const _PantallaCine();

  @override
  Widget build(BuildContext context) => Column(children: [
        CustomPaint(size: const Size(double.infinity, 26), painter: _ArcoPantalla()),
        const SizedBox(height: 2),
        Text('PANTALLA', style: _etiqueta(LumenColors.secondary)),
      ]);
}

class _ArcoPantalla extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Color(0x1A111319), LumenColors.secondary, LumenColors.primary, LumenColors.secondary, Color(0x1A111319)])
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path()
      ..moveTo(size.width * 0.04, size.height - 2)
      ..quadraticBezierTo(size.width / 2, -size.height * 0.5, size.width * 0.96, size.height - 2);
    canvas.drawPath(path, trazo);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Butaca extends StatelessWidget {
  final AsientoDisponibilidad a;
  final double lado;
  final CineState cine;
  const _Butaca({required this.a, required this.lado, required this.cine});

  @override
  Widget build(BuildContext context) {
    final elegida = cine.butacas.any((b) => b.idAsiento == a.idAsiento);
    if (!a.disponible) {
      return Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(color: LumenColors.surfaceContainerLow, borderRadius: BorderRadius.circular(6)),
        child: Icon(Icons.close, size: lado * 0.5, color: LumenColors.outlineVariant),
      );
    }
    return GestureDetector(
      onTap: () => cine.toggleButaca(a),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: elegida ? LumenColors.primaryContainer : LumenColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          boxShadow: elegida ? [BoxShadow(color: LumenColors.primaryContainer.withValues(alpha: 0.55), blurRadius: 12)] : const [],
        ),
        child: elegida
            ? Icon(Icons.check, size: lado * 0.55, color: LumenColors.onPrimaryContainer)
            : Text('${a.numero}', style: TextStyle(color: LumenColors.onSurfaceVariant, fontSize: lado * 0.38)),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  final bool tachado;
  const _Leyenda({required this.color, required this.texto, this.tachado = false});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: tachado ? const Icon(Icons.close, size: 10, color: LumenColors.outlineVariant) : null,
        ),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 11)),
      ]);
}

// ------------------------------------------------------------------------ dulceria

class _Dulceria extends StatefulWidget {
  final CineState cine;
  const _Dulceria({required this.cine});

  @override
  State<_Dulceria> createState() => _DulceriaState();
}

class _DulceriaState extends State<_Dulceria> {
  List<CategoriaDulceria> _categorias = const [];
  List<ProductoDulceria> _productos = const [];
  int? _categoria;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await Future.wait<Object>([widget.cine.api.listarCategoriasDulceria(), widget.cine.api.listarProductosDulceria()]);
      if (!mounted) return;
      setState(() {
        _categorias = r[0] as List<CategoriaDulceria>;
        _productos = (r[1] as List<ProductoDulceria>).where((p) => p.disponible).toList();
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el menú de dulcería. Puedes saltar este paso y seguir con el pago.';
        _cargando = false;
      });
    }
  }

  int _cantidad(ProductoDulceria p) => widget.cine.dulceria.where((i) => i.id == '${p.idProducto}').firstOrNull?.cantidad ?? 0;

  void _cambiar(ProductoDulceria p, int delta) {
    final actual = _cantidad(p);
    final nueva = (actual + delta).clamp(0, 99);
    widget.cine.actualizarDulceria(ItemDulceria(
      id: '${p.idProducto}',
      nombre: p.nombre,
      descripcion: p.descripcion ?? '',
      precio: p.precioBase,
      imagenUrl: p.imagenUrl ?? '',
      cantidad: nueva,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: LumenColors.onSurfaceVariant)),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    final visibles = _categoria == null ? _productos : _productos.where((p) => p.idCategoria == _categoria).toList();

    return Column(children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          _chip('Todo', _categoria == null, () => setState(() => _categoria = null)),
          for (final c in _categorias) _chip(c.nombre, _categoria == c.idCategoria, () => setState(() => _categoria = c.idCategoria)),
        ]),
      ),
      Expanded(
        child: visibles.isEmpty
            ? const Center(child: Text('No hay productos en esta categoría.', style: TextStyle(color: LumenColors.onSurfaceVariant)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                itemCount: visibles.length,
                itemBuilder: (_, i) => _fila(visibles[i]),
              ),
      ),
    ]);
  }

  Widget _chip(String t, bool activo, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(t),
          selected: activo,
          onSelected: (_) => onTap(),
          selectedColor: LumenColors.primary,
          labelStyle: TextStyle(color: activo ? LumenColors.onPrimary : LumenColors.onSurface, fontWeight: FontWeight.w600),
          backgroundColor: LumenColors.surfaceContainerHigh,
          side: BorderSide.none,
        ),
      );

  Widget _fila(ProductoDulceria p) {
    final cantidad = _cantidad(p);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cantidad > 0 ? LumenColors.primary.withValues(alpha: 0.6) : Colors.transparent),
      ),
      child: Row(children: [
        Poster(url: p.imagenUrl, width: 56, height: 56, radius: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nombre, style: const TextStyle(color: LumenColors.onSurface, fontWeight: FontWeight.w700)),
            if ((p.descripcion ?? '').isNotEmpty)
              Text(p.descripcion!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 11)),
            const SizedBox(height: 2),
            Text(bs(p.precioBase), style: const TextStyle(color: LumenColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
        _Contador(cantidad: cantidad, onMas: () => _cambiar(p, 1), onMenos: () => _cambiar(p, -1)),
      ]),
    );
  }
}

class _Contador extends StatelessWidget {
  final int cantidad;
  final VoidCallback onMas;
  final VoidCallback onMenos;
  const _Contador({required this.cantidad, required this.onMas, required this.onMenos});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: cantidad > 0 ? onMenos : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: LumenColors.onSurface,
        ),
        SizedBox(width: 22, child: Text('$cantidad', textAlign: TextAlign.center, style: const TextStyle(color: LumenColors.onSurface, fontWeight: FontWeight.w700))),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onMas,
          icon: const Icon(Icons.add_circle),
          color: LumenColors.primary,
        ),
      ]);
}

// ------------------------------------------------------------------------ compra completada

class _Completado extends StatelessWidget {
  final CineState cine;
  const _Completado({required this.cine});

  @override
  Widget build(BuildContext context) {
    final p = cine.peliculaSeleccionada!;
    final f = cine.funcionSeleccionada!;
    final venta = cine.ventaCreada;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: LumenColors.surfaceContainer, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [LumenColors.tertiaryContainer, LumenColors.tertiary]),
              ),
              child: const Icon(Icons.verified, color: LumenColors.onTertiary, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('¡Compra confirmada!', style: TextStyle(color: LumenColors.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
                Text(venta?.metodoPagoElegido == 'stripe' ? 'Pago con tarjeta confirmado' : 'Pago en efectivo registrado',
                    style: const TextStyle(color: LumenColors.tertiary, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        EntradaDigital(
          pelicula: p.titulo,
          sala: cine.salaSeleccionada?.nombre,
          fecha: f.fecha,
          horaInicio: f.horaInicio,
          asientos: cine.butacas.map((b) => b.id).toList(),
          dulceria: [for (final i in cine.dulceria) '${i.cantidad} × ${i.nombre}'],
          idVenta: venta?.idVenta,
          total: cine.totalReal,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            cine.resetearCompra();
            cine.irA(Pantalla.cartelera);
          },
          icon: const Icon(Icons.home_outlined),
          label: const Text('Volver a la cartelera'),
        ),
        TextButton(
          onPressed: () {
            cine.resetearCompra();
            cine.irA(Pantalla.misCompras);
          },
          child: const Text('Ver mis compras'),
        ),
      ]),
    );
  }
}

/// Tarjeta de entrada digital (pelicula, funcion, asientos, codigo de compra y total).
class EntradaDigital extends StatelessWidget {
  final String pelicula;
  final String? sala;
  final String fecha;
  final String horaInicio;
  final List<String> asientos;
  final List<String> dulceria;
  final int? idVenta;
  final double? total;

  const EntradaDigital({
    super.key,
    required this.pelicula,
    this.sala,
    required this.fecha,
    required this.horaInicio,
    required this.asientos,
    required this.dulceria,
    this.idVenta,
    this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LumenColors.primaryContainer.withValues(alpha: 0.25), LumenColors.surfaceContainerHigh, LumenColors.secondaryContainer.withValues(alpha: 0.2)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LUMEN CINEMA · ${(sala ?? 'SALA POR CONFIRMAR').toUpperCase()}', style: _etiqueta(LumenColors.secondary)),
        const SizedBox(height: 4),
        Text(pelicula, style: const TextStyle(color: LumenColors.primary, fontSize: 21, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _dato('FECHA', diaLargo(fecha))),
          _dato('HORA', hora(horaInicio), derecha: true),
        ]),
        const SizedBox(height: 12),
        Text('ASIENTOS', style: _etiqueta(LumenColors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in asientos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: LumenColors.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(a, style: const TextStyle(color: LumenColors.onPrimaryContainer, fontWeight: FontWeight.w800)),
            ),
        ]),
        if (dulceria.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('DULCERÍA', style: _etiqueta(LumenColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(dulceria.join(' · '), style: const TextStyle(color: LumenColors.onSurface)),
        ],
        const Divider(height: 26, color: LumenColors.outlineVariant),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _dato('COMPRA', '#${idVenta ?? '—'}', color: LumenColors.tertiary)),
          if (total != null && total! > 0) _dato('TOTAL', bs(total!), color: LumenColors.primary, derecha: true),
        ]),
      ]),
    );
  }

  Widget _dato(String etiqueta, String valor, {Color color = LumenColors.onSurface, bool derecha = false}) => Column(
        crossAxisAlignment: derecha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: _etiqueta(LumenColors.onSurfaceVariant)),
          Text(valor, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      );
}
