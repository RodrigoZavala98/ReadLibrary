import 'book_format.dart';
import 'book_locator.dart';

/// Un libro tal y como vive en la biblioteca del usuario.
///
/// Esto es lo que se guarda en la base de datos. Deliberadamente no contiene el
/// contenido del libro ni la portada en bytes: sólo rutas y metadatos. La
/// biblioteca puede tener cientos de entradas y se carga entera para pintar la
/// cuadrícula, así que cada campo aquí se paga multiplicado.
///
/// Todavía sin anotaciones de Isar: el generador de código se añade cuando el
/// modelo esté estable, para no estar regenerando en cada cambio.
class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.filePath,
    required this.format,
    required this.title,
    required this.addedAt,
    this.author,
    this.coverPath,
    this.lastOpenedAt,
    this.locator,
    this.progress = 0,
    this.totalPages,
    this.collection,
    this.fingerprint,
  });

  final int id;

  /// Ruta al fichero dentro del almacenamiento privado de la aplicación.
  ///
  /// Importante: **nunca** una ruta al almacenamiento externo. Desde Android 11
  /// el acceso directo a ficheros del usuario está restringido, y el permiso
  /// MANAGE_EXTERNAL_STORAGE es motivo de rechazo en Google Play salvo
  /// justificación excepcional. El flujo correcto es: el usuario elige el
  /// fichero con el selector del sistema y nosotros lo copiamos aquí.
  final String filePath;

  final BookFormat format;
  final String title;
  final String? author;

  /// Ruta a la portada ya extraída y guardada como fichero aparte.
  final String? coverPath;

  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  /// Posición exacta de lectura. `null` si nunca se ha abierto.
  final BookLocator? locator;

  /// Avance entre 0 y 1. Redundante con [locator], pero se guarda aparte
  /// porque la biblioteca necesita pintar la barra de progreso de cientos de
  /// libros sin abrir ni uno solo de ellos.
  final double progress;

  /// Sólo para formatos de maqueta fija.
  final int? totalPages;

  /// Carpeta o estantería a la que pertenece. `null` es la raíz.
  final String? collection;

  /// Huella del fichero original, para reconocer que un libro ya está en la
  /// biblioteca aunque se importe desde otra carpeta o con otro nombre.
  final String? fingerprint;

  /// Si el lector ya se ha puesto con él.
  ///
  /// No basta con mirar el progreso. Un texto que cabe entero en pantalla no
  /// genera desplazamiento, así que su avance se queda en cero exacto por mucho
  /// rato que se haya pasado leyéndolo. Haberlo abierto alguna vez ya cuenta.
  bool get isStarted => progress > 0 || lastOpenedAt != null;

  /// Se considera terminado al 99 %: en un EPUB casi nunca se llega al 100 %
  /// exacto, porque el último salto suele caer en la página de créditos.
  bool get isFinished => progress >= 0.99;

  /// Cómo se guarda la posición en la base de datos.
  String? get encodedLocator => locator?.encode();

  LibraryBook copyWith({
    String? title,
    String? author,
    String? coverPath,
    DateTime? lastOpenedAt,
    BookLocator? locator,
    double? progress,
    int? totalPages,
    String? collection,
  }) {
    return LibraryBook(
      id: id,
      filePath: filePath,
      format: format,
      addedAt: addedAt,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      locator: locator ?? this.locator,
      progress: progress ?? this.progress,
      totalPages: totalPages ?? this.totalPages,
      collection: collection ?? this.collection,
      fingerprint: fingerprint,
    );
  }
}
