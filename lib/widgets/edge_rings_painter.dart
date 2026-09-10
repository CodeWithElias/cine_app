import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Arcos en forma de campana (como una distribucion de probabilidad) que
/// nacen cerca de los bordes inferiores de la pantalla y suben para bordear
/// el boton de voz desde arriba. Mientras mas "activo" este el agente
/// (escuchando/hablando), mas brillante se ve y mas rapido viaja el brillo
/// a lo largo del arco.
class EdgeRingsPainter extends CustomPainter {
  final Offset anchor; // posicion del boton (centro)
  final double shimmer; // 0..1, avanza infinito - hace viajar el brillo
  final double intensity; // 0..1, que tan "activo" esta
  final Color colorA;
  final Color colorB;

  EdgeRingsPainter({
    required this.anchor,
    required this.shimmer,
    required this.intensity,
    required this.colorA,
    required this.colorB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const arcCount = 3;
    for (int i = 0; i < arcCount; i++) {
      final radius = 90.0 + i * 46.0;
      // Circulo centrado justo debajo del boton: solo se ve la porcion de
      // arriba, que arma la forma de "campana" bordeando el boton.
      final center = anchor + const Offset(0, 18);
      final rect = Rect.fromCircle(center: center, radius: radius);

      // Arco fijo (la "campana"): cubre la mitad superior, un poco mas.
      const startAngle = math.pi * 1.08;
      const sweep = math.pi * 0.84;

      final shimmerAngle = startAngle + sweep * ((shimmer + i * 0.28) % 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + intensity * 1.5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: GradientRotation(shimmerAngle - math.pi / 2),
          colors: [
            colorA.withValues(alpha: 0.06 + intensity * 0.1),
            colorB.withValues(alpha: 0.35 + intensity * 0.55),
            colorA.withValues(alpha: 0.06 + intensity * 0.1),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);

      canvas.drawArc(rect, startAngle, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant EdgeRingsPainter oldDelegate) {
    return oldDelegate.shimmer != shimmer ||
        oldDelegate.intensity != intensity ||
        oldDelegate.anchor != anchor;
  }
}
