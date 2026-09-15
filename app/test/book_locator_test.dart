import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';

void main() {
  group('ida y vuelta por la base de datos', () {
    test('una página de PDF sobrevive al guardado', () {
      const original = PageLocator(23);
      final restored = BookLocator.decode(original.encode(), BookFormat.pdf);
      expect(restored, original);
    });

    test('un desplazamiento de TXT sobrevive al guardado', () {
      const original = CharLocator(148302);
      final restored = BookLocator.decode(original.encode(), BookFormat.txt);
      expect(restored, original);
    });

    test('una posición de EPUB sobrevive al guardado', () {
      const original = EpubLocator(14, 432);
      final restored = BookLocator.decode(original.encode(), BookFormat.epub);
      expect(restored, original);
    });

    test('la fracción se guarda en milésimas y vuelve idéntica', () {
      // Milésimas y no un double: un entero va y vuelve exacto por JSON, y
      // comparar 0,432 reconstruido con 0,432 escrito no es de fiar.
      final original = EpubLocator.atFraction(3, 0.4325);
      expect(original.permille, 433);
      expect(BookLocator.decode(original.encode(), BookFormat.epub), original);
    });
  });

  group('se rechaza lo que no encaja', () {
    test('una página no vale para un EPUB', () {
      expect(BookLocator.decode('page:12', BookFormat.epub), isNull);
    });

    test('una posición de EPUB no vale para un PDF', () {
      expect(BookLocator.decode('epub:2/500', BookFormat.pdf), isNull);
    });

    test('un CFI guardado por una versión anterior se descarta', () {
      // El EPUB se leía con CFI cuando el motor iba a ser Epub.js. Se cambió de
      // motor, y un CFI ya no lo sabe interpretar nadie: el libro se abre por
      // el principio en lugar de en un sitio inventado.
      expect(
        BookLocator.decode('cfi:epubcfi(/6/14!/4/10/2/1:0)', BookFormat.epub),
        isNull,
      );
    });

    test('una posición de EPUB imposible se descarta', () {
      expect(BookLocator.decode('epub:2/1001', BookFormat.epub), isNull);
      expect(BookLocator.decode('epub:2', BookFormat.epub), isNull);
      expect(BookLocator.decode('epub:x/5', BookFormat.epub), isNull);
      expect(BookLocator.decode('epub:-1/5', BookFormat.epub), isNull);
    });

    test('un desplazamiento de caracteres no vale para un cómic', () {
      expect(BookLocator.decode('char:500', BookFormat.cbz), isNull);
    });

    test('una página sí vale tanto para PDF como para CBZ', () {
      expect(BookLocator.decode('page:3', BookFormat.pdf), isNotNull);
      expect(BookLocator.decode('page:3', BookFormat.cbz), isNotNull);
    });
  });

  group('entradas corruptas no revientan, devuelven null', () {
    for (final corrupt in ['', 'page', 'page:', 'page:-1', 'page:abc', 'cfi:',
      'basura', ':::', 'unknown:5']) {
      test('«$corrupt»', () {
        expect(BookLocator.decode(corrupt, BookFormat.pdf), isNull);
        expect(BookLocator.decode(corrupt, BookFormat.epub), isNull);
      });
    }
  });

  group('detección de formato por nombre de fichero', () {
    test('reconoce las extensiones habituales', () {
      expect(BookFormat.fromFileName('Dune.epub'), BookFormat.epub);
      expect(BookFormat.fromFileName('manual.PDF'), BookFormat.pdf);
      expect(BookFormat.fromFileName('tomo 3.cbz'), BookFormat.cbz);
      expect(BookFormat.fromFileName('notas.txt'), BookFormat.txt);
    });

    test('reconoce los formatos aún no soportados, para poder explicarlos', () {
      expect(BookFormat.fromFileName('comic.cbr')?.isSupported, isFalse);
      expect(BookFormat.fromFileName('libro.fb2')?.isSupported, isFalse);
    });

    test('devuelve null sin extensión o con una desconocida', () {
      expect(BookFormat.fromFileName('LEEME'), isNull);
      expect(BookFormat.fromFileName('foto.jpg'), isNull);
      expect(BookFormat.fromFileName('raro.'), isNull);
    });

    test('un nombre con puntos usa la última extensión', () {
      expect(BookFormat.fromFileName('El.Señor.de.los.Anillos.epub'),
          BookFormat.epub);
    });
  });

  test('la maqueta de cada formato es la correcta', () {
    expect(BookFormat.epub.layout, LayoutKind.reflowable);
    expect(BookFormat.txt.layout, LayoutKind.reflowable);
    expect(BookFormat.pdf.layout, LayoutKind.fixed);
    expect(BookFormat.cbz.layout, LayoutKind.fixed);
  });
}
