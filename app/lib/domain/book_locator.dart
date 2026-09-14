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
      case 'cfi':
        locator = value.isEmpty ? null : CfiLocator(value);
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
    CfiLocator() => format == BookFormat.epub,
  };

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

/// Posición en EPUB, expresada como EPUB CFI.
///
/// Un CFI es la forma estándar de señalar un punto concreto dentro de un EPUB
/// —capítulo, nodo y desplazamiento—, del estilo
/// `epubcfi(/6/14[chap05ref]!/4[body01]/10/2/1:0)`. Sobrevive a cualquier
/// cambio de tipografía o tamaño de pantalla, que es exactamente el motivo de
/// usarlo en lugar de un número de página.
final class CfiLocator extends BookLocator {
  const CfiLocator(this.cfi) : assert(cfi != '');

  final String cfi;

  @override
  String encode() => 'cfi:$cfi';

  @override
  bool operator ==(Object other) => other is CfiLocator && other.cfi == cfi;

  @override
  int get hashCode => Object.hash('cfi', cfi);

  @override
  String toString() => 'CfiLocator($cfi)';
}
