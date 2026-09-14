import 'dart:typed_data';

import 'book_format.dart';
import 'book_locator.dart';

/// Datos descriptivos de un libro, extraídos del propio fichero.
///
/// Todo es opcional salvo el título, porque los ficheros reales vienen mal
/// etiquetados con muchísima frecuencia. Cuando no hay metadatos, el nombre del
/// fichero hace de título.
class BookInfo {
  const BookInfo({
    required this.title,
    this.author,
    this.coverBytes,
    this.totalPages,
  });

  final String title;
  final String? author;

  /// Portada codificada como PNG o JPEG, tal y como venía en el fichero.
  /// Se guarda en disco aparte; no conviene arrastrarla en memoria.
  final Uint8List? coverBytes;

  /// Número de páginas, sólo para formatos de maqueta fija. En un EPUB no
  /// existe un número de páginas estable, así que aquí será `null`.
  final int? totalPages;
}

/// Un libro abierto y listo para leerse.
///
/// Cada formato implementa esta interfaz, y el resto de la aplicación no sabe
/// —ni necesita saber— si por debajo hay un ZIP, un PDF o un fichero de texto.
/// Esa es la razón de existir de esta capa: añadir FB2 en el futuro no debería
/// obligar a tocar ni una línea de la interfaz de usuario.
///
/// El ciclo de vida siempre es `open()` → uso → `dispose()`. Varias
/// implementaciones mantienen descriptores de fichero o memoria nativa abierta,
/// así que olvidar `dispose()` tiene coste real.
abstract interface class BookSource {
  BookFormat get format;

  /// Prepara el libro para leerse: abre el fichero, valida la cabecera y lee
  /// el índice. Las operaciones costosas deben ir en un Isolate, porque un
  /// cómic de 300 MB bloquearía la interfaz durante segundos.
  ///
  /// Lanza [BookOpenException] si el fichero está corrupto o no es del formato
  /// que decía su extensión.
  Future<void> open();

  /// Libera descriptores de fichero, memoria nativa y ficheros temporales.
  Future<void> dispose();

  /// Metadatos del libro. Sólo válido después de `open()`.
  BookInfo get info;

  /// Dónde empezar cuando no hay progreso guardado.
  BookLocator get startLocator;

  /// Avance normalizado entre 0 y 1, exclusivamente para la interfaz: barras
  /// de progreso y el «65 % completado» de la biblioteca.
  ///
  /// Es una aproximación y no debe usarse jamás para restaurar la posición;
  /// para eso está el [BookLocator], que sí es exacto.
  double progressAt(BookLocator locator);
}

/// Libros cuyas páginas son imágenes o maquetas inmutables: PDF y CBZ.
abstract interface class FixedLayoutSource implements BookSource {
  int get pageCount;

  /// Renderiza una página como mapa de bits.
  ///
  /// [targetWidth] es la anchura en píxeles físicos que necesita la pantalla.
  /// Pasarla permite que el PDF se rasterice a la resolución justa en lugar de
  /// generar imágenes enormes que luego hay que reducir.
  Future<Uint8List> renderPage(int pageIndex, {required int targetWidth});
}

/// Un capítulo dentro del índice de un libro re-maquetable.
class ChapterRef {
  const ChapterRef({
    required this.title,
    required this.index,
    required this.start,
  });

  final String title;
  final int index;

  /// Dónde empieza el capítulo, para saltar directamente desde el índice.
  final BookLocator start;
}

/// Libros de texto que se re-maquetan: EPUB, TXT y, en el futuro, FB2.
abstract interface class ReflowableSource implements BookSource {
  /// Índice del libro. Puede estar vacío: un TXT no tiene capítulos.
  List<ChapterRef> get chapters;

  /// Carga el contenido de un capítulo como HTML ya saneado.
  ///
  /// Se devuelve HTML —y no texto plano— porque hay que conservar cursivas,
  /// negritas, encabezados e imágenes intercaladas. El saneado es obligatorio:
  /// un EPUB es un fichero descargado de Internet y puede traer scripts.
  Future<String> loadChapter(int chapterIndex);
}

/// El fichero no se pudo abrir.
class BookOpenException implements Exception {
  const BookOpenException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'BookOpenException: $message';
}
