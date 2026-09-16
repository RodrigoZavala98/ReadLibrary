import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/data/book_importer.dart';
import 'package:lector/data/json_library_repository.dart';
import 'package:lector/domain/book_format.dart';

void main() {
  late Directory temp;
  late Directory entrada;
  late Directory biblioteca;
  late BookImporter importer;
  late JsonLibraryRepository repo;

  String ruta(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_import_');
    entrada = await Directory(ruta(temp, 'descargas')).create();
    biblioteca = Directory(ruta(temp, 'biblioteca'));
    repo = JsonLibraryRepository(File(ruta(temp, 'library.json')));
    importer = BookImporter(repository: repo, libraryDir: biblioteca);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<File> crear(String name, [String contenido = 'Hola.\n\nAdiós.']) async {
    final file = File(ruta(entrada, name));
    await file.writeAsString(contenido);
    return file;
  }

  group('importación correcta', () {
    test('copia el fichero y lo registra', () async {
      final result = await importer.import(await crear('Dune.txt'));

      expect(result, isA<ImportedOk>());
      final book = (result as ImportedOk).book;
      expect(book.title, 'Dune');
      expect(book.format, BookFormat.txt);
      expect(await repo.loadAll(), hasLength(1));
    });

    test('el libro queda dentro de la biblioteca, no en su sitio original',
        () async {
      final origen = await crear('Dune.txt');
      final book = (await importer.import(origen) as ImportedOk).book;

      expect(
        book.filePath.startsWith(biblioteca.path),
        isTrue,
        reason: 'la ruta original deja de ser accesible en Android 11+',
      );
      expect(await File(book.filePath).exists(), isTrue);
      expect(await origen.exists(), isTrue, reason: 'se copia, no se mueve');
    });

    test('el título se limpia de guiones bajos', () async {
      final result = await importer.import(
        await crear('El_nombre_del_viento.txt'),
      );
      expect((result as ImportedOk).book.title, 'El nombre del viento');
    });

    test('dos libros distintos con el mismo nombre conviven', () async {
      await importer.import(await crear('libro.txt', 'Primer contenido.'));

      final otraCarpeta = await Directory(ruta(temp, 'otra')).create();
      final segundo = File(ruta(otraCarpeta, 'libro.txt'));
      await segundo.writeAsString('Contenido completamente distinto.');
      final result = await importer.import(segundo);

      expect(result, isA<ImportedOk>());
      expect(await repo.loadAll(), hasLength(2));
      expect(
        biblioteca.listSync(),
        hasLength(2),
        reason: 'el segundo no debe pisar al primero',
      );
    });
  });

  group('duplicados', () {
    test('importar el mismo fichero dos veces no lo duplica', () async {
      final file = await crear('Dune.txt');
      await importer.import(file);
      final segundo = await importer.import(file);

      expect(segundo, isA<AlreadyInLibrary>());
      expect(await repo.loadAll(), hasLength(1));
    });

    test('se detecta por contenido, aunque cambie el nombre', () async {
      const contenido = 'El mismo libro exacto.\n\nSegundo párrafo.';
      await importer.import(await crear('dune.txt', contenido));
      final result = await importer.import(await crear('dune (1).txt', contenido));

      expect(result, isA<AlreadyInLibrary>());
      expect(await repo.loadAll(), hasLength(1));
    });
  });

  group('ficheros que no se pueden importar', () {
    test('un CBR se rechaza explicando por qué', () async {
      final result = await importer.import(await crear('comic.cbr'));

      expect(result, isA<UnsupportedFormat>());
      final r = result as UnsupportedFormat;
      expect(r.format, BookFormat.cbr);
      expect(r.reason, contains('RAR'));
      expect(await repo.loadAll(), isEmpty);
    });

    test('un PDF se rechaza al importarlo, no al abrirlo', () async {
      // El rechazo tiene que ocurrir aquí. Mientras PDF estuvo marcado como
      // soportado sin tener lector, el fichero se copiaba al almacenamiento
      // privado y entraba en la biblioteca, y el usuario sólo se enteraba de
      // que no se podía leer al tocarlo.
      final result = await importer.import(await crear('manual.pdf'));

      expect(result, isA<UnsupportedFormat>());
      final r = result as UnsupportedFormat;
      expect(r.format, BookFormat.pdf);
      expect(r.reason, contains('PDF'));
      expect(await repo.loadAll(), isEmpty);
    });

    test('un CBZ sí se importa: ése ya se lee', () async {
      final result = await importer.import(await crear('comic.cbz'));

      expect(result, isA<ImportedOk>());
      expect((result as ImportedOk).book.format, BookFormat.cbz);
    });

    test('FB2 y RTF también dan un motivo', () async {
      for (final name in ['libro.fb2', 'doc.rtf']) {
        final result = await importer.import(await crear(name));
        expect(result, isA<UnsupportedFormat>(), reason: name);
        expect((result as UnsupportedFormat).reason, isNotEmpty);
      }
    });

    test('una extensión desconocida se distingue de un formato pendiente',
        () async {
      final result = await importer.import(await crear('foto.jpg'));
      expect(result, isA<UnknownFormat>());
      expect((result as UnknownFormat).fileName, 'foto.jpg');
    });

    test('un fichero inexistente da un fallo con mensaje, no una excepción',
        () async {
      final result = await importer.import(File(ruta(entrada, 'fantasma.txt')));
      expect(result, isA<ImportFailed>());
      expect((result as ImportFailed).message, isNotEmpty);
    });
  });

  group('saneado del nombre de fichero', () {
    test('un nombre con separadores de ruta no escribe fuera de la carpeta',
        () async {
      // No se puede crear un fichero así, pero sí llegar un nombre así desde
      // un selector o un intent malicioso. El destino debe quedar dentro.
      final origen = await crear('normal.txt');
      final book = (await importer.import(origen) as ImportedOk).book;
      final parent = File(book.filePath).parent.path;
      expect(parent, biblioteca.path);
    });
  });
}
