import 'package:flutter/material.dart';

import '../domain/reading_settings.dart';

/// La hoja de ajustes de un cómic.
///
/// Es propia y no la de lectura porque de aquellos ajustes no sirve ni uno:
/// cuerpo de letra, interlineado, margen y tipografía no quieren decir nada
/// sobre un mapa de bits. Lo único que hay que decidir en un cómic es hacia
/// dónde se pasa la página.
///
/// El valor que edita es **global**, el mismo que guarda el resto de ajustes de
/// lectura, pero se edita desde aquí: obligar a abrir una novela para cambiar
/// cómo se leen los mangas no tendría ningún sentido.
///
/// Se pinta en oscuro, como el propio lector de cómics, y no con los colores de
/// papel del tema de lectura.
Future<void> showComicSettingsSheet(
  BuildContext context, {
  required ComicDirection current,
  required ValueChanged<ComicDirection> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // Sin oscurecer lo de detrás: como en la hoja de lectura, la gracia es ver
    // el efecto sobre la página que hay debajo.
    barrierColor: Colors.black12,
    builder: (_) => _ComicSettingsSheet(current: current, onChanged: onChanged),
  );
}

class _ComicSettingsSheet extends StatefulWidget {
  const _ComicSettingsSheet({required this.current, required this.onChanged});

  final ComicDirection current;
  final ValueChanged<ComicDirection> onChanged;

  @override
  State<_ComicSettingsSheet> createState() => _ComicSettingsSheetState();
}

class _ComicSettingsSheetState extends State<_ComicSettingsSheet> {
  late ComicDirection _direction = widget.current;

  static const _surface = Color(0xFF161616);
  static const _text = Color(0xFFECECEC);
  static const _muted = Color(0xFF9A9A9A);

  void _choose(ComicDirection next) {
    setState(() => _direction = next);
    // Se guarda en el acto, sin botón de aceptar, como la hoja de lectura: si
    // la aplicación muere con la hoja abierta, lo elegido ya está en el disco.
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Sentido de lectura',
            style: TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Un manga se lee al revés que un cómic occidental, y el fichero no '
            'dice cuál es cuál.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          RadioGroup<ComicDirection>(
            groupValue: _direction,
            onChanged: (chosen) {
              if (chosen != null) _choose(chosen);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in ComicDirection.values)
                  RadioListTile<ComicDirection>(
                    value: option,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: _text,
                    title: Text(
                      option.label,
                      style: const TextStyle(color: _text, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
