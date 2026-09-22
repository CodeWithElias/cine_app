import 'package:flutter/material.dart';

import '../models/cine_models.dart';
import '../services/cine_api.dart';
import '../state/cine_state.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../widgets/aviso_datos_guardados.dart';

/// Historial de compras del cliente (`GET /ventas`) con el detalle al tocar una.
/// Espejo de `views/MisCompras.tsx`.
class MisComprasView extends StatefulWidget {
  final CineState cine;
  const MisComprasView({super.key, required this.cine});

  @override
  State<MisComprasView> createState() => _MisComprasViewState();
}

class _MisComprasViewState extends State<MisComprasView> {
  List<CompraHistorial> _compras = const [];
  final Map<int, DetalleCompra> _detalles = {};
  int? _abierta;
  bool _cargando = true;
  String? _error;

  static const _estados = {
    'pagada': ('Pagada', LumenColors.tertiary),
    'confirmada': ('Confirmada', LumenColors.tertiary),
    'pendiente_pago': ('Pendiente de pago', LumenColors.primary),
    'pendiente': ('Pendiente', LumenColors.primary),
    'cancelada': ('Cancelada', LumenColors.error),
    'anulada': ('Anulada', LumenColors.error),
  };

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
      final lista = [
        ...await widget.cine.api.listarMisCompras(),
      ]; // copia: la API puede entregar una lista de solo lectura
      lista.sort(
        (a, b) => (b.venta.fechaHora ?? '').compareTo(a.venta.fechaHora ?? ''),
      );
      if (!mounted) return;
      setState(() {
        _compras = lista;
        _cargando = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    }
  }

  Future<void> _alternar(CompraHistorial c) async {
    final id = c.venta.idVenta;
    setState(() => _abierta = _abierta == id ? null : id);
    if (_abierta == id && !_detalles.containsKey(id)) {
      try {
        final d = await widget.cine.api.obtenerDetalleCompra(id);
        if (mounted) setState(() => _detalles[id] = d);
      } catch (_) {
        // sin detalle igual se ve el resumen
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargar,
      color: LumenColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const AvisoDatosGuardados(),
          const Text(
            'TUS ENTRADAS',
            style: TextStyle(
              color: LumenColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Mis compras',
            style: TextStyle(
              color: LumenColors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _vacio(
              Icons.cloud_off,
              _error!,
              accion: 'Reintentar',
              onAccion: _cargar,
            )
          else if (_compras.isEmpty)
            _vacio(
              Icons.receipt_long_outlined,
              'Todavía no hiciste ninguna compra.',
            )
          else
            for (final c in _compras) _tarjeta(c),
        ],
      ),
    );
  }

  Widget _tarjeta(CompraHistorial c) {
    final abierta = _abierta == c.venta.idVenta;
    final detalle = _detalles[c.venta.idVenta];
    final (etiqueta, color) =
        _estados[c.venta.estado] ??
        (c.venta.estado, LumenColors.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: LumenColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _alternar(c),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.pelicula,
                      style: const TextStyle(
                        color: LumenColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      etiqueta,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${diaLargo(c.fecha)} · ${hora(c.horaInicio)}${c.sala.isEmpty ? '' : ' · ${c.sala}'}',
                style: const TextStyle(
                  color: LumenColors.secondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Compra #${c.venta.idVenta}',
                    style: const TextStyle(
                      color: LumenColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    bs(c.venta.total),
                    style: const TextStyle(
                      color: LumenColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(
                    abierta ? Icons.expand_less : Icons.expand_more,
                    color: LumenColors.onSurfaceVariant,
                  ),
                ],
              ),
              if (abierta) ...[
                const Divider(color: LumenColors.outlineVariant),
                if (detalle == null)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else ...[
                  _dato(
                    'Asientos',
                    detalle.asientos.isEmpty
                        ? '—'
                        : detalle.asientos.join(', '),
                  ),
                  if (detalle.dulceria.isNotEmpty)
                    _dato('Dulcería', detalle.dulceria.join(' · ')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dato(String e, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            e,
            style: const TextStyle(
              color: LumenColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              color: LumenColors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _vacio(
    IconData icono,
    String texto, {
    String? accion,
    VoidCallback? onAccion,
  }) => Padding(
    padding: const EdgeInsets.only(top: 50),
    child: Column(
      children: [
        Icon(icono, size: 40, color: LumenColors.outline),
        const SizedBox(height: 10),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: LumenColors.onSurfaceVariant),
        ),
        if (accion != null)
          TextButton(onPressed: onAccion, child: Text(accion)),
      ],
    ),
  );
}
