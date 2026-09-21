import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/ui_control.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../views/compra_view.dart' show EntradaDigital;
import 'poster.dart';

/// Ventanas que abre el agente sobre la pantalla (`ventana.abrir`): la
/// confirmacion previa a una accion (RF19) y la entrada digital. Espejo de
/// `CapaVentanas.tsx`; en el movil no se arrastran: la confirmacion sube sobre el
/// boton del asistente y la entrada se muestra centrada.
class VentanasLayer extends StatelessWidget {
  final UiControl ui;

  /// "confirmo" / "cancelá" como texto al agente (igual que los botones de la web).
  final void Function(String texto) onDecir;

  /// Espacio libre que hay que dejar abajo para el boton del asistente.
  final double reservaInferior;

  const VentanasLayer({super.key, required this.ui, required this.onDecir, required this.reservaInferior});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) {
        final confirmacion = ui.ventana(TipoVentana.confirmacion);
        final ticket = ui.ventana(TipoVentana.ticket);
        return Stack(children: [
          if (ticket != null) ...[
            Positioned.fill(
              child: GestureDetector(onTap: () => ui.cerrar(TipoVentana.ticket), child: ColoredBox(color: Colors.black.withValues(alpha: 0.6))),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, reservaInferior),
                    child: _Marco(
                      titulo: 'Entrada digital',
                      icono: Icons.confirmation_number_outlined,
                      color: LumenColors.tertiary,
                      onCerrar: () => ui.cerrar(TipoVentana.ticket),
                      child: _Ticket(datos: ticket),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (confirmacion != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: reservaInferior,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
                child: _Marco(
                  titulo: (confirmacion['titulo'] as String?) ?? 'Confirma la acción',
                  icono: Icons.fact_check_outlined,
                  color: LumenColors.primary,
                  onCerrar: () => onDecir('cancelá'),
                  child: _Confirmacion(datos: confirmacion, onDecir: onDecir),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _Marco extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Color color;
  final VoidCallback onCerrar;
  final Widget child;

  const _Marco({required this.titulo, required this.icono, required this.color, required this.onCerrar, required this.child});

  @override
  Widget build(BuildContext context) => Material(
        color: LumenColors.surfaceContainer,
        elevation: 12,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            color: color.withValues(alpha: 0.14),
            child: Row(children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14))),
              IconButton(visualDensity: VisualDensity.compact, onPressed: onCerrar, icon: const Icon(Icons.close, size: 18), color: LumenColors.onSurfaceVariant),
            ]),
          ),
          Flexible(child: child),
        ]),
      );
}

// ------------------------------------------------------------------------ confirmacion

class _Confirmacion extends StatelessWidget {
  final Map<String, dynamic> datos;
  final void Function(String texto) onDecir;
  const _Confirmacion({required this.datos, required this.onDecir});

  @override
  Widget build(BuildContext context) {
    final campos = ((datos['campos'] as List?) ?? const []).whereType<Map>().map((c) => c.cast<String, dynamic>()).toList();
    final resumen = datos['resumen'] as String?;
    final aviso = datos['aviso'] as String?;
    final total = datos['total'];
    final metodo = datos['metodoPago'] as String?;
    var imagen = datos['imagen'] as String?;
    if (imagen != null && imagen.startsWith('/')) imagen = '$kVoiceAgentUrl$imagen'; // la portada la sirve el servicio de voz

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (resumen != null && resumen.isNotEmpty) Text(resumen, style: const TextStyle(color: LumenColors.onSurface, fontSize: 14, height: 1.35)),
            if (imagen != null || campos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (imagen != null) ...[Poster(url: imagen, width: 64, height: 96, radius: 10), const SizedBox(width: 10)],
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: LumenColors.surfaceContainerLowest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      for (final c in campos)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${c['etiqueta']}'.toUpperCase(), style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${c['valor']}', textAlign: TextAlign.right, style: const TextStyle(color: LumenColors.onSurface, fontSize: 13, fontWeight: FontWeight.w700))),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ]),
            ],
            if (total is num && total > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: LumenColors.primaryContainer.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Text('TOTAL${metodo == null ? '' : ' · $metodo'}', style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(bs(total), style: const TextStyle(color: LumenColors.primary, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ),
            ],
            if (aviso != null && aviso.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: LumenColors.errorContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.gpp_maybe_outlined, size: 18, color: LumenColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(aviso, style: const TextStyle(color: LumenColors.error, fontSize: 12, fontWeight: FontWeight.w700))),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            const Center(
              child: Text('DI «CONFIRMO» PARA CONTINUAR',
                  style: TextStyle(color: LumenColors.primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => onDecir('cancelá'), child: const Text('Cancelar')),
          const SizedBox(width: 8),
          // Con aviso de no reembolso la confirmacion es solo por voz (doble check, RF19): igual que en la web.
          if (aviso == null || aviso.isEmpty) FilledButton(onPressed: () => onDecir('confirmo'), child: const Text('Confirmar')),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------------ ticket

class _Ticket extends StatelessWidget {
  final Map<String, dynamic> datos;
  const _Ticket({required this.datos});

  @override
  Widget build(BuildContext context) {
    final venta = (datos['venta'] as Map?)?.cast<String, dynamic>();
    final funcion = (datos['funcion'] as Map?)?.cast<String, dynamic>();
    final asientos = ((datos['asientos'] as List?) ?? const []).map((a) => '$a').toList();
    final dulceria = ((datos['dulceria'] as List?) ?? const [])
        .whereType<Map>()
        .map((d) => '${d['cantidad']} × ${d['nombre']}')
        .toList();
    final total = venta?['total'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: EntradaDigital(
        pelicula: (datos['pelicula'] as String?) ?? 'Entrada',
        sala: datos['sala'] as String?,
        fecha: (funcion?['fecha'] as String?) ?? '',
        horaInicio: (funcion?['horaInicio'] as String?) ?? '',
        asientos: asientos,
        dulceria: dulceria,
        idVenta: (venta?['idVenta'] as num?)?.toInt(),
        total: total is num ? total.toDouble() : double.tryParse('${total ?? ''}'),
      ),
    );
  }
}
