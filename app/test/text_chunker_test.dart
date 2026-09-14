import 'package:flutter_test/flutter_test.dart';
import 'package:lector/formats/text_chunker.dart';

String libroLargo({int parrafos = 200}) => List.generate(
  parrafos,
  (i) => 'Párrafo $i. ${'palabra ' * 25}',
).join('\n\n');

void main() {
  group('casos límite', () {
    test('un texto vacío da un único fragmento vacío', () {
      final chunks = TextChunker.split('');
      expect(chunks, hasLength(1));
      expect(chunks.single.length, 0);
    });

    test('un texto corto cabe en un solo fragmento', () {
      final chunks = TextChunker.split('Dos líneas.\n\nY ya está.');
      expect(chunks, hasLength(1));
      expect(chunks.single.start, 0);
    });
  });

  group('integridad del troceado', () {
    final texto = libroLargo();
    final chunks = TextChunker.split(texto, targetChars: 2000);

    test('se generan varios fragmentos', () {
      expect(chunks.length, greaterThan(3));
    });

    test('cubren el texto entero sin huecos ni solapes', () {
      expect(chunks.first.start, 0);
      for (var i = 1; i < chunks.length; i++) {
        expect(
          chunks[i].start,
          chunks[i - 1].end,
          reason: 'el fragmento $i debe empezar donde acabó el anterior',
        );
      }
      expect(chunks.last.end, texto.length);
    });

    test('los índices son correlativos', () {
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].index, i);
      }
    });

    test('ningún corte cae en mitad de un párrafo', () {
      for (var i = 1; i < chunks.length; i++) {
        final anterior = texto.codeUnitAt(chunks[i].start - 1);
        expect(
          anterior == 0x0A || anterior == 0x0D || anterior == 0x20,
          isTrue,
          reason: 'el fragmento $i empieza a mitad de frase',
        );
      }
    });

    test('no queda un último fragmento ridículamente pequeño', () {
      expect(
        chunks.last.length,
        greaterThan(2000 * 0.25),
        reason: 'el resto sobrante debe absorberse en el anterior',
      );
    });
  });

  test('funciona con finales de línea de Windows', () {
    final texto = List.generate(80, (i) => 'Párrafo $i. ${'x' * 60}')
        .join('\r\n\r\n');
    final chunks = TextChunker.split(texto, targetChars: 1000);

    expect(chunks.length, greaterThan(2));
    expect(chunks.last.end, texto.length);
    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].start, chunks[i - 1].end);
    }
  });

  test('un texto sin ningún salto de párrafo no se puede trocear', () {
    final texto = 'x' * 10000;
    final chunks = TextChunker.split(texto, targetChars: 1000);
    expect(chunks, hasLength(1), reason: 'no hay por dónde cortar sin romper');
    expect(chunks.single.end, texto.length);
  });

  group('localizar un desplazamiento', () {
    final texto = libroLargo();
    final chunks = TextChunker.split(texto, targetChars: 2000);

    test('el principio está en el primer fragmento', () {
      expect(TextChunker.chunkIndexAt(chunks, 0), 0);
    });

    test('cada fragmento se encuentra por su propio inicio', () {
      for (final chunk in chunks) {
        expect(TextChunker.chunkIndexAt(chunks, chunk.start), chunk.index);
      }
    });

    test('un desplazamiento más allá del final devuelve el último', () {
      expect(
        TextChunker.chunkIndexAt(chunks, texto.length + 5000),
        chunks.length - 1,
        reason: 'puede pasar si el fichero se editó por fuera',
      );
    });

    test('un desplazamiento negativo devuelve el primero', () {
      expect(TextChunker.chunkIndexAt(chunks, -10), 0);
    });
  });
}
