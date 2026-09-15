import 'book_format.dart';

/// Un punto exacto dentro de un libro.
///
/// Esta es la decisión de diseño central del lector, y conviene entender por
/// qué no es simplemente un `int paginaActual`.
///
/// En un PDF o un cómic, la página 24 es la página 24 siempre: en tu móvil, en
/// una tablet y dentro de tres años. En un EPUB no existe tal cosa. El texto se
/// re-maqueta, y si el usuario sube el tamaño de letra, lo que era la página 47
/// pasa a ser la 61. Guardar un número de página en un EPUB significa perder el
/// sitio del lector cada vez que toque los ajustes de tipografía.
///
/// Por eso la posición se guarda como un localizador **opaco y propio de cada
/// formato**, y el porcentaje de avance se lleva aparte, sólo para la interfaz.
/// La interfaz nunca interpreta el contenido de un localizador: lo guarda y se
/// lo devuelve al lector correspondiente.
sealed class BookLocator {
  const BookLocator();

  /// Representación en texto para guardar en base de datos.
  String encode();

  /// Reconstruye un localizador a partir de [encoded] y el formato del libro.
  ///
  /// Devuelve `null` si la cadena está corrupta o pertenece a otro formato, en
  /// cuyo caso el lector debe abrir el libro por el principio en lugar de
  /// fallar: perder la posición es molesto, pero no poder abrir el libro lo es
  /// mucho más.
  static BookLocator? decode(String encoded, BookFormat format) {
    final separator = encoded.indexOf(':');
    if (separator == -1) return null;
    final kind = encoded.substring(0, separator);
    final value = encoded.substring(separator + 1);

    final BookLocator? locator;
    switch (kind) {
      case 'page':
        final page = _nonNegative(value);
        locator = page == null ? null : PageLocator(page);
      case 'char':
        final offset = _nonNegative(value);
        locator = offset == null ? null : CharLocator(offset);
      case 'epub':
        locator = _parseEpub(value);
      default:
        locator = null;
    }

    // Un localizador guardado para otro formato no sirve: aplicar un número de
    // página a un EPUB daría una posición sin sentido. Mejor empezar de cero.
    if (locator == null || !locator.suitsFormat(format)) return null;
    return locator;
  }

  /// Si este tipo de localizador tiene sentido para [format].
  bool suitsFormat(BookFormat format) => switch (this) {
    PageLocator() => format.layout == LayoutKind.fixed,
    CharLocator() => format == BookFormat.txt,
    EpubLocator() => format == BookFormat.epub,
  };

  /// «7/432»: documento del lomo y milésimas dentro de él.
  static EpubLocator? _parseEpub(String value) {
    final slash = value.indexOf('/');
    if (slash == -1) return null;
    final spine = _nonNegative(value.substring(0, slash));
    final permille = _nonNegative(value.substring(slash + 1));
    if (spine == null || permille == null || permille > 1000) return null;
    return EpubLocator(spine, permille);
  }

  static int? _nonNegative(String value) {
    final parsed = int.tryParse(value);
    return (parsed != null && parsed >= 0) ? parsed : null;
  }
}

/// Posición en formatos de maqueta fija: índice de página empezando en cero.
///
/// PDF y CBZ.
final class PageLocator extends BookLocator {
  const PageLocator(this.pageIndex) : assert(pageIndex >= 0);

  final int pageIndex;

  @override
  String encode() => 'page:$pageIndex';

  @override
  bool operator ==(Object other) =>
      other is PageLocator && other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash('page', pageIndex);

  @override
  String toString() => 'PageLocator($pageIndex)';
}

/// Posición en texto plano: desplazamiento en caracteres desde el inicio.
///
/// TXT. Es estable frente a cambios de tipografía, que es justo lo que se
/// necesita.
final class CharLocator extends BookLocator {
  const CharLocator(this.charOffset) : assert(charOffset >= 0);

  final int charOffset;

  @override
  String encode() => 'char:$charOffset';

  @override
  bool operator ==(Object other) =>
      other is CharLocator && other.charOffset == charOffset;

  @override
  int get hashCode => Object.hash('char', charOffset);

  @override
  String toString() => 'CharLocator($charOffset)';
}

/// Posición en un EPUB: documento del lomo y milésimas recorridas dentro de él.
///
/// No es un EPUB CFI, que sería el estándar. Un CFI señala un nodo concreto del
/// árbol del documento, y generarlo o resolverlo exige tener ese árbol delante:
/// funciona cuando el que pinta el libro es Epub.js, que fue el motor que se
/// descartó. Con un renderizador propio, un CFI sería una cadena que nadie
/// sabría interpretar.
///
/// A cambio se guarda el documento del lomo —que es estable, es un fichero
/// dentro del ZIP— y la fracción recorrida dentro de él en milésimas. Sobrevive
/// a cualquier cambio de tipografía, que es el motivo de todo esto. Lo que no
/// da es el carácter exacto: devuelve a la misma pantalla, no a la misma
/// palabra. El tramo sobre el que se aproxima es un capítulo, del mismo orden
/// que el fragmento sobre el que ya aproxima el lector de TXT.
final class EpubLocator extends BookLocator {
  const EpubLocator(this.spineIndex, this.permille)
    : assert(spineIndex >= 0),
      assert(permille >= 0 && permille <= 1000);

  /// Milésimas y no un `double` porque esto se guarda en JSON y se compara:
  /// un entero va y vuelve idéntico, y 0,1 + 0,2 no.
  factory EpubLocator.atFraction(int spineIndex, double fraction) =>
      EpubLocator(spineIndex, (fraction.clamp(0.0, 1.0) * 1000).round());

  final int spineIndex;
  final int permille;

  double get fraction => permille / 1000;

  @override
  String encode() => 'epub:$spineIndex/$permille';

  @override
  bool operator ==(Object other) =>
      other is EpubLocator &&
      other.spineIndex == spineIndex &&
      other.permille == permille;

  @override
  int get hashCode => Object.hash('epub', spineIndex, permille);

  @override
  String toString() => 'EpubLocator($spineIndex, $permille‰)';
}
