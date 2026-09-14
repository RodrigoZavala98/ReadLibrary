import 'package:flutter_test/flutter_test.dart';
import 'package:lector/ui/simple_html.dart';

void main() {
  test('separa los párrafos', () {
    expect(
      SimpleHtml.toParagraphs('<p>Uno.</p><p>Dos.</p>'),
      ['Uno.', 'Dos.'],
    );
  });

  test('deshace el escapado', () {
    expect(
      SimpleHtml.toParagraphs('<p>Si a &lt; b &amp; b &gt; c</p>'),
      ['Si a < b & b > c'],
    );
  });

  test('un ampersand escapado dos veces no se convierte en etiqueta', () {
    // «&amp;lt;» representa el texto literal «&lt;». Si se sustituyera «&amp;»
    // antes que «&lt;», el resultado sería «<», que es justo lo que el doble
    // escapado pretendía evitar.
    expect(SimpleHtml.unescape('&amp;lt;'), '&lt;');
  });

  test('los párrafos vacíos se descartan', () {
    expect(SimpleHtml.toParagraphs('<p>Uno.</p><p>  </p><p>Dos.</p>'),
        ['Uno.', 'Dos.']);
  });

  test('un párrafo con saltos de línea internos se conserva entero', () {
    expect(
      SimpleHtml.toParagraphs('<p>Primera línea\nsegunda línea</p>'),
      ['Primera línea\nsegunda línea'],
    );
  });

  test('texto sin etiquetas no deja la pantalla en blanco', () {
    expect(SimpleHtml.toParagraphs('Suelto y sin marcar'),
        ['Suelto y sin marcar']);
  });

  test('una entrada vacía no produce párrafos', () {
    expect(SimpleHtml.toParagraphs(''), isEmpty);
    expect(SimpleHtml.toParagraphs('   '), isEmpty);
  });
}
