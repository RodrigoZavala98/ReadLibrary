import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';
import 'rich_html.dart';

/// De dónde salen los bytes de una imagen del capítulo. `null` si no está.
typedef ImageResolver = Uint8List? Function(String src);

/// Pinta un bloque de [RichHtml] con la tipografía del lector.
///
/// El reparto es deliberado: [RichHtml] decide **qué** hay —y eso se prueba sin
/// pintar nada— y este widget decide **cómo se ve**, aplicando los
/// [ReadingSettings] que el usuario controla. El HTML no manda aquí: un EPUB
/// con su hoja de estilos se ve con la tipografía del lector, no con la suya.
class HtmlBlockView extends StatelessWidget {
  const HtmlBlockView({
    required this.block,
    required this.style,
    this.imageFor,
    super.key,
  });

  final HtmlBlock block;
  final ReadingSettings style;
  final ImageResolver? imageFor;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      HtmlParagraph(:final runs) => _spaced(
        Text.rich(
          _spanOf(runs, style.toTextStyle()),
          textAlign: TextAlign.justify,
        ),
      ),
      HtmlHeading(:final level, :final runs) => _heading(level, runs),
      HtmlQuote(:final runs) => _quote(runs),
      HtmlListItem(:final marker, :final runs, :final depth) => _listItem(
        marker,
        runs,
        depth,
      ),
      HtmlPre(:final text) => _pre(text),
      HtmlRule() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Divider(
          height: 1,
          thickness: 1,
          color: style.palette.muted.withValues(alpha: 0.35),
        ),
      ),
      HtmlImage(:final src, :final alt) => _image(src, alt),
    };
  }

  Widget _spaced(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 18), child: child);

  Widget _heading(int level, List<TextRun> runs) {
    // Escala descendente por nivel. Se corta en el 3 porque a partir de ahí los
    // encabezados de un EPUB son subdivisiones que no merecen más cuerpo que el
    // texto: engordarlos rompe la mancha de la página.
    final scale = switch (level) {
      1 => 1.55,
      2 => 1.32,
      3 => 1.15,
      _ => 1.0,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: Text.rich(
        _spanOf(
          runs,
          style.toTextStyle().copyWith(
            fontSize: style.fontSize * scale,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _quote(List<TextRun> runs) {
    return _spaced(
      Container(
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          // Una raya al margen en lugar de comillas o sangría a los dos lados:
          // se distingue de un vistazo sin robar anchura de línea, que en un
          // móvil es lo más escaso que hay.
          border: Border(
            left: BorderSide(
              color: style.palette.muted.withValues(alpha: 0.45),
              width: 3,
            ),
          ),
        ),
        child: Text.rich(
          _spanOf(
            runs,
            style.toTextStyle().copyWith(
              fontStyle: FontStyle.italic,
              color: style.palette.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _listItem(String marker, List<TextRun> runs, int depth) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10, left: 8.0 + (depth - 1) * 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              marker,
              style: style.toTextStyle().copyWith(color: style.palette.muted),
            ),
          ),
          Expanded(child: Text.rich(_spanOf(runs, style.toTextStyle()))),
        ],
      ),
    );
  }

  Widget _pre(String text) {
    return _spaced(
      // Con scroll horizontal propio: el texto preformateado no se puede
      // reajustar sin destruirlo, y cortarlo es peor que dejar arrastrarlo.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          text,
          style: style.toTextStyle().copyWith(
            fontFamily: 'monospace',
            fontSize: style.fontSize * 0.88,
          ),
        ),
      ),
    );
  }

  Widget _image(String src, String? alt) {
    final bytes = imageFor?.call(src);
    if (bytes == null) return _missingImage(alt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        // Un EPUB puede traer la imagen en un formato que Flutter no decodifica
        // —SVG, sobre todo, muy común en las cubiertas—. Se enseña el texto
        // alternativo en lugar del icono roto del sistema.
        errorBuilder: (_, _, _) => _missingImage(alt),
      ),
    );
  }

  Widget _missingImage(String? alt) {
    final text = (alt ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return _spaced(
      Text(
        text,
        textAlign: TextAlign.center,
        style: style.toTextStyle().copyWith(
          fontStyle: FontStyle.italic,
          fontSize: style.fontSize * 0.9,
          color: style.palette.muted,
        ),
      ),
    );
  }

  /// Convierte los trozos con énfasis en un `TextSpan` sobre [base].
  static TextSpan _spanOf(List<TextRun> runs, TextStyle base) {
    return TextSpan(
      children: [
        for (final run in runs)
          TextSpan(
            text: run.text,
            style: TextStyle(
              fontStyle: run.italic ? FontStyle.italic : null,
              fontWeight: run.bold ? FontWeight.w700 : null,
              fontFamily: run.code ? 'monospace' : null,
              // Los enlaces se subrayan pero no navegan todavía. Se marcan
              // igualmente: un enlace invisible es peor que uno que no lleva a
              // ninguna parte, porque el texto de alrededor deja de tener
              // sentido («ver la nota siguiente»).
              decoration: run.link ? TextDecoration.underline : null,
            ),
          ),
      ],
      style: base,
    );
  }
}
