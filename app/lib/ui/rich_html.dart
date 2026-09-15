import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Un trozo de texto con su énfasis. La unidad más pequeña del renderizador.
class TextRun {
  const TextRun(
    this.text, {
    this.italic = false,
    this.bold = false,
    this.code = false,
    this.link = false,
  });

  final String text;
  final bool italic;
  final bool bold;
  final bool code;

  /// Se pinta distinto, pero no navega: ver [RichHtml].
  final bool link;

  TextRun withText(String other) => TextRun(
    other,
    italic: italic,
    bold: bold,
    code: code,
    link: link,
  );

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      other.italic == italic &&
      other.bold == bold &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, italic, bold, code, link);

  @override
  String toString() {
    final marks = [
      if (italic) 'i',
      if (bold) 'b',
      if (code) 'code',
      if (link) 'a',
    ];
    return marks.isEmpty ? '«$text»' : '«$text»(${marks.join(',')})';
  }
}

/// Un bloque del documento, ya listo para pintarse.
sealed class HtmlBlock {
  const HtmlBlock();
}

final class HtmlParagraph extends HtmlBlock {
  const HtmlParagraph(this.runs);
  final List<TextRun> runs;
}

final class HtmlHeading extends HtmlBlock {
  const HtmlHeading(this.level, this.runs);

  /// De 1 a 6, como en HTML.
  final int level;
  final List<TextRun> runs;
}

final class HtmlQuote extends HtmlBlock {
  const HtmlQuote(this.runs);
  final List<TextRun> runs;
}

final class HtmlListItem extends HtmlBlock {
  const HtmlListItem({
    required this.marker,
    required this.runs,
    required this.depth,
  });

  /// «•» o «3.», ya resuelto: la numeración se lleva al analizar, no al pintar.
  final String marker;
  final List<TextRun> runs;
  final int depth;
}

/// Texto con los espacios tal cual venían: código, versos maquetados a mano.
final class HtmlPre extends HtmlBlock {
  const HtmlPre(this.text);
  final String text;
}

final class HtmlRule extends HtmlBlock {
  const HtmlRule();
}

final class HtmlImage extends HtmlBlock {
  const HtmlImage(this.src, {this.alt});
  final String src;
  final String? alt;
}

/// Convierte el XHTML de un capítulo en bloques que el lector sabe pintar.
///
/// Sustituye a un `SimpleHtml` que sólo entendía los `<p>` que generaba el
/// lector de TXT. El HTML de un EPUB es arbitrario: viene con encabezados,
/// citas, listas, imágenes y estilos propios.
///
/// **No se pinta con un WebView ni con un renderizador genérico** a propósito.
/// En un lector la tipografía es el producto: el tamaño, el interlineado y los
/// márgenes los manda `ReadingStyle`, y un motor ajeno no deja afinarlos. De
/// paso sale gratis algo que con WebView costaría vigilancia: **el `<script>`
/// de un EPUB descargado de cualquier sitio no se ejecuta nunca**, porque aquí
/// no hay nada capaz de ejecutarlo.
///
/// Lo que esta versión deja fuera, a sabiendas:
///
///  - El **CSS del EPUB** se descarta entero. Es la decisión de fondo: manda la
///    tipografía del lector.
///  - Las **tablas** se aplanan a una línea por fila, con las celdas separadas
///    por «·». Son rarísimas en narrativa, y una tabla de verdad —con anchos,
///    combinaciones de celdas y desbordamiento horizontal— es otro trabajo.
///  - Los **enlaces internos** se pintan distintos pero no llevan a ninguna
///    parte todavía.
abstract final class RichHtml {
  static List<HtmlBlock> parse(String xhtml) {
    final document = html_parser.parse(xhtml);
    final walker = _Walker();
    // Si no hay `<body>` —fragmentos sueltos, que es lo que produce el lector
    // de TXT— se recorre lo que haya.
    walker.visitAll((document.body ?? document.documentElement)?.nodes ?? []);
    walker.flush();
    return walker.blocks;
  }

