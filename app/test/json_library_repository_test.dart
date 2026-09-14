import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/data/json_library_repository.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/library_book.dart';

void main() {
  late Directory temp;
  late File indexFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_repo_');
    indexFile = File('${temp.path}${Platform.pathSeparator}library.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Una instancia nueva cada vez, para que las comprobaciones lean de disco y
  /// no de la caché en memoria.
  JsonLibraryRepository abrir() => JsonLibraryRepository(indexFile);

  LibraryBook libro(int id, {String title = 'Dune', DateTime? abierto}) =>
      LibraryBook(
        id: id,
        filePath: '/datos/$id.epub',
        format: BookFormat.epub,
        title: title,
        addedAt: DateTime(2026, 3, id),
        lastOpenedAt: abierto,
      );

  group('operaciones básicas', () {
    test('una biblioteca sin fichero está vacía', () async {
      expect(await abrir().loadAll(), isEmpty);
    });

    test('lo guardado se recupera en otra sesión', () async {
      await abrir().save(libro(1));

      final recuperados = await abrir().loadAll();
      expect(recuperados, hasLength(1));
      expect(recuperados.single.title, 'Dune');
    });

    test('guardar con un id existente reemplaza, no duplica', () async {
      final repo = abrir();
      await repo.save(libro(1, title: 'Dune'));
      await repo.save(libro(1, title: 'Dune (revisado)'));

      final todos = await abrir().loadAll();
      expect(todos, hasLength(1));
      expect(todos.single.title, 'Dune (revisado)');
    });

    test('se puede recuperar un libro por su id', () async {
      await abrir().save(libro(3));
      expect((await abrir().byId(3))!.id, 3);
      expect(await abrir().byId(99), isNull);
    });

    test('borrar lo quita del índice', () async {
      final repo = abrir();
      await repo.save(libro(1));
      await repo.save(libro(2));
      await repo.delete(1);

      final todos = await abrir().loadAll();
      expect(todos.map((b) => b.id), [2]);
    });

    test('los identificadores nuevos no chocan con los existentes', () async {
      expect(await abrir().nextId(), 1);

      final repo = abrir();
      await repo.save(libro(1));
      await repo.save(libro(7));
      expect(await abrir().nextId(), 8);
    });

    test('la posición de lectura sobrevive a cerrar la aplicación', () async {
      await abrir().save(
        LibraryBook(
          id: 1,
          filePath: '/datos/1.txt',
          format: BookFormat.txt,
          title: 'Notas',
          addedAt: DateTime(2026, 3, 1),
          locator: const CharLocator(148302),
          progress: 0.42,
        ),
      );

      final recuperado = (await abrir().loadAll()).single;
      expect(recuperado.locator, const CharLocator(148302));
      expect(recuperado.progress, closeTo(0.42, 0.0001));
    });
  });

  test('la lista se ordena por lo último abierto', () async {
    final repo = abrir();
    await repo.save(libro(1, abierto: DateTime(2026, 3, 10)));
    await repo.save(libro(2, abierto: DateTime(2026, 3, 14)));
    await repo.save(libro(3)); // nunca abierto, alta el 3 de marzo

    expect((await abrir().loadAll()).map((b) => b.id), [2, 1, 3]);
  });

  group('resistencia a ficheros dañados', () {
    test('un JSON corrupto no impide arrancar, y se aparta para inspección',
        () async {
      await indexFile.writeAsString('{esto no es json valido');

      expect(await abrir().loadAll(), isEmpty);

      final apartados = temp
          .listSync()
          .where((f) => f.path.contains('.corrupt.'))
          .toList();
      expect(apartados, hasLength(1), reason: 'se conserva, no se borra');
    });

    test('un JSON válido con la forma equivocada también se aparta', () async {
      await indexFile.writeAsString('[1, 2, 3]');
      expect(await abrir().loadAll(), isEmpty);
      expect(
        temp.listSync().where((f) => f.path.contains('.corrupt.')),
        hasLength(1),
      );
    });

    test('las entradas ilegibles se saltan sin perder las buenas', () async {
      await indexFile.writeAsString(
        jsonEncode({
          'version': 1,
          'books': [
            {'basura': true},
            {
              'id': 5,
              'filePath': '/datos/5.epub',
              'format': 'epub',
              'title': 'El bueno',
              'addedAt': '2026-03-01T00:00:00.000Z',
              'progress': 0,
            },
            null,
            {'id': 6, 'format': 'formato_del_futuro'},
          ],
        }),
      );

      final todos = await abrir().loadAll();
      expect(todos, hasLength(1));
      expect(todos.single.title, 'El bueno');
    });
  });

  group('escritura atómica', () {
    test('no deja ficheros temporales detrás', () async {
      await abrir().save(libro(1));

      final sobrantes = temp
          .listSync()
          .map((f) => f.path)
          .where((p) => p.endsWith('.tmp') || p.endsWith('.bak'));
      expect(sobrantes, isEmpty);
    });

    test('si la aplicación muere entre renombrados, el respaldo salva el día',
        () async {
      final repo = abrir();
      await repo.save(libro(1));
      await repo.save(libro(2));

      // Se simula el instante exacto en que el índice ya pasó a respaldo pero
      // el fichero nuevo todavía no ocupó su lugar.
      final backup = File('${indexFile.path}.bak');
      await indexFile.rename(backup.path);
      expect(await indexFile.exists(), isFalse);

      final recuperados = await abrir().loadAll();
      expect(
        recuperados.map((b) => b.id),
        containsAll([1, 2]),
        reason: 'la biblioteca se recupera del respaldo',
      );
    });

    test('crea el directorio si no existe', () async {
      final anidado = File(
        '${temp.path}${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b${Platform.pathSeparator}library.json',
      );
      await JsonLibraryRepository(anidado).save(libro(1));
      expect(await anidado.exists(), isTrue);
    });
  });
}
