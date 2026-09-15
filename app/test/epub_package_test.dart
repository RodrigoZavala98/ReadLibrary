import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_source.dart';
import 'package:lector/formats/epub_archive.dart';
import 'package:lector/formats/epub_package.dart';

import 'epub_fixture.dart';

EpubPackage leer(Map<String, Object> entries) =>
    EpubPackage.parse(EpubArchive.open(zipOf(entries)));

void main() {
  group('metadatos', () {
    test('saca título y autor', () {
      final package = leer(sampleEpub2());
      expect(package.title, 'El libro');
      expect(package.author, 'Quien sea');
    });

    test('sin título declarado devuelve null y no inventa nada', () {
      // Lo resuelve quien llama, con el nombre del fichero: el paquete no sabe
      // de dónde salió el EPUB.
      final package = leer({
        ...sampleEpub2(),
        'OEBPS/content.opf': opf2(title: null, author: null),
      });
      expect(package.title, isNull);
      expect(package.author, isNull);
    });

    test('los espacios y saltos de línea del título se colapsan', () {
      final package = leer({
        ...sampleEpub2(),
        'OEBPS/content.opf': opf2(title: '  El\n  libro  '),
      });
      expect(package.title, 'El libro');
    });
  });

  group('lomo', () {
    test('los documentos salen en el orden del lomo, no del manifiesto', () {
      // El manifiesto es un inventario; el lomo es la secuencia de lectura. Un
      // EPUB que los declare al revés se lee en el orden del lomo.
      final opf =
          '<?xml version="1.0"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
          '<metadata/>'
          '<manifest>'
          '<item id="b" href="segundo.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '<item id="a" href="primero.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '</manifest>'
          '<spine><itemref idref="a"/><itemref idref="b"/></spine>'
          '</package>';

      final package = leer({
        'META-INF/container.xml': containerFor('OEBPS/content.opf'),
        'OEBPS/content.opf': opf,
        'OEBPS/primero.xhtml': chapterXhtml('<p>1</p>'),
        'OEBPS/segundo.xhtml': chapterXhtml('<p>2</p>'),
      });

      expect(package.spine.map((d) => d.href), ['primero.xhtml',
        'segundo.xhtml']);
    });

    test('un itemref que no existe en el manifiesto se ignora', () {
      final opf =
          '<?xml version="1.0"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
          '<metadata/>'
          '<manifest><item id="a" href="c1.xhtml" '
          'media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="a"/><itemref idref="fantasma"/></spine>'
          '</package>';

      final package = leer({
        'META-INF/container.xml': containerFor('OEBPS/content.opf'),
        'OEBPS/content.opf': opf,
        'OEBPS/c1.xhtml': chapterXhtml('<p>1</p>'),
      });

      expect(package.spine.length, 1);
    });

    test('un EPUB sin un solo capítulo se rechaza', () {
      // Es lo único que no se puede perdonar: sin documentos no hay libro.
      expect(
        () => leer({
          'META-INF/container.xml': containerFor('OEBPS/content.opf'),
          'OEBPS/content.opf': opf2(spine: []),
        }),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'mensaje',
            contains('ni un solo capítulo'),
          ),
        ),
      );
    });

    test('un OPF mal formado se rechaza', () {
      expect(
        () => leer({
          'META-INF/container.xml': containerFor('OEBPS/content.opf'),
          'OEBPS/content.opf': '<package><manifest>',
        }),
        throwsA(isA<BookOpenException>()),
      );
    });
  });

  group('índice', () {
    test('el NCX de EPUB 2 pone los títulos', () {
      final package = leer(sampleEpub2());
      expect(package.spine.map((d) => d.title), ['El principio', 'El final']);
    });

    test('el nav de EPUB 3 pone los títulos', () {
      final package = leer({
        'META-INF/container.xml': containerFor('OEBPS/content.opf'),
        'OEBPS/content.opf': opf3(),
        'OEBPS/nav.xhtml': navXhtml({
          'c1.xhtml': 'Uno',
          'c2.xhtml': 'Dos',
        }),
        'OEBPS/c1.xhtml': chapterXhtml('<p>1</p>'),
        'OEBPS/c2.xhtml': chapterXhtml('<p>2</p>'),
      });
      expect(package.spine.map((d) => d.title), ['Uno', 'Dos']);
    });

    test('un índice con anclas casa igualmente con su documento', () {
      // Los índices apuntan a `cap1.xhtml#seccion`, y el lomo sólo conoce
      // `cap1.xhtml`: sin quitar el ancla, ningún capítulo tendría título.
      final package = leer({
        ...sampleEpub2(),
        'OEBPS/toc.ncx': ncx({
          'c1.xhtml#inicio': 'Con ancla',
          'c2.xhtml#fin': 'También',
        }),
      });
      expect(package.spine.map((d) => d.title), ['Con ancla', 'También']);
    });

    test('un índice en otra carpeta resuelve sus rutas contra sí mismo', () {
      final package = leer({
        'META-INF/container.xml': containerFor('OEBPS/content.opf'),
        'OEBPS/content.opf': opf2(
          spine: ['text/c1.xhtml', 'text/c2.xhtml'],
          ncxHref: 'nav/toc.ncx',
        ),
        'OEBPS/nav/toc.ncx': ncx({
          '../text/c1.xhtml': 'Primero',
          '../text/c2.xhtml': 'Segundo',
        }),
        'OEBPS/text/c1.xhtml': chapterXhtml('<p>1</p>'),
        'OEBPS/text/c2.xhtml': chapterXhtml('<p>2</p>'),
      });
      expect(package.spine.map((d) => d.title), ['Primero', 'Segundo']);
    });

    test('sin índice, los capítulos se numeran', () {
      final package = leer({
        'META-INF/container.xml': containerFor('OEBPS/content.opf'),
        'OEBPS/content.opf': opf2(),
        'OEBPS/c1.xhtml': chapterXhtml('<p>1</p>'),
        'OEBPS/c2.xhtml': chapterXhtml('<p>2</p>'),
      });
      expect(package.spine.map((d) => d.title), ['Capítulo 1', 'Capítulo 2']);
    });

    test('un índice mal formado no impide leer el libro', () {
      final package = leer({...sampleEpub2(), 'OEBPS/toc.ncx': '<ncx><navMap>'});
      expect(package.spine.length, 2);
      expect(package.spine.first.title, 'Capítulo 1');
    });

    test('un documento que el índice no menciona se numera por su sitio', () {
      final package = leer({
        ...sampleEpub2(),
        'OEBPS/toc.ncx': ncx({'c2.xhtml': 'El final'}),
      });
      expect(package.spine.map((d) => d.title), ['Capítulo 1', 'El final']);
    });
  });
}
