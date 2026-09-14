import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/library_book.dart';

/// Traduce entre [LibraryBook] y el mapa que se guarda en JSON.
///
/// Vive en la capa de datos y no en el modelo a propósito: el dominio no tiene
/// por qué saber en qué formato se le guarda.
///
/// La regla que gobierna todo este fichero: **un dato corrupto nunca debe
/// impedir abrir la biblioteca**. Un campo ilegible se descarta y el libro se
/// carga sin él; solo si falta algo imprescindible —identificador, ruta o
/// formato— se descarta la entrada entera. Perder la posición de lectura de un
/// libro es molesto; perder la biblioteca completa es imperdonable.
abstract final class LibraryBookCodec {
  static Map<String, Object?> encode(LibraryBook book) => {
    'id': book.id,
    'filePath': book.filePath,
    'format': book.format.name,
    'title': book.title,
    if (book.author != null) 'author': book.author,
    if (book.coverPath != null) 'coverPath': book.coverPath,
    'addedAt': book.addedAt.toUtc().toIso8601String(),
    if (book.lastOpenedAt != null)
      'lastOpenedAt': book.lastOpenedAt!.toUtc().toIso8601String(),
    if (book.encodedLocator != null) 'locator': book.encodedLocator,
    'progress': book.progress,
    if (book.totalPages != null) 'totalPages': book.totalPages,
    if (book.collection != null) 'collection': book.collection,
    if (book.fingerprint != null) 'fingerprint': book.fingerprint,
  };

  /// Reconstruye un libro. Devuelve `null` si la entrada no es recuperable.
  static LibraryBook? decode(Object? raw) {
    if (raw is! Map) return null;

    final id = _asInt(raw['id']);
    final filePath = _asString(raw['filePath']);
    final format = _asFormat(raw['format']);
    final title = _asString(raw['title']);
    if (id == null || filePath == null || format == null || title == null) {
      return null;
    }

    final addedAt = _asDate(raw['addedAt']);

    return LibraryBook(
      id: id,
      filePath: filePath,
      format: format,
      title: title,
      // Si la fecha de alta es ilegible, se usa la época en lugar de descartar
      // el libro: solo afecta al orden en que aparece la lista.
      addedAt: addedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      author: _asString(raw['author']),
      coverPath: _asString(raw['coverPath']),
      lastOpenedAt: _asDate(raw['lastOpenedAt']),
      locator: _asLocator(raw['locator'], format),
      progress: _asProgress(raw['progress']),
      totalPages: _asInt(raw['totalPages']),
      collection: _asString(raw['collection']),
      fingerprint: _asString(raw['fingerprint']),
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final double v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };

  static String? _asString(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static BookFormat? _asFormat(Object? value) {
    if (value is! String) return null;
    for (final format in BookFormat.values) {
      if (format.name == value) return format;
    }
    // Un formato desconocido significa que el índice lo escribió una versión
    // más nueva de la aplicación. Se descarta la entrada, no el fichero.
    return null;
  }

  static DateTime? _asDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static BookLocator? _asLocator(Object? value, BookFormat format) {
    if (value is! String) return null;
    return BookLocator.decode(value, format);
  }

  static double _asProgress(Object? value) {
    final number = switch (value) {
      final num v => v.toDouble(),
      final String v => double.tryParse(v),
      _ => null,
    };
    if (number == null || number.isNaN) return 0;
    return number.clamp(0.0, 1.0);
  }
}