  /// El texto pelado de unos bloques. Para pruebas y para medir.
  static String plainText(List<HtmlBlock> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      final runs = switch (block) {
        HtmlParagraph(:final runs) => runs,
        HtmlHeading(:final runs) => runs,
        HtmlQuote(:final runs) => runs,
        HtmlListItem(:final runs) => runs,
        HtmlPre(:final text) => [TextRun(text)],
        HtmlRule() || HtmlImage() => const <TextRun>[],
      };
      for (final run in runs) {
        buffer.write(run.text);
      }
      buffer.write('\n');
    }
    return buffer.toString();
  }
}

/// Qué clase de bloque se está construyendo ahora mismo.
enum _Kind { paragraph, quote, listItem }

class _Walker {
  final blocks = <HtmlBlock>[];

  List<TextRun> _runs = [];
  _Kind _kind = _Kind.paragraph;
  int _headingLevel = 0;
  String _marker = '';
  int _depth = 0;

  /// Contadores de las listas numeradas abiertas, una por nivel de anidamiento.
  final _counters = <int>[];

  static const _skip = {'script', 'style', 'head', 'title', 'meta', 'link'};

  static const _inline = {
    'a', 'abbr', 'b', 'bdi', 'bdo', 'big', 'cite', 'code', 'dfn', 'em', 'i',
    'kbd', 'mark', 'q', 'ruby', 's', 'samp', 'small', 'span', 'strike',
    'strong', 'sub', 'sup', 'time', 'tt', 'u', 'var', 'wbr',
  };

  /// Envoltorios que no significan nada por sí mismos: se atraviesan.
  static const _containers = {
    'div', 'section', 'article', 'aside', 'header', 'footer', 'main', 'nav',
    'figure', 'figcaption', 'body', 'html', 'dl', 'dd', 'dt', 'details',
  };

  void visitAll(List<dom.Node> nodes, [_Marks marks = const _Marks()]) {
    for (final node in nodes) {
      _visit(node, marks: marks);
    }
  }

