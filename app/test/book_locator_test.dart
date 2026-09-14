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

    test('un CFI de EPUB sobrevive intacto, con sus dos puntos incluidos', () {
      // Un CFI real lleva ':' dentro, que es justo el carácter que usamos como
      // separador. Si decode partiera por el último ':' en vez de por el
      // primero, esto se rompería.
      const original = CfiLocator('epubcfi(/6/14[chap05]!/4/10/2/1:0)');
      final restored = BookLocator.decode(original.encode(), BookFormat.epub);
      expect(restored, original);
    });
  });

  group('se rechaza lo que no encaja', () {
    test('una página no vale para un EPUB', () {
      expect(BookLocator.decode('page:12', BookFormat.epub), isNull);
    });

    test('un CFI no vale para un PDF', () {
      expect(BookLocator.decode('cfi:epubcfi(/6/4)', BookFormat.pdf), isNull);
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
