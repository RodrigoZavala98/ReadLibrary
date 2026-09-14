import 'dart:convert';
import 'dart:io';

import '../domain/library_book.dart';
import 'library_book_codec.dart';
import 'library_repository.dart';

/// Guarda la biblioteca como un único fichero JSON.
///
/// Para cientos de libros esto sobra: el índice cabe holgadamente en memoria y
/// leerlo entero al arrancar cuesta milisegundos. Lo que sí exige cuidado es la
/// **escritura**, porque el fichero se reescribe completo en cada guardado y un
/// corte a mitad de operación dejaría la biblioteca truncada e ilegible.
///
/// De ahí el baile de ficheros de [_flush]: se escribe aparte, se conserva el
/// anterior como respaldo hasta que el nuevo está completo, y solo entonces se
/// descarta. En ningún instante existe un momento en que no haya al menos una
/// copia íntegra en disco.
class JsonLibraryRepository implements LibraryRepository {
  JsonLibraryRepository(this.indexFile);

  final File indexFile;

  File get _tempFile => File('${indexFile.path}.tmp');
  File get _backupFile => File('${indexFile.path}.bak');

  List<LibraryBook>? _cache;

  @override
  Future<List<LibraryBook>> loadAll() async {
    final books = await _ensureLoaded();
    final sorted = [...books];
    sorted.sort((a, b) {
      // Lo último que se abrió va primero; lo nunca abierto, por fecha de alta.
      final aDate = a.lastOpenedAt ?? a.addedAt;
      final bDate = b.lastOpenedAt ?? b.addedAt;
      return bDate.compareTo(aDate);
    });
    return sorted;
  }

  @override
  Future<LibraryBook?> byId(int id) async {
    final books = await _ensureLoaded();
    for (final book in books) {
      if (book.id == id) return book;
    }
    return null;
  }

  @override
  Future<void> save(LibraryBook book) async {
    final books = await _ensureLoaded();
    final index = books.indexWhere((b) => b.id == book.id);
    if (index >= 0) {
      books[index] = book;
    } else {
      books.add(book);
    }
    await _flush(books);
  }

  @override
  Future<void> delete(int id) async {
    final books = await _ensureLoaded();
    books.removeWhere((b) => b.id == id);
    await _flush(books);
  }

  @override
  Future<int> nextId() async {
    final books = await _ensureLoaded();
    var maximum = 0;
    for (final book in books) {
      if (book.id > maximum) maximum = book.id;
    }
    return maximum + 1;
  }

  Future<List<LibraryBook>> _ensureLoaded() async {
    return _cache ??= await _readFromDisk();
  }

  Future<List<LibraryBook>> _readFromDisk() async {
    var source = indexFile;

    // Si el índice no está pero sí el respaldo, la aplicación murió justo entre
    // los dos renombrados de un guardado anterior. El respaldo es íntegro.
    if (!await source.exists()) {
      if (await _backupFile.exists()) {
        source = _backupFile;
      } else {
        return [];
      }
    }

    final Object? parsed;
    try {
      parsed = jsonDecode(await source.readAsString());
    } on Object {
      // El índice está corrupto. Se aparta en lugar de borrarlo: así se puede
      // inspeccionar después, y el usuario empieza con una biblioteca vacía en
      // lugar de con una aplicación que no arranca.
      await _quarantine(source);
      return [];
    }

    if (parsed is! Map || parsed['books'] is! List) {
      await _quarantine(source);
      return [];
    }

    final books = <LibraryBook>[];
    for (final entry in parsed['books'] as List) {
      final book = LibraryBookCodec.decode(entry);
      if (book != null) books.add(book);
    }
    return books;
  }

  Future<void> _quarantine(File file) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${indexFile.path}.corrupt.$stamp');
    } on FileSystemException {
      // Si ni siquiera se puede apartar, se sigue con la biblioteca vacía: no
      // merece la pena impedir el arranque por esto.
    }
  }

  Future<void> _flush(List<LibraryBook> books) async {
    _cache = books;

    final payload = jsonEncode({
      'version': 1,
      'books': [for (final book in books) LibraryBookCodec.encode(book)],
    });

    await indexFile.parent.create(recursive: true);

    // 1. El contenido nuevo se escribe aparte. `flush` fuerza el volcado a
    //    disco: sin él, el sistema operativo podría tener los datos aún en
    //    caché cuando se ejecute el renombrado.
    await _tempFile.writeAsString(payload, flush: true);

    // 2. El índice actual pasa a ser el respaldo.
    if (await indexFile.exists()) {
      if (await _backupFile.exists()) await _backupFile.delete();
      await indexFile.rename(_backupFile.path);
    }

    // 3. El nuevo ocupa su lugar.
    await _tempFile.rename(indexFile.path);

    // 4. Y solo ahora se puede tirar el respaldo.
    if (await _backupFile.exists()) await _backupFile.delete();
  }
}
