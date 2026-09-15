import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/book_source.dart';
import '../domain/reading_settings.dart';

/// El índice del libro, desde dentro de la lectura.
///
/// Devuelve el capítulo elegido, o `null` si se cierra sin elegir.
///
/// Funciona igual en TXT y en EPUB porque los dos formatos ya rellenan
/// `ReflowableSource.chapters`: en un EPUB son los documentos del lomo con su
/// título real; en un TXT, las partes en que se trocea el fichero. La pantalla
/// no necesita saber cuál de los dos está mirando.
Future<int?> showChaptersSheet(
  BuildContext context, {
  required List<ChapterRef> chapters,
  required int current,
  required ReadingSettings settings,
}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: settings.palette.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ChaptersSheet(
      chapters: chapters,
      current: current,
      settings: settings,
    ),
  );
}

class _ChaptersSheet extends StatelessWidget {
  const _ChaptersSheet({
    required this.chapters,
    required this.current,
    required this.settings,
  });

  final List<ChapterRef> chapters;
  final int current;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
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
              // Media pantalla: el índice de un libro largo no cabe entero, y
              // taparlo del todo rompe la sensación de seguir dentro del libro.
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
                onTap: () => Navigator.of(context).pop(i),
              ),
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
