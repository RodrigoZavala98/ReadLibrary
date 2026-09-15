import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';
import 'rich_html.dart';

/// El aspecto de un bloque, en un solo sitio.
///
/// Existe por una razón concreta: paginar es **medir** por un lado y **pintar**
/// por otro, y si las dos mitades no coinciden al píxel el texto se corta mal.
/// Un margen distinto, un interlineado que se aplica en un sitio y no en el
/// otro, y el fallo resultante es dificilísimo de perseguir porque todo parece
/// correcto.
///
/// Así que el estilo se decide aquí, y de aquí beben los dos: [HtmlBlockView]
/// para pintar y [Paginator] para medir. Nadie más inventa un margen.
abstract final class BlockLayout {
  /// Hueco entre bloques. Va debajo y no arriba para que el primer bloque de
  /// una página empiece pegado al borde superior.
  static const paragraphGap = 18.0;
  static const listGap = 10.0;
  static const headingTop = 12.0;
  static const headingBottom = 20.0;
  static const ruleGap = 22.0;
  static const ruleThickness = 1.0;
  static const imageGap = 14.0;

  /// Sangría de una cita: la barra del margen más el hueco hasta el texto.
  static const quoteBar = 3.0;
  static const quoteIndent = 16.0;

  /// Ancho de la columna donde va la viñeta o el número de una lista.
  static const markerWidth = 26.0;
  static const listIndent = 8.0;
  static const listDepthIndent = 16.0;

  /// Los márgenes que rodean al texto del bloque, sangrías incluidas.
  ///
  /// El que mide resta esto del ancho disponible; el que pinta lo aplica como
  /// relleno. Por eso la sangría de las listas y las citas está **aquí** y no
  /// dentro del widget.
  static EdgeInsets insetsOf(HtmlBlock block) => switch (block) {
    HtmlParagraph() => const EdgeInsets.only(bottom: paragraphGap),
    HtmlHeading() => const EdgeInsets.only(
      top: headingTop,
      bottom: headingBottom,
    ),
    HtmlQuote() => const EdgeInsets.only(
      left: quoteIndent + quoteBar,
      bottom: paragraphGap,
    ),
    HtmlListItem(:final depth) => EdgeInsets.only(
      left: listIndent + (depth - 1) * listDepthIndent + markerWidth,
      bottom: listGap,
    ),
    HtmlPre() => const EdgeInsets.only(bottom: paragraphGap),
    HtmlRule() => const EdgeInsets.symmetric(vertical: ruleGap),
    HtmlImage() => const EdgeInsets.symmetric(vertical: imageGap),
  };

  /// El texto del bloque con su estilo, o `null` si el bloque no es texto.
  static TextSpan? spanOf(HtmlBlock block, ReadingSettings settings) {
    final base = settings.toTextStyle();

    return switch (block) {
      HtmlParagraph(:final runs) => _span(runs, base),
      HtmlHeading(:final level, :final runs) => _span(
        runs,
        base.copyWith(
          fontSize: settings.fontSize * headingScale(level),
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
      HtmlQuote(:final runs) => _span(
        runs,
        base.copyWith(
          fontStyle: FontStyle.italic,
          color: settings.palette.muted,
        ),
      ),
      HtmlListItem(:final runs) => _span(runs, base),
      HtmlPre(:final text) => TextSpan(
        text: text,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontSize: settings.fontSize * 0.88,
        ),
      ),
      HtmlRule() || HtmlImage() => null,
    };
  }

  /// Escala del cuerpo de letra de un encabezado.
  ///
  /// Se corta en el nivel 3 porque a partir de ahí los encabezados de un EPUB
  /// son subdivisiones que no merecen más cuerpo que el texto: engordarlas
  /// rompe la mancha de la página.
  static double headingScale(int level) => switch (level) {
    1 => 1.55,
    2 => 1.32,
    3 => 1.15,
    _ => 1.0,
  };

  /// Altura del contenido cuando no es texto. `null` si lo es.
  static double? fixedHeightOf(HtmlBlock block) =>
      block is HtmlRule ? ruleThickness : null;

  /// Si el bloque se lleva una página para él solo.
  ///
  /// Sólo las imágenes. No se sabe lo que mide una imagen sin decodificarla, y
  /// decodificar cada una al paginar sería caro y podría fallar; dándole la
  /// página entera no hace falta saberlo. El precio es que un icono pequeño
  /// también se lleva su página.
  static bool ownPage(HtmlBlock block) => block is HtmlImage;

  /// Alto que ocupará [block] al pintarse en un ancho de [width].
  ///
  /// Incluye sus márgenes. Es la función de la que depende toda la paginación.
  static double measure(
    HtmlBlock block,
    ReadingSettings settings,
    double width,
  ) {
    final insets = insetsOf(block);
    final fixed = fixedHeightOf(block);
    if (fixed != null) return fixed + insets.vertical;

    final span = spanOf(block, settings);
    if (span == null) return insets.vertical;

    final painter = paint(span, width - insets.horizontal);
    final height = painter.height;
    painter.dispose();
    return height + insets.vertical;
  }

  /// Un `TextPainter` ya maquetado. Quien lo pida se encarga de liberarlo.
  ///
  /// El span se envuelve en otro con su mismo estilo porque es lo que hace
  /// `Text.rich` al pintarlo, y el envoltorio manda en las métricas del
  /// párrafo. Medir sin él da unos píxeles de menos, y con la paginación eso
  /// es una página desbordada.
  static TextPainter paint(TextSpan span, double width) {
    return TextPainter(
      text: TextSpan(style: span.style, children: [span]),
      textDirection: TextDirection.ltr,
      // El texto preformateado no se reajusta, pero el resto sí, y el ancho de
      // maquetado tiene que ser exactamente el que usará el widget.
      maxLines: null,
    )..layout(maxWidth: width);
  }

  static TextSpan _span(List<TextRun> runs, TextStyle base) {
    return TextSpan(
      style: base,
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
              // ninguna parte, porque el texto de alrededor pierde el sentido.
              decoration: run.link ? TextDecoration.underline : null,
            ),
          ),
      ],
    );
  }
}
