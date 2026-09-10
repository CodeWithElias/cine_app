import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'staggered_entrance.dart';

/// Vista generativa disparada por voz ("qué butacas hay libres"). Ocupa
/// todo el espacio disponible - se agranda/centra segun el tamano de
/// pantalla, y el usuario puede acercar/alejar/rotar con gestos (ver
/// ManipulableCanvas, que envuelve esta vista). Ocupacion de prueba (fija,
/// no aleatoria) - se conecta a disponibilidad real mas adelante.
class ButacasGrid extends StatefulWidget {
  const ButacasGrid({super.key});

  @override
  State<ButacasGrid> createState() => _ButacasGridState();
}

const _filas = ['A', 'B', 'C', 'D', 'E', 'F'];
const _asientosPorFila = 8;

// Patron fijo de butacas ya ocupadas (fila*asientosPorFila + asiento).
const _ocupadas = {2, 3, 9, 14, 15, 16, 22, 27, 28, 33, 40, 41};

class _ButacasGridState extends State<ButacasGrid> {
  final Set<int> _seleccionadas = {};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final seatSize = (constraints.maxWidth / (_asientosPorFila + 2)).clamp(36.0, 56.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'BUTACAS • SALA 3',
                  style: TextStyle(
                    color: LumenColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 16),
                _legendDot(LumenColors.secondaryContainer.withValues(alpha: 0.6), 'Libre'),
                const SizedBox(width: 10),
                _legendDot(LumenColors.surfaceContainerHighest, 'Ocupada'),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    LumenColors.secondary.withValues(alpha: 0),
                    LumenColors.secondary.withValues(alpha: 0.6),
                    LumenColors.secondary.withValues(alpha: 0),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 6),
            const Text('PANTALLA', style: TextStyle(color: LumenColors.outline, fontSize: 10, letterSpacing: 3)),
            const SizedBox(height: 36),
            for (int f = 0; f < _filas.length; f++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: StaggeredEntrance(
                  index: f,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          _filas[f],
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: LumenColors.outline, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ...List.generate(_asientosPorFila, (a) {
                        final id = f * _asientosPorFila + a;
                        final ocupada = _ocupadas.contains(id);
                        final seleccionada = _seleccionadas.contains(id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: ocupada
                                ? null
                                : () => setState(() {
                                      if (seleccionada) {
                                        _seleccionadas.remove(id);
                                      } else {
                                        _seleccionadas.add(id);
                                      }
                                    }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: seatSize,
                              height: seatSize,
                              decoration: BoxDecoration(
                                color: ocupada
                                    ? LumenColors.surfaceContainerHighest
                                    : seleccionada
                                        ? LumenColors.primary
                                        : LumenColors.secondaryContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.chair,
                                size: seatSize * 0.55,
                                color: ocupada
                                    ? LumenColors.outline
                                    : seleccionada
                                        ? LumenColors.onPrimary
                                        : LumenColors.secondary,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            if (_seleccionadas.isNotEmpty)
              Text(
                '${_seleccionadas.length} butaca(s) seleccionada(s)',
                style: const TextStyle(color: LumenColors.tertiary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
          ],
        );
      },
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: LumenColors.onSurfaceVariant, fontSize: 10)),
      ],
    );
  }
}
