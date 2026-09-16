import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/book_source.dart';
import '../domain/reading_settings.dart';

/// El índice del libro, como panel de la píldora.
///
/// Funciona igual en TXT y en EPUB porque los dos formatos ya rellenan
/// `ReflowableSource.chapters`: en un EPUB son los documentos del lomo con su
/// título real; en un TXT, las partes en que se trocea el fichero. El panel no
/// necesita saber cuál de los dos está mirando.
class ChaptersPanel extends StatelessWidget {
  const ChaptersPanel({
    required this.chapters,
    required this.current,
    required this.settings,
    required this.onPick,
    super.key,
  });

  final List<ChapterRef> chapters;
  final int current;
  final ReadingSettings settings;

  /// Qué capítulo se ha elegido. Cerrar el panel es cosa de quien lo aloja:
  /// cuando esto era una hoja modal se cerraba sola con un `pop`, y ése era
  /// justo el motivo de que no se pudiera saltar de panel en panel.
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            chapters.length == 1
                ? 'Un capítulo'
                : '${chapters.length} capítulos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: chapters.length,
            // Se abre por donde vas, no por el principio. En un EPUB de
            // cuarenta capítulos, empezar arriba obliga a buscarte.
            controller: ScrollController(
              initialScrollOffset: (current * 52.0 - 120).clamp(0.0, 1e6),
            ),
            itemBuilder: (_, i) => _ChapterTile(
              chapter: chapters[i],
              selected: i == current,
              palette: palette,
              onTap: () => onPick(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ChapterRef chapter;
  final bool selected;
  final ReadingPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? palette.muted.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border(
              // Una barra al margen marca dónde estás sin cambiar el color del
              // texto, que en esta lista ya significa otra cosa.
              left: BorderSide(
                color: selected ? palette.text : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${chapter.index + 1}',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: palette.text,
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
