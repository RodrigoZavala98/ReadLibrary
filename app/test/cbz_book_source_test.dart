import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/book_source.dart';
import 'package:lector/formats/cbz_book_source.dart';

import 'archive_fixture.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_cbz_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  File ficheroEn(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name');

  /// Escribe un cómic en disco sin abrirlo.
  Future<File> escribir(
    Uint8List bytes, {
    String name = 'comic.cbz',
  }) async {
    final file = ficheroEn(name);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Escribe un CBZ y devuelve su fuente, ya abierta.
  Future<CbzBookSource> abrir(
    Map<String, Object> entries, {
    String name = 'comic.cbz',
  }) async {
    final source = CbzBookSource(await escribir(zipOf(entries), name: name));
    await source.open();
    return source;
  }

  /// Un cómic sano de tres páginas.
  Map<String, Object> comicDeTres() => {
    'pagina1.png': pngBytes(grey: 1),
    'pagina2.png': pngBytes(grey: 2),
    'pagina3.png': pngBytes(grey: 3),
  };

  group('apertura', () {
    test('abre un CBZ y cuenta sus páginas', () async {
      final source = await abrir(comicDeTres(), name: 'El_cómic.cbz');
      addTearDown(source.dispose);

      expect(source.format, BookFormat.cbz);
      expect(source.pageCount, 3);
      expect(source.info.title, 'El cómic');
      // A diferencia de un EPUB, aquí el número de páginas sí es estable.
      expect(source.info.totalPages, 3);
    });

    test('un .cbt es un TAR y se abre igual', () async {
      final source = CbzBookSource(
        await escribir(tarOf(comicDeTres()), name: 'comic.cbt'),
      );
      addTearDown(source.dispose);
      await source.open();

      expect(source.pageCount, 3);
    });

    test('abrir dos veces no duplica las páginas', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      await source.open();
      expect(source.pageCount, 3);
    });
  });

  group('orden de las páginas', () {
    test('se ordenan por su número, no por su texto', () async {
      final source = await abrir({
        'p10.png': pngBytes(grey: 10),
        'p2.png': pngBytes(grey: 2),
        'p1.png': pngBytes(grey: 1),
      });
      addTearDown(source.dispose);

      // Un CBZ no declara el orden en ninguna parte: es el de los nombres. Sin
      // orden natural, la página 10 sería la segunda del cómic.
      expect(await grisDe(source, 0), 1);
      expect(await grisDe(source, 1), 2);
      expect(await grisDe(source, 2), 10);
    });
  });

  group('lo que no es una página', () {
    test('la basura de macOS no cuenta como páginas', () async {
      // Un fork de recursos pesa unos bytes y no es una imagen. Colarlo
      // duplicaría el cómic entero y la mitad de las páginas saldrían rotas.
      final source = await abrir({
        ...comicDeTres(),
        '__MACOSX/._pagina1.png': [0, 1, 2, 3],
        '__MACOSX/._pagina2.png': [0, 1, 2, 3],
        '._pagina3.png': [0, 1, 2, 3],
      });
      addTearDown(source.dispose);

      expect(source.pageCount, 3);
    });

    test('los ficheros que no son imágenes se ignoran', () async {
      final source = await abrir({
        ...comicDeTres(),
        'ComicInfo.xml': '<ComicInfo><Series>Lo que sea</Series></ComicInfo>',
        'Thumbs.db': [0, 1, 2],
        'creditos.txt': 'traducido por alguien',
      });
      addTearDown(source.dispose);

      expect(source.pageCount, 3);
    });

    test('una entrada vacía no es una página', () async {
      final source = await abrir({...comicDeTres(), 'pagina4.png': <int>[]});
      addTearDown(source.dispose);

      expect(source.pageCount, 3);
    });
  });

  group('ficheros que no se pueden leer', () {
    test('un .cbz que por dentro es un RAR se explica', () async {
      // El caso más habitual de todos: alguien renombra un .cbr a .cbz.
      final rar = Uint8List.fromList([
        0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00,
        ...List.filled(100, 0),
      ]);
      final source = CbzBookSource(await escribir(rar));

      await expectLater(
        source.open(),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'message',
            allOf(contains('RAR'), contains('Conviértelo')),
          ),
        ),
      );
    });

    test('un fichero que no es ni ZIP ni TAR se explica', () async {
      final source = CbzBookSource(
        await escribir(Uint8List.fromList(List.filled(400, 0x41))),
      );

      await expectLater(
        source.open(),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'message',
            contains('no es un cómic'),
          ),
        ),
      );
    });

    test('un ZIP sin imágenes dentro se explica', () async {
      final source = CbzBookSource(
        await escribir(zipOf({'leeme.txt': 'aquí no hay cómic'})),
      );

      await expectLater(
        source.open(),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'message',
            contains('ninguna imagen'),
          ),
        ),
      );
    });

    test('un fichero que ya no está se explica', () async {
      final source = CbzBookSource(ficheroEn('no_existe.cbz'));

      await expectLater(source.open(), throwsA(isA<BookOpenException>()));
    });
  });

  group('posición y avance', () {
    test('empieza por la primera página', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      expect(source.startLocator, const PageLocator(0));
    });

    test('la última página es el cien por cien', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      expect(source.progressAt(const PageLocator(0)), 0);
      expect(source.progressAt(const PageLocator(1)), closeTo(0.5, 0.001));
      expect(source.progressAt(const PageLocator(2)), 1);
    });

    test('un cómic de una sola página está leído en cuanto se abre', () async {
      final source = await abrir({'unica.png': pngBytes()});
      addTearDown(source.dispose);

      // Está entero a la vista: dejarlo al 0 % sería mentir.
      expect(source.progressAt(const PageLocator(0)), 1);
    });

    test('un localizador de otro formato no rompe el avance', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      expect(source.progressAt(const CharLocator(500)), 0);
    });

    test('una página más allá del final se queda en el cien por cien', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      expect(source.progressAt(const PageLocator(99)), 1);
    });
  });

  group('páginas', () {
    test('devuelve los bytes tal cual venían', () async {
      final esperado = pngBytes(grey: 7);
      final source = await abrir({'p1.png': esperado});
      addTearDown(source.dispose);

      expect(await source.renderPage(0, targetWidth: 1080), esperado);
    });

    test('pedir una página que no existe es un error de programación', () async {
      final source = await abrir(comicDeTres());
      addTearDown(source.dispose);

      expect(
        () => source.renderPage(3, targetWidth: 1080),
        throwsA(isA<RangeError>()),
      );
    });

    test('pedir una página sin abrir el cómic avisa', () async {
      final source = CbzBookSource(await escribir(zipOf(comicDeTres())));

      expect(
        () => source.renderPage(0, targetWidth: 1080),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('cierre', () {
    test('después de cerrar se puede borrar el fichero', () async {
      // En Windows un archivo abierto impide borrar el fichero, y la
      // biblioteca tiene que poder quitar un libro.
      final file = await escribir(zipOf(comicDeTres()));
      final source = CbzBookSource(file);
      await source.open();
      await source.dispose();

      await file.delete();
      expect(file.existsSync(), isFalse);
    });

    test('cerrar dos veces no falla', () async {
      final source = await abrir(comicDeTres());
      await source.dispose();

      await expectLater(source.dispose(), completes);
    });
  });
}

/// El tono de gris con que se pintó una página, que sirve para reconocerla.
///
/// Las páginas se fabrican con un gris distinto cada una, así que leer el
/// píxel de una imagen de 1×1 dice exactamente qué página se devolvió. Es la
/// única forma de comprobar el **orden** sin depender del nombre del fichero,
/// que es justo lo que está bajo prueba.
Future<int> grisDe(CbzBookSource source, int pageIndex) async {
  final bytes = await source.renderPage(pageIndex, targetWidth: 100);
  // El primer byte del bloque IDAT descomprimido es el filtro de la fila; el
  // siguiente es el componente rojo del único píxel.
  final png = pngBytes(grey: 0);
  expect(bytes.length, png.length, reason: 'las páginas miden todas igual');
  // Se compara contra la imagen fabricada con cada gris hasta dar con el suyo.
  for (var grey = 0; grey <= 255; grey++) {
    if (_sameBytes(bytes, pngBytes(grey: grey))) return grey;
  }
  fail('la página $pageIndex no es ninguna de las fabricadas');
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
