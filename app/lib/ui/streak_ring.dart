import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// El anillo de racha: días encadenados en el centro, avance de hoy en el aro.
///
/// Se dibuja con un [CustomPainter] en lugar de apilar widgets porque hace
/// falta un arco con extremos redondeados, un degradado que recorra el trazo y
/// un fondo exacto detrás. Componer eso con `CircularProgressIndicator` y
/// recortes sale más frágil y peor rematado que doce líneas de canvas.
class StreakRing extends StatelessWidget {
  const StreakRing({
    required this.days,
    required this.todayProgress,
    required this.atRisk,
    this.size = 96,
    super.key,
  });

  /// Días consecutivos cumpliendo la meta.
  final int days;

  /// Avance de hoy sobre la meta, de 0 a 1.
  final double todayProgress;

  /// La racha sigue viva pero hoy todavía no se ha leído.
  final bool atRisk;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: days == 0
          ? 'Sin racha. Has leído el ${(todayProgress * 100).round()} por '
                'ciento de tu meta de hoy.'
          : '$days días de racha. Hoy llevas el '
                '${(todayProgress * 100).round()} por ciento de tu meta.',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: todayProgress, atRisk: atRisk),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$days',
                  style: TextStyle(
                    fontSize: size * 0.30,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: ChromeTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  days == 1 ? 'día' : 'días',
                  style: TextStyle(
                    fontSize: size * 0.12,
                    color: ChromeTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.atRisk});

  final double progress;
  final bool atRisk;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = ChromeTheme.surfaceHigh;
    canvas.drawArc(circle, 0, math.pi * 2, false, track);

    if (progress <= 0) return;

    // Empieza arriba y avanza en el sentido de las agujas del reloj.
    const start = -math.pi / 2;
    final sweep = math.pi * 2 * progress.clamp(0.0, 1.0);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + math.pi * 2,
        colors: atRisk
            // En riesgo el aro se apaga a un ámbar tenue: informa sin regañar.
            ? const [Color(0xFF8A5A3B), ChromeTheme.accent]
            : const [ChromeTheme.accent, ChromeTheme.accentSoft],
        transform: GradientRotation(start),
      ).createShader(circle);

    canvas.drawArc(circle, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.atRisk != atRisk;
}
