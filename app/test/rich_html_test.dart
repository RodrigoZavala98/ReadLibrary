import 'package:flutter_test/flutter_test.dart';
import 'package:lector/ui/rich_html.dart';

List<HtmlBlock> bloques(String html) => RichHtml.parse(html);

/// El texto de un bloque, juntando sus trozos.
String textoDe(HtmlBlock block) => switch (block) {
  HtmlParagraph(:final runs) => runs.map((r) => r.text).join(),
  HtmlHeading(:final runs) => runs.map((r) => r.text).join(),
  HtmlQuote(:final runs) => runs.map((r) => r.text).join(),
  HtmlListItem(:final runs) => runs.map((r) => r.text).join(),
  HtmlPre(:final text) => text,
  HtmlRule() => '',
  HtmlImage(:final src) => src,
};

void main() {
  group('párrafos', () {
    test('cada párrafo es un bloque', () {
      final r = bloques('<p>Uno.</p><p>Dos.</p>');
      expect(r.length, 2);
      expect(textoDe(r[0]), 'Uno.');
      expect(textoDe(r[1]), 'Dos.');
    });

    test('los espacios se colapsan, como manda HTML', () {
      // Es la razón de tirar el renderizador anterior: un capítulo de EPUB
      // viene maquetado con saltos de línea cada ochenta columnas, y sin
      // colapsar se leería como una escalera.
      final r = bloques('<p>Una  frase\n   partida\n\ten el fichero.</p>');
      expect(textoDe(r.single), 'Una frase partida en el fichero.');
    });

    test('el `br` sí separa de verdad', () {
      // Es lo que mantiene los versos en su sitio.
      final r = bloques('<p>Verso uno<br/>Verso dos</p>');
      expect(textoDe(r.single), 'Verso uno\nVerso dos');
    });

    test('el texto suelto, sin etiquetas, no se pierde', () {
      expect(textoDe(bloques('Sin marcar').single), 'Sin marcar');
    });

    test('un documento vacío no da bloques', () {
      expect(bloques(''), isEmpty);
      expect(bloques('<p>   </p>'), isEmpty);
      expect(bloques('<html><body></body></html>'), isEmpty);
    });

    test('los espacios del borde del párrafo se recortan', () {
      expect(textoDe(bloques('<p>\n  Con sangría\n</p>').single),
          'Con sangría');
    });
  });

  group('énfasis', () {
    test('cursiva, negrita y código se marcan', () {
      final r = bloques(
        '<p>Un <em>eco</em>, un <strong>golpe</strong> y un '
        '<code>valor</code>.</p>',
      );
      final runs = (r.single as HtmlParagraph).runs;

      expect(runs.firstWhere((x) => x.text == 'eco').italic, isTrue);
      expect(runs.firstWhere((x) => x.text == 'golpe').bold, isTrue);
      expect(runs.firstWhere((x) => x.text == 'valor').code, isTrue);
    });

    test('los énfasis anidados se acumulan', () {
      final runs =
          (bloques('<p><em>muy <strong>fuerte</strong></em></p>').single
                  as HtmlParagraph)
              .runs;
      final fuerte = runs.firstWhere((r) => r.text == 'fuerte');
      expect(fuerte.italic, isTrue);
      expect(fuerte.bold, isTrue);
    });

    test('los sinónimos de cursiva y negrita valen igual', () {
      final runs =
          (bloques('<p><i>a</i><b>b</b></p>').single as HtmlParagraph).runs;
      expect(runs.firstWhere((r) => r.text == 'a').italic, isTrue);
      expect(runs.firstWhere((r) => r.text == 'b').bold, isTrue);
    });

    test('un enlace se marca aunque todavía no navegue', () {
      final runs =
          (bloques('<p>Ver <a href="x.xhtml">la nota</a>.</p>').single
                  as HtmlParagraph)
              .runs;
      expect(runs.firstWhere((r) => r.text == 'la nota').link, isTrue);
    });

    test('las entidades se deshacen', () {
      expect(
        textoDe(bloques('<p>Si a &lt; b &amp; b &gt; c</p>').single),
        'Si a < b & b > c',
      );
    });
  });

  group('bloques que no son párrafos', () {
    test('los encabezados llevan su nivel', () {
      final r = bloques('<h1>Parte</h1><h3>Capítulo</h3>');
      expect((r[0] as HtmlHeading).level, 1);
      expect((r[1] as HtmlHeading).level, 3);
      expect(textoDe(r[1]), 'Capítulo');
    });

    test('las citas se distinguen de los párrafos', () {
      final r = bloques('<blockquote>Dijo algo.</blockquote>');
      expect(r.single, isA<HtmlQuote>());
    });

    test('las listas sin numerar llevan viñeta', () {
      final r = bloques('<ul><li>Uno</li><li>Dos</li></ul>');
      expect(r.length, 2);
      expect((r[0] as HtmlListItem).marker, '•');
      expect(textoDe(r[1]), 'Dos');
    });

    test('las listas numeradas se numeran al analizar, no al pintar', () {
      final r = bloques('<ol><li>Uno</li><li>Dos</li><li>Tres</li></ol>');
      expect(r.map((b) => (b as HtmlListItem).marker), ['1.', '2.', '3.']);
    });

    test('las listas anidadas cuentan su profundidad', () {
      final r = bloques('<ul><li>Fuera<ul><li>Dentro</li></ul></li></ul>');
      final dentro = r.firstWhere((b) => textoDe(b) == 'Dentro');
      expect((dentro as HtmlListItem).depth, 2);
    });

    test('la línea separadora es un bloque propio', () {
      expect(bloques('<p>a</p><hr/><p>b</p>')[1], isA<HtmlRule>());
    });

    test('el preformateado conserva sus espacios', () {
      final r = bloques('<pre>  uno\n    dos</pre>');
      expect((r.single as HtmlPre).text, '  uno\n    dos');
    });
  });

  group('imágenes', () {
    test('salen como bloque con su ruta y su texto alternativo', () {
      final r = bloques('<p><img src="foto.png" alt="Un perro"/></p>');
      final imagen = r.single as HtmlImage;
      expect(imagen.src, 'foto.png');
      expect(imagen.alt, 'Un perro');
    });

    test('una imagen parte el párrafo en lugar de descolocarse', () {
      final r = bloques('<p>Antes<img src="x.png"/>Después</p>');
      expect(r.map(textoDe), ['Antes', 'x.png', 'Después']);
    });

    test('un img sin src se ignora', () {
      expect(bloques('<p><img alt="nada"/></p>'), isEmpty);
    });
  });

  group('lo que un EPUB de verdad trae', () {
    test('el script no se ejecuta ni se lee: ni siquiera entra', () {
      // Sin WebView no hay nada que pueda ejecutarlo, pero su texto tampoco
      // debe aparecer en mitad del capítulo.
      final r = bloques('<p>Texto</p><script>alert("hola")</script>');
      expect(r.length, 1);
      expect(textoDe(r.single), 'Texto');
    });

    test('el CSS embebido tampoco se cuela como texto', () {
      final r = bloques('<style>p { color: red }</style><p>Texto</p>');
      expect(r.length, 1);
    });

    test('el HTML mal cerrado se lee igual', () {
      // Es lo normal en un EPUB convertido desde Word.
      final r = bloques('<p>Uno<p>Dos');
      expect(r.map(textoDe), ['Uno', 'Dos']);
    });

    test('los envoltorios sin significado se atraviesan', () {
      final r = bloques('<div><section><p>Dentro</p></section></div>');
      expect(textoDe(r.single), 'Dentro');
    });

    test('una etiqueta desconocida no se lleva por delante su texto', () {
      final r = bloques('<p>Antes <trampa>dentro</trampa> después</p>');
      expect(textoDe(r.single), contains('dentro'));
    });

    test('una tabla se aplana a una línea por fila', () {
      final r = bloques(
        '<table><tr><td>Año</td><td>Obra</td></tr>'
        '<tr><td>1967</td><td>Cien años</td></tr></table>',
      );
      expect(r.map(textoDe), ['Año · Obra', '1967 · Cien años']);
    });

    test('el capítulo entero se puede leer como texto pelado', () {
      final texto = RichHtml.plainText(bloques('<h1>Título</h1><p>Cuerpo</p>'));
      expect(texto, 'Título\nCuerpo\n');
    });
  });
}
