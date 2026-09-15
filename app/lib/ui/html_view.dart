import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';
import 'block_layout.dart';
import 'rich_html.dart';

/// De dónde salen los bytes de una imagen del capítulo. `null` si no está.
typedef ImageResolver = Uint8List? Function(String src);

/// Pinta un bloque de [RichHtml] con la tipografía del lector.
///
/// El reparto es deliberado: [RichHtml] decide **qué** hay —y eso se prueba sin
/// pintar nada—, [BlockLayout] decide **cuánto ocupa** y este widget sólo lo
/// pone en pantalla. El HTML no manda aquí: un EPUB con su hoja de estilos se
/// ve con la tipografía del lector, no con la suya.
///
/// Ni un margen ni un tamaño se deciden en este fichero. Todos salen de
/// [BlockLayout], porque son los mismos números con los que el paginador mide,
/// y si se separasen el texto se cortaría mal al pasar de página.
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
    final insets = BlockLayout.insetsOf(block);
    final span = BlockLayout.spanOf(block, style);

    return switch (block) {
      HtmlParagraph() => Padding(
        padding: insets,
        child: _text(span!, align: TextAlign.justify),
      ),
      HtmlHeading() => Padding(padding: insets, child: _text(span!)),
      HtmlQuote() => _quote(insets, span!),
      HtmlListItem(:final marker) => _listItem(insets, span!, marker),
      HtmlPre() => _pre(insets, span!),
      HtmlRule() => Padding(
        padding: insets,
        child: Divider(
          height: BlockLayout.ruleThickness,
          thickness: BlockLayout.ruleThickness,
          color: style.palette.muted.withValues(alpha: 0.35),
        ),
      ),
      HtmlImage(:final src, :final alt) => Padding(
        padding: insets,
        child: _image(src, alt),
      ),
    };
  }

  Widget _quote(EdgeInsets insets, TextSpan span) {
    return Container(
      // La barra se pinta dentro del hueco que el paginador ya ha contado: el
      // relleno es la sangría menos el grosor de la barra.
      padding: insets.copyWith(left: insets.left - BlockLayout.quoteBar),
      decoration: BoxDecoration(
        // Una raya al margen en lugar de comillas o sangría a los dos lados: se
        // distingue de un vistazo sin robar anchura de línea, que en un móvil
        // es lo más escaso que hay.
        border: Border(
          left: BorderSide(
            color: style.palette.muted.withValues(alpha: 0.45),
            width: BlockLayout.quoteBar,
          ),
        ),
      ),
      child: _text(span),
    );
  }

  Widget _listItem(EdgeInsets insets, TextSpan span, String marker) {
    return Padding(
      padding: insets.copyWith(left: insets.left - BlockLayout.markerWidth),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: BlockLayout.markerWidth,
            child: Text(
              marker,
              style: style.toTextStyle().copyWith(color: style.palette.muted),
            ),
          ),
          Expanded(child: _text(span)),
        ],
      ),
    );
  }

  Widget _pre(EdgeInsets insets, TextSpan span) {
    return Padding(
      padding: insets,
      // Con scroll horizontal propio: el texto preformateado no se puede
      // reajustar sin destruirlo, y cortarlo es peor que dejar arrastrarlo.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _text(span),
      ),
    );
  }

  /// El texto de un bloque, pintado **exactamente como se midió**.
  ///
  /// Dos precauciones, y las dos vienen de que paginar exige que medir y pintar
  /// den el mismo número al píxel:
  ///
  /// `Text.rich` envuelve el span en otro con el estilo ambiente, y ese
  /// envoltorio manda en las métricas del párrafo. Por eso se fija el ambiente
  /// al mismo estilo del bloque, que es el envoltorio que `BlockLayout.paint`
  /// replica al medir. Sin esto la página desbordaba por unos píxeles.
  ///
  /// Y se ignora la escala de fuente del sistema: en un lector con su propio
  /// control de tamaño el cuerpo lo elige el usuario aquí dentro, y además una
  /// escala que el paginador no conoce descuadraría el reparto.
  Widget _text(TextSpan span, {TextAlign align = TextAlign.start}) {
    return DefaultTextStyle(
      style: span.style!,
      child: Text.rich(
        span,
        textAlign: align,
        textScaler: TextScaler.noScaling,
      ),
    );
  }

  Widget _image(String src, String? alt) {
    final bytes = imageFor?.call(src);
    if (bytes == null) return _missingImage(alt);

    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      // Un EPUB puede traer la imagen en un formato que Flutter no decodifica
      // —SVG, sobre todo, muy común en las cubiertas—. Se enseña el texto
      // alternativo en lugar del icono roto del sistema.
      errorBuilder: (_, _, _) => _missingImage(alt),
    );
  }

  Widget _missingImage(String? alt) {
    final text = (alt ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      textAlign: TextAlign.center,
      style: style.toTextStyle().copyWith(
        fontStyle: FontStyle.italic,
        fontSize: style.fontSize * 0.9,
        color: style.palette.muted,
      ),
    );
  }
}
