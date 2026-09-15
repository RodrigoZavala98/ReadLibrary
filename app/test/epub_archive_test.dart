import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_source.dart';
import 'package:lector/formats/epub_archive.dart';

import 'epub_fixture.dart';

void main() {
  group('rutas', () {
    test('el href del índice se resuelve contra el propio índice', () {
      // El error clásico es resolverlo contra la carpeta del OPF: funciona de
      // casualidad en los EPUB que lo tienen todo junto.
      expect(resolveHref('text/nav.xhtml', 'cap1.xhtml'), 'text/cap1.xhtml');
    });

    test('los dos puntos suben de carpeta', () {
      expect(
        resolveHref('text/cap1.xhtml', '../images/foto.jpg'),
        'images/foto.jpg',
      );
    });

    test('la barra inicial significa la raíz del ZIP', () {
      expect(resolveHref('text/cap1.xhtml', '/OEBPS/x.jpg'), 'OEBPS/x.jpg');
    });

    test('el ancla no forma parte del fichero', () {
      expect(resolveHref('nav.xhtml', 'cap1.xhtml#seccion2'), 'cap1.xhtml');
    });

    test('los nombres escapados como URL se deshacen', () {
      // Sin esto, un capítulo llamado «El día 1.xhtml» no se encuentra nunca.
      expect(
        resolveHref('nav.xhtml', 'El%20d%C3%ADa%201.xhtml'),
        'El día 1.xhtml',
      );
    });
  });

  group('apertura', () {
    test('un EPUB sano encuentra su OPF', () {
      final epub = EpubArchive.open(zipOf(sampleEpub2()));
      expect(epub.opfPath, 'OEBPS/content.opf');
      expect(epub.opfDir, 'OEBPS/');
    });

    test('un OPF en la raíz deja la carpeta vacía', () {
      final epub = EpubArchive.open(zipOf(sampleEpub2(prefix: '')));
      expect(epub.opfDir, '');
    });

    test('lo que no es un ZIP se rechaza explicando por qué', () {
      final basura = Uint8List.fromList(utf8.encode('esto no es un EPUB'));
      expect(
        () => EpubArchive.open(basura),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'mensaje',
            contains('no es un EPUB'),
          ),
        ),
      );
    });

    test('un ZIP sin container.xml se rechaza', () {
      expect(
        () => EpubArchive.open(zipOf({'OEBPS/c1.xhtml': '<p>hola</p>'})),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'mensaje',
            contains('container.xml'),
          ),
        ),
      );
    });

    test('un container.xml sin rootfile se rechaza', () {
      expect(
        () => EpubArchive.open(
          zipOf({
            'META-INF/container.xml':
                '<?xml version="1.0"?><container><rootfiles/></container>',
          }),
        ),
        throwsA(isA<BookOpenException>()),
      );
    });

    test('un container.xml mal formado se rechaza', () {
      expect(
        () => EpubArchive.open(
          zipOf({'META-INF/container.xml': '<container><rootfiles>'}),
        ),
        throwsA(isA<BookOpenException>()),
      );
    });

    test('un OPF prometido que no está se rechaza diciendo dónde faltaba', () {
      expect(
        () => EpubArchive.open(
          zipOf({
            'META-INF/container.xml': containerFor('OEBPS/no_existe.opf'),
          }),
        ),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'mensaje',
            contains('no_existe.opf'),
          ),
        ),
      );
    });
  });

  group('lectura de entradas', () {
    test('lee relativo a la carpeta del OPF', () {
      final epub = EpubArchive.open(zipOf(sampleEpub2()));
      expect(epub.readString('c1.xhtml'), contains('Primera página'));
      expect(epub.contains('c2.xhtml'), isTrue);
    });

    test('una entrada que no está devuelve null en lugar de fallar', () {
      final epub = EpubArchive.open(zipOf(sampleEpub2()));
      expect(epub.read('fantasma.xhtml'), isNull);
      expect(epub.readString('fantasma.xhtml'), isNull);
      expect(epub.sizeOf('fantasma.xhtml'), 0);
    });

    test('el tamaño es el del fichero sin comprimir', () {
      final contenido = chapterXhtml('<p>${'x' * 5000}</p>');
      final epub = EpubArchive.open(
        zipOf({...sampleEpub2(), 'OEBPS/c1.xhtml': contenido}),
      );
      // En bytes, no en caracteres: el ZIP no sabe de UTF-16.
      expect(epub.sizeOf('c1.xhtml'), utf8.encode(contenido).length);
    });
  });

  group('cifrado', () {
    String encryption(String uri) =>
        '<?xml version="1.0"?>'
        '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">'
        '<CipherData><CipherReference URI="$uri"/></CipherData>'
        '</EncryptedData></encryption>';

    test('un EPUB con DRM se rechaza con una explicación honesta', () {
      expect(
        () => EpubArchive.open(
          zipOf({
            ...sampleEpub2(),
            'META-INF/encryption.xml': encryption('OEBPS/c1.xhtml'),
          }),
        ),
        throwsA(
          isA<BookOpenException>().having(
            (e) => e.message,
            'mensaje',
            contains('DRM'),
          ),
        ),
      );
    });

    test('una tipografía ofuscada no impide abrir el libro', () {
      // La ofuscación de fuentes usa el mismo fichero que el DRM y es legítima.
      // Confundirlas dejaría sin abrir un montón de libros perfectamente
      // legibles, porque las fuentes embebidas ni siquiera se usan.
      final epub = EpubArchive.open(
        zipOf({
          ...sampleEpub2(),
          'META-INF/encryption.xml': encryption('OEBPS/fonts/x.otf'),
        }),
      );
      expect(epub.readString('c1.xhtml'), contains('Primera página'));
    });

    test('un encryption.xml ilegible no bloquea la lectura', () {
      final epub = EpubArchive.open(
        zipOf({...sampleEpub2(), 'META-INF/encryption.xml': 'no es xml <<<'}),
      );
      expect(epub.opfPath, 'OEBPS/content.opf');
    });
  });
}
