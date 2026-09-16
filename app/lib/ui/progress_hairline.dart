import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// El hilo de avance del borde inferior, con su porcentaje.
///
/// Se ve **siempre**, no sólo con los controles fuera. Es una revisión
/// consciente del «dentro del libro no hay cromo»: saber por dónde vas era
/// justo lo que faltaba, y un hilo de dos píxeles en el margen no compite con
/// el texto.
///
/// Escucha a un `ValueNotifier` en lugar de recibir un número: así se repinta
/// él solo mientras el dedo arrastra, sin reconstruir el capítulo entero —con
/// sus imágenes— sesenta veces por segundo.
class ProgressHairline extends StatelessWidget {
  const ProgressHairline({
    required this.progress,
    required this.palette,
    super.key,
  });

  final ValueListenable<double> progress;
  final ReadingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Text(
                  '${(value * 100).round()} %',
                  style: TextStyle(
                    fontSize: 10,
                    color: palette.muted.withValues(alpha: 0.7),
                  ),
                ),
              ),
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  backgroundColor: palette.muted.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(
                    palette.muted.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