  void _visit(dom.Node node, {_Marks marks = const _Marks()}) {
    if (node is dom.Text) {
      _append(node.text, marks);
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';
    if (_skip.contains(tag)) return;

    switch (tag) {
      case 'br':
        // Un salto duro dentro del mismo párrafo: es lo que mantiene los versos
        // separados cuando el resto de espacios se colapsa.
        _runs.add(const TextRun('\n'));
      case 'img' || 'image':
        _emitImage(node);
      case 'hr':
        flush();
        blocks.add(const HtmlRule());
      case 'p':
        _block(_Kind.paragraph, node, marks);
      case 'blockquote':
        _block(_Kind.quote, node, marks);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _heading(int.parse(tag.substring(1)), node, marks);
      case 'ul' || 'ol':
        _list(tag == 'ol', node, marks);
      case 'li':
        _listItem(node, marks);
      case 'pre':
        flush();
        final text = node.text.trimRight();
        if (text.trim().isNotEmpty) blocks.add(HtmlPre(text));
      case 'table':
        _table(node, marks);
      default:
        if (_inline.contains(tag)) {
          visitAll(node.nodes, marks.of(tag));
        } else if (_containers.contains(tag)) {
          visitAll(node.nodes, marks);
        } else {
          // Etiqueta desconocida: se atraviesa. Un EPUB puede traer cualquier
          // cosa, y perder el texto de dentro es peor que ignorar la etiqueta.
          visitAll(node.nodes, marks);
        }
    }
  }

  /// Un bloque de texto: se cierra lo que hubiera abierto, se recoge lo de
  /// dentro y se cierra otra vez.
  void _block(_Kind kind, dom.Element element, _Marks marks) {
    flush();
    _kind = kind;
    visitAll(element.nodes, marks);
    flush();
    _kind = _Kind.paragraph;
  }

  void _heading(int level, dom.Element element, _Marks marks) {
    flush();
    _headingLevel = level;
    visitAll(element.nodes, marks);
    flush();
    _headingLevel = 0;
  }

  void _list(bool ordered, dom.Element element, _Marks marks) {
    flush();
    _counters.add(ordered ? 0 : -1);
    _depth++;
    visitAll(element.nodes, marks);
    _depth--;
    _counters.removeLast();
    flush();
  }

  void _listItem(dom.Element element, _Marks marks) {
    flush();
    // Un `<li>` suelto, sin lista alrededor, también se pinta: los EPUB mal
    // convertidos los tienen.
    if (_counters.isEmpty) {
      _counters.add(-1);
      _depth++;
    }

    final counter = _counters.last;
    if (counter >= 0) {
      _counters[_counters.length - 1] = counter + 1;
      _marker = '${counter + 1}.';
    } else {
      _marker = '•';
    }

    _kind = _Kind.listItem;
    visitAll(element.nodes, marks);
    flush();
    _kind = _Kind.paragraph;
    _marker = '';
  }

  /// Una tabla aplanada: una línea por fila, celdas separadas por «·».
  void _table(dom.Element element, _Marks marks) {
    flush();
    for (final row in element.querySelectorAll('tr')) {
      final cells = row.children.where(
        (cell) => cell.localName == 'td' || cell.localName == 'th',
      );
      var first = true;
      for (final cell in cells) {
        if (!first) _runs.add(const TextRun(' · '));
        first = false;
        visitAll(cell.nodes, marks);
      }
      flush();
    }
  }

  void _emitImage(dom.Element element) {
    final src =
        element.attributes['src'] ??
        element.attributes['xlink:href'] ??
        element.attributes['href'];
    if (src == null || src.trim().isEmpty) return;

    // La imagen rompe el párrafo en dos en lugar de esperar a que acabe: si no,
    // saldría descolocada respecto al texto que la rodea.
    flush();
    blocks.add(HtmlImage(src.trim(), alt: element.attributes['alt']));
  }

  void _append(String text, _Marks marks) {
    // Colapsar los espacios es la regla de HTML, y es lo que hace que un
    // capítulo maquetado con saltos de línea cada ochenta columnas —lo normal
    // en un EPUB— se lea como párrafos y no como una escalera.
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return;
    if (collapsed == ' ' && _runs.isEmpty) return;

    _runs.add(
      TextRun(
        collapsed,
        italic: marks.italic,
        bold: marks.bold,
        code: marks.code,
        link: marks.link,
      ),
    );
  }

  /// Cierra el bloque en construcción, si tiene algo dentro.
  void flush() {
    final runs = _trim(_runs);
    _runs = [];
    if (runs.isEmpty) return;

    blocks.add(
      switch (_headingLevel) {
        > 0 => HtmlHeading(_headingLevel, runs),
        _ => switch (_kind) {
          _Kind.paragraph => HtmlParagraph(runs),
          _Kind.quote => HtmlQuote(runs),
          _Kind.listItem => HtmlListItem(
            marker: _marker,
            runs: runs,
            depth: _depth,
          ),
        },
      },
    );
  }

  /// Quita el espacio de los bordes del bloque, que viene de la sangría del
  /// propio fichero y no del texto.
  static List<TextRun> _trim(List<TextRun> runs) {
    final result = [...runs];
    while (result.isNotEmpty) {
      final first = result.first.withText(result.first.text.trimLeft());
      if (first.text.isEmpty) {
        result.removeAt(0);
        continue;
      }
      result[0] = first;
      break;
    }
    while (result.isNotEmpty) {
      final last = result.last.withText(result.last.text.trimRight());
      if (last.text.isEmpty) {
        result.removeLast();
        continue;
      }
      result[result.length - 1] = last;
      break;
    }
    return result;
  }
}

/// Los énfasis activos en el punto del árbol que se está recorriendo.
class _Marks {
  const _Marks({
    this.italic = false,
    this.bold = false,
    this.code = false,
    this.link = false,
  });

  final bool italic;
  final bool bold;
  final bool code;
  final bool link;

  _Marks of(String tag) => switch (tag) {
    'em' || 'i' || 'cite' || 'dfn' || 'var' => _copy(italic: true),
    'strong' || 'b' => _copy(bold: true),
    'code' || 'kbd' || 'samp' || 'tt' => _copy(code: true),
    'a' => _copy(link: true),
    _ => this,
  };

  _Marks _copy({bool? italic, bool? bold, bool? code, bool? link}) => _Marks(
    italic: italic ?? this.italic,
    bold: bold ?? this.bold,
    code: code ?? this.code,
    link: link ?? this.link,
  );
}
