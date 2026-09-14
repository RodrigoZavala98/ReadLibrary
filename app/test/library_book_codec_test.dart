import 'package:flutter_test/flutter_test.dart';
import 'package:lector/data/library_book_codec.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/library_book.dart';

LibraryBook libro({
  int id = 1,
  BookFormat format = BookFormat.epub,
  BookLocator? locator,
  double progress = 0,
}) => LibraryBook(
  id: id,
  filePath: '/datos/libro.epub',
  format: format,
  title: 'Dune',
  addedAt: DateTime(2026, 3, 1, 12),
  author: 'Frank Herbert',
  locator: locator,
  progress: progress,
);

void main() {
  group('ida y vuelta', () {
    test('conserva todos los campos', () {
      final original = LibraryBook(
        id: 7,
        filePath: '/datos/dune.epub',
        format: BookFormat.epub,
        title: 'Dune',
        addedAt: DateTime(2026, 3, 1, 12),
        author: 'Frank Herbert',
        coverPath: '/datos/portadas/7.jpg',
        lastOpenedAt: DateTime(2026, 3, 14, 22, 30),
        locator: const CfiLocator('epubcfi(/6/14!/4/10/2/1:0)'),
        progress: 0.65,
        totalPages: 312,
        collection: 'Ciencia ficción',
      );

      final copia = LibraryBookCodec.decode(
        LibraryBookCodec.encode(original),
      )!;

      expect(copia.id, 7);
      expect(copia.filePath, original.filePath);
      expect(copia.format, BookFormat.epub);
      expect(copia.title, 'Dune');
      expect(copia.author, 'Frank Herbert');
      expect(copia.coverPath, original.coverPath);
      expect(copia.addedAt, original.addedAt);
      expect(copia.lastOpenedAt, original.lastOpenedAt);
      expect(copia.locator, original.locator);
      expect(copia.progress, 0.65);
      expect(copia.totalPages, 312);
      expect(copia.collection, 'Ciencia ficción');
    });

    test('un libro recién añadido, sin nada opcional, sobrevive', () {
      final copia = LibraryBookCodec.decode(
        LibraryBookCodec.encode(libro()),
      )!;
      expect(copia.locator, isNull);
      expect(copia.lastOpenedAt, isNull);
      expect(copia.progress, 0);
    });

    test('las fechas sobreviven al cambio de huso', () {
      final original = libro();
      final json = LibraryBookCodec.encode(original);
      expect(json['addedAt'], endsWith('Z'), reason: 'se guarda en UTC');
      expect(LibraryBookCodec.decode(json)!.addedAt, original.addedAt);
    });
  });

  group('entradas que hay que descartar enteras', () {
    test('lo que no es un mapa', () {
      expect(LibraryBookCodec.decode(null), isNull);
      expect(LibraryBookCodec.decode('texto'), isNull);
      expect(LibraryBookCodec.decode(42), isNull);
      expect(LibraryBookCodec.decode([]), isNull);
    });

    test('sin los campos imprescindibles', () {
      final base = LibraryBookCodec.encode(libro());
      for (final campo in ['id', 'filePath', 'format', 'title']) {
        final roto = {...base}..remove(campo);
        expect(
          LibraryBookCodec.decode(roto),
          isNull,
          reason: 'sin «$campo» el libro no se puede usar',
        );
      }
    });

    test('un formato que esta versión no conoce', () {
      final json = {...LibraryBookCodec.encode(libro()), 'format': 'djvu'};
      expect(
        LibraryBookCodec.decode(json),
        isNull,
        reason: 'el índice lo escribió una versión más nueva',
      );
    });
  });

  group('campos corruptos que NO deben tumbar el libro', () {
    test('una fecha ilegible no impide cargarlo', () {
      final json = {...LibraryBookCodec.encode(libro()), 'addedAt': 'ayer'};
      final copia = LibraryBookCodec.decode(json);
      expect(copia, isNotNull);
      // Se compara el instante, no el año: la época en UTC cae en 1969 para
      // cualquier huso al oeste de Greenwich, y este test correría en CI bajo
      // UTC y en local bajo otro huso.
      expect(copia!.addedAt.millisecondsSinceEpoch, 0);
    });

    test('un localizador de otro formato se descarta, el libro no', () {
      // Una posición de página guardada para un EPUB: sin sentido.
      final json = {
        ...LibraryBookCodec.encode(libro(format: BookFormat.epub)),
        'locator': 'page:42',
      };
      final copia = LibraryBookCodec.decode(json);
      expect(copia, isNotNull);
      expect(copia!.locator, isNull, reason: 'se empieza el libro de cero');
    });

    test('un localizador con basura tampoco molesta', () {
      final json = {...LibraryBookCodec.encode(libro()), 'locator': '###'};
      expect(LibraryBookCodec.decode(json)!.locator, isNull);
    });

    test('el progreso se recorta al rango válido', () {
      Object? conProgreso(Object? value) =>
          LibraryBookCodec.decode({
            ...LibraryBookCodec.encode(libro()),
            'progress': value,
          })!.progress;

      expect(conProgreso(1.5), 1.0);
      expect(conProgreso(-3), 0.0);
      expect(conProgreso('0.4'), closeTo(0.4, 0.0001));
      expect(conProgreso('no es un número'), 0.0);
      expect(conProgreso(null), 0.0);
    });

    test('un id escrito como texto se acepta', () {
      final json = {...LibraryBookCodec.encode(libro()), 'id': '12'};
      expect(LibraryBookCodec.decode(json)!.id, 12);
    });
  });
}
