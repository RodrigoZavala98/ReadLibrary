import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/book_source.dart';
import 'package:lector/formats/epub_book_source.dart';

import 'epub_fixture.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_epub_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Escribe un EPUB en disco y devuelve su fuente, ya abierta.
  Future<EpubBookSource> abrir(
    Map<String, Object> entries, {
    String name = 'libro.epub',
  }) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(zipOf(entries));
    final source = EpubBookSource(file);
    await source.open();
    return source;
  }

  test('abre un EPUB y saca sus metadatos', () async {
    final source = await abrir(sampleEpub2());
    addTearDown(source.dispose);

    expect(source.format, BookFormat.epub);
    expect(source.info.title, 'El libro');
    expect(source.info.author, 'Quien sea');
    // Un EPUB no tiene un número de páginas estable: se re-maqueta.
    expect(source.info.totalPages, isNull);
  });

  test('sin título en el EPUB usa el nombre del fichero', () async {
    final source = await abrir({
      ...sampleEpub2(),
      'OEBPS/content.opf': opf2(title: null),
    }, name: 'El_nombre_del_viento.epub');
    addTearDown(source.dispose);

    expect(source.info.title, 'El nombre del viento');
  });

  test('el índice lleva un capítulo por documento del lomo', () async {
    final source = await abrir(sampleEpub2());
    addTearDown(source.dispose);

    expect(source.chapters.length, 2);
    expect(source.chapters.first.title, 'El principio');
    expect(source.chapters.first.start, const EpubLocator(0, 0));
    expect(source.chapters.last.start, const EpubLocator(1, 0));
  });

  test('carga el contenido de un capítulo', () async {
    final source = await abrir(sampleEpub2());
    addTearDown(source.dispose);

    expect(await source.loadChapter(0), contains('Primera página'));
    expect(await source.loadChapter(1), contains('Última página'));
  });

  test('un capítulo fuera de rango es un error de programación', () async {
    final source = await abrir(sampleEpub2());
    addTearDown(source.dispose);

    expect(() => source.loadChapter(9), throwsRangeError);
    expect(() => source.loadChapter(-1), throwsRangeError);
  });

  test('un documento que el lomo promete y el ZIP no tiene no tumba el libro',
      () async {
    // Pasa en EPUB mal empaquetados. Perder un capítulo es malo; perder el
    // libro entero por un capítulo es peor.
    final entries = {...sampleEpub2()}..remove('OEBPS/c2.xhtml');
    final source = await abrir(entries);
    addTearDown(source.dispose);

    expect(await source.loadChapter(1), contains('falta'));
    expect(await source.loadChapter(0), contains('Primera página'));
  });

  test('un fichero que ya no está se explica al abrir', () async {
    final source = EpubBookSource(File('${temp.path}/no_existe.epub'));
    expect(source.open, throwsA(isA<BookOpenException>()));
  });

  group('posición', () {
    test('empieza al principio del primer documento', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.startLocator, const EpubLocator(0, 0));
    });

    test('el localizador dice qué capítulo cargar', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.chapterIndexFor(const EpubLocator(1, 500)), 1);
    });

    test('un localizador de otro formato abre por el principio', () async {
      // No es un error: es lo que pasa cuando se reemplaza el fichero de un
      // libro por otro de distinto formato.
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.chapterIndexFor(const CharLocator(5000)), 0);
      expect(source.fractionWithin(0, const CharLocator(5000)), 0);
    });

    test('un capítulo que ya no existe se recorta al último', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.chapterIndexFor(const EpubLocator(99, 0)), 1);
    });

    test('la fracción sólo cuenta dentro de su propio capítulo', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.fractionWithin(1, const EpubLocator(1, 250)), 0.25);
      expect(source.fractionWithin(0, const EpubLocator(1, 250)), 0);
    });

    test('ir y volver entre fracción y localizador no pierde nada', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      final locator = source.locatorAt(1, 0.4);
      expect(locator, const EpubLocator(1, 400));
      expect(source.fractionWithin(1, locator), 0.4);
    });
  });

  group('progreso', () {
    test('crece a lo largo del libro', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      final inicio = source.progressAt(const EpubLocator(0, 0));
      final medio = source.progressAt(const EpubLocator(0, 1000));
      final final_ = source.progressAt(const EpubLocator(1, 1000));

      expect(inicio, 0);
      expect(medio, greaterThan(0));
      expect(final_, closeTo(1, 0.001));
      expect(medio, lessThan(final_));
    });

    test('reparte según lo que pesa cada capítulo, no a partes iguales',
        () async {
      // Un capítulo mucho más largo que el otro vale mucho más del avance:
      // terminarlo no puede marcar el 50 % si es casi todo el libro.
      final source = await abrir({
        ...sampleEpub2(),
        'OEBPS/c1.xhtml': chapterXhtml('<p>${'palabra ' * 2000}</p>'),
      });
      addTearDown(source.dispose);

      expect(source.progressAt(const EpubLocator(1, 0)), greaterThan(0.9));
    });

    test('un localizador de otro formato no mueve la barra', () async {
      final source = await abrir(sampleEpub2());
      addTearDown(source.dispose);

      expect(source.progressAt(const CharLocator(900)), 0);
    });
  });

  group('imágenes', () {
    Map<String, Object> conImagen() => {
      'META-INF/container.xml': containerFor('OEBPS/content.opf'),
      'OEBPS/content.opf': opf2(spine: ['text/c1.xhtml']),
      'OEBPS/text/c1.xhtml': chapterXhtml('<img src="../images/foto.png"/>'),
      'OEBPS/images/foto.png': const [1, 2, 3, 4],
    };

    test('se resuelven contra el capítulo, no contra el OPF', () async {
      final source = await abrir(conImagen());
      addTearDown(source.dispose);

      expect(source.imageBytes(0, '../images/foto.png'), [1, 2, 3, 4]);
    });

    test('una imagen que no está devuelve null', () async {
      final source = await abrir(conImagen());
      addTearDown(source.dispose);

      expect(source.imageBytes(0, '../images/otra.png'), isNull);
    });

    test('las imágenes de fuera del EPUB no se van a buscar', () async {
      // Un `src` remoto en un libro local es o un error de empaquetado o un
      // rastreador. En ninguno de los dos casos se sale a la red.
      final source = await abrir(conImagen());
      addTearDown(source.dispose);

      expect(source.imageBytes(0, 'https://ejemplo.com/foto.png'), isNull);
      expect(source.imageBytes(0, 'data:image/png;base64,AAAA'), isNull);
    });
  });

  test('después de cerrar, se puede volver a abrir', () async {
    final file = File('${temp.path}${Platform.pathSeparator}libro.epub');
    await file.writeAsBytes(zipOf(sampleEpub2()));

    final source = EpubBookSource(file);
    await source.open();
    await source.dispose();
    await source.open();
    addTearDown(source.dispose);

    expect(source.chapters.length, 2);
  });
}
