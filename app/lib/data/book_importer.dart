import 'dart:io';

import '../domain/book_format.dart';
import '../domain/library_book.dart';
import '../formats/file_naming.dart';
import 'book_fingerprint.dart';
import 'library_repository.dart';

/// Qué pasó al intentar añadir un fichero a la biblioteca.
///
/// Se modela con un tipo cerrado en lugar de devolver `null` o lanzar
/// excepciones porque cada desenlace merece un mensaje distinto en pantalla.
/// «No reconozco este fichero» y «este formato aún no está disponible» son
/// cosas muy diferentes para quien acaba de elegir un libro.
sealed class ImportResult {
  const ImportResult();
}

final class ImportedOk extends ImportResult {
  const ImportedOk(this.book);
  final LibraryBook book;
}

/// El fichero ya estaba, con el mismo contenido. No se duplica.
final class AlreadyInLibrary extends ImportResult {
  const AlreadyInLibrary(this.existing);
  final LibraryBook existing;
}

/// Se reconoce el formato pero todavía no se sabe abrir.
final class UnsupportedFormat extends ImportResult {
  const UnsupportedFormat(this.format, this.reason);
  final BookFormat format;
  final String reason;
}

/// La extensión no corresponde a ningún formato de libro.
final class UnknownFormat extends ImportResult {
  const UnknownFormat(this.fileName);
  final String fileName;
}

final class ImportFailed extends ImportResult {
  const ImportFailed(this.message);
  final String message;
}

/// Copia un fichero elegido por el usuario a la biblioteca y lo registra.
///
/// La copia no es opcional. Desde Android 11 la aplicación no puede volver a
/// leer sin más una ruta del almacenamiento del usuario: el permiso concedido
/// por el selector del sistema es temporal y se pierde al reiniciar. Un libro
/// que solo se referenciase por su ruta original dejaría de abrirse al día
/// siguiente. Por eso todo lo que entra en la biblioteca se copia al
/// almacenamiento privado de la aplicación.
class BookImporter {
  BookImporter({required this.repository, required this.libraryDir});

  final LibraryRepository repository;

  /// Carpeta privada donde viven las copias.
  final Directory libraryDir;

  static const _reasons = {
    BookFormat.pdf:
        'El soporte para PDF todavía está en camino. Los cómics en CBZ sí se '
        'pueden leer ya.',
    BookFormat.cbr:
        'Los CBR son archivos RAR, y no existe forma de descomprimirlos '
        'legalmente desde Dart. Conviértelo a CBZ y funcionará.',
    BookFormat.fb2: 'El soporte para FB2 todavía está en camino.',
    BookFormat.rtf: 'El soporte para RTF todavía está en camino.',
  };

  Future<ImportResult> import(File source) async {
    if (!await source.exists()) {
      return const ImportFailed('El fichero ya no está disponible.');
    }

    final fileName = source.path.split(RegExp(r'[/\\]')).last;
    final format = BookFormat.fromFileName(fileName);
    if (format == null) return UnknownFormat(fileName);
    if (!format.isSupported) {
      return UnsupportedFormat(
        format,
        _reasons[format] ?? 'Este formato todavía no está disponible.',
      );
    }

    final String fingerprint;
    try {
      fingerprint = await BookFingerprint.ofFile(source);
    } on FileSystemException catch (error) {
      return ImportFailed('No se pudo leer el fichero: ${error.message}');
    }

    // Se compara por contenido y no por nombre: el mismo libro descargado dos
    // veces suele llegar como «dune.epub» y «dune (1).epub».
    for (final book in await repository.loadAll()) {
      if (book.fingerprint != null && book.fingerprint == fingerprint) {
        return AlreadyInLibrary(book);
      }
    }

    final File copy;
    try {
      copy = await _copyIntoLibrary(source, fileName);
    } on FileSystemException catch (error) {
      return ImportFailed('No se pudo copiar el libro: ${error.message}');
    }

    final book = LibraryBook(
      id: await repository.nextId(),
      filePath: copy.path,
      format: format,
      title: titleFromFileName(fileName),
      addedAt: DateTime.now(),
      fingerprint: fingerprint,
    );
    await repository.save(book);
    return ImportedOk(book);
  }

  Future<File> _copyIntoLibrary(File source, String fileName) async {
    await libraryDir.create(recursive: true);

    final safe = safeFileName(fileName);
    var target = File('${libraryDir.path}${Platform.pathSeparator}$safe');

    // Dos libros distintos pueden llamarse igual. Si el nombre está ocupado se
    // le añade un sufijo en lugar de pisar el fichero que ya estaba.
    if (await target.exists()) {
      final dot = safe.lastIndexOf('.');
      final stem = dot > 0 ? safe.substring(0, dot) : safe;
      final ext = dot > 0 ? safe.substring(dot) : '';
      var n = 2;
      while (await target.exists()) {
        target = File(
          '${libraryDir.path}${Platform.pathSeparator}$stem ($n)$ext',
        );
        n++;
      }
    }

    return source.copy(target.path);
  }
}
