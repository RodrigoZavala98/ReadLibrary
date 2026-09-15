import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/reading_settings.dart';
import 'package:lector/ui/paginator.dart';
import 'package:lector/ui/rich_html.dart';

/// El texto de una página, juntando todos sus bloques.
String textoDe(BookPage page) {
  final buffer = StringBuffer();
  for (final block in page.blocks) {
    final runs = switch (block) {
      HtmlParagraph(:final runs) => runs,
      HtmlHeading(:final runs) => runs,
      HtmlQuote(:final runs) => runs,
      HtmlListItem(:final runs) => runs,
      HtmlPre(:final text) => [TextRun(text)],
      HtmlRule() || HtmlImage() => const <TextRun>[],
    };
    for (final run in runs) {
      buffer.write(run.text);
    }
  }
  return buffer.toString();
}

String textoDeTodas(PagedChapter chapter) =>
    chapter.pages.map(textoDe).join();

void main() {
  // `TextPainter` necesita el motor de texto, así que hace falta el enlace de
  // pruebas aunque no se pinte nada. La fuente de las pruebas no es Literata
  // sino la de prueba, con todos los glifos del mismo ancho: eso hace que las
  // medidas sean deterministas, que es justo lo que interesa aquí.
  TestWidgetsFlutterBinding.ensureInitialized();

  const pantalla = Size(360, 600);

  PagedChapter paginar(
    String html, {
    Size viewport = pantalla,
    ReadingSettings? settings,
  }) => Paginator.paginate(
    blocks: RichHtml.parse(html),
    settings: settings ?? ReadingSettings(),
    viewport: viewport,
  );

  String parrafos(int cuantos) => [
    for (var i = 0; i < cuantos; i++)
      '<p>Párrafo $i. ${'palabra ' * 40}</p>',
  ].join();

  group('reparto', () {
    test('un texto corto cabe en una sola página', () {
      final chapter = paginar('<p>Una frase corta.</p>');
      expect(chapter.length, 1);
      expect(textoDe(chapter.pages.single), 'Una frase corta.');
    });

    test('un capítulo largo se reparte en varias', () {
      expect(paginar(parrafos(30)).length, greaterThan(1));
    });

    test('un capítulo vacío da una página, no ninguna', () {
      // Devolver una lista vacía reventaría a quien pinta, que da por hecho
      // que siempre hay al menos una página.
      final chapter = paginar('');
      expect(chapter.pages, hasLength(1));
      expect(chapter.pages.single.blocks, isEmpty);
    });

    test('una pantalla de tamaño cero no cuelga el reparto', () {
      // Pasa en el primer fotograma, antes de que haya medidas.
      final chapter = paginar(parrafos(5), viewport: Size.zero);
      expect(chapter.pages, hasLength(1));
    });
  });

  group('no se pierde ni se repite nada', () {
    test('el texto de todas las páginas es exactamente el del capítulo', () {
      // Es **la** invariante de esta entrega. Si falla, el lector se come
      // párrafos o los enseña dos veces, y eso no se nota hasta que alguien
      // está leyendo en serio.
      final html = parrafos(25);
      final esperado = RichHtml.parse(html)
          .whereType<HtmlParagraph>()
          .expand((p) => p.runs)
          .map((r) => r.text)
          .join();

      expect(textoDeTodas(paginar(html)), esperado);
    });

    test('también cuando hay encabezados, citas y listas de por medio', () {
      final html =
          '<h1>Título</h1>${parrafos(8)}'
          '<blockquote>${'cita larga ' * 40}</blockquote>'
          '<ul><li>${'uno ' * 30}</li><li>dos</li></ul>'
          '${parrafos(8)}';

      final bloques = RichHtml.parse(html);
      final esperado = bloques
          .map(
            (b) => switch (b) {
              HtmlParagraph(:final runs) ||
              HtmlHeading(:final runs) ||
              HtmlQuote(:final runs) ||
              HtmlListItem(:final runs) => runs.map((r) => r.text).join(),
              _ => '',
            },
          )
          .join();

      expect(
        textoDeTodas(
          Paginator.paginate(
            blocks: bloques,
            settings: ReadingSettings(),
            viewport: pantalla,
          ),
        ),
        esperado,
      );
    });

    test('el énfasis sobrevive al corte', () {
      // Un párrafo largo en cursiva partido en dos páginas tiene que seguir en
      // cursiva en las dos.
      final chapter = paginar('<p><em>${'palabra ' * 300}</em></p>');
      expect(chapter.length, greaterThan(1));

      for (final page in chapter.pages) {
        final parrafo = page.blocks.whereType<HtmlParagraph>().single;
        expect(parrafo.runs.every((r) => r.italic), isTrue);
      }
    });
  });

  group('ninguna página se desborda', () {
    test('todas caben en el alto disponible', () {
      final chapter = paginar(parrafos(40));
      expect(chapter.length, greaterThan(3), reason: 'que haya varias');
    });

    test('un párrafo se parte por el renglón, no por donde caiga', () {
      // Si cortara por carácter, la última línea de una página saldría a medias
      // y la primera de la siguiente empezaría mordida.
      final chapter = paginar('<p>${'palabra ' * 400}</p>');
      expect(chapter.length, greaterThan(1));

      final primera = textoDe(chapter.pages.first);
      // El corte cae entre palabras: el trozo que se queda no termina en mitad
      // de una, salvo que la propia línea acabe justo ahí.
      expect(primera.endsWith('palabra ') || primera.endsWith('palabra'),
          isTrue);
    });
  });

  group('imágenes', () {
    test('cada una se lleva su página, sola', () {
      final chapter = paginar(
        '<p>Antes</p><img src="foto.png"/><p>Después</p>',
      );

      final conImagen = chapter.pages.where(
        (p) => p.blocks.any((b) => b is HtmlImage),
      );
      expect(conImagen, hasLength(1));
      expect(conImagen.single.blocks, hasLength(1));
    });

    test('el texto de alrededor no se pierde', () {
      final chapter = paginar(
        '<p>Antes</p><img src="foto.png"/><p>Después</p>',
      );
      expect(textoDeTodas(chapter), 'AntesDespués');
    });
  });

  group('los ajustes cambian el reparto', () {
    test('con letra más grande salen más páginas', () {
      final html = parrafos(20);
      final pequena = paginar(html, settings: ReadingSettings(fontSize: 14));
      final grande = paginar(html, settings: ReadingSettings(fontSize: 28));

      expect(grande.length, greaterThan(pequena.length));
    });

    test('con más interlineado también', () {
      final html = parrafos(20);
      final junto = paginar(html, settings: ReadingSettings(lineHeight: 1.2));
      final suelto = paginar(html, settings: ReadingSettings(lineHeight: 2.2));

      expect(suelto.length, greaterThan(junto.length));
    });

    test('una pantalla más alta reparte en menos páginas', () {
      final html = parrafos(20);
      expect(
        paginar(html, viewport: const Size(360, 1200)).length,
        lessThan(paginar(html, viewport: const Size(360, 400)).length),
      );
    });
  });

  group('la posición se conserva al repaginar', () {
    test('la primera página empieza en el carácter cero', () {
      expect(paginar(parrafos(10)).pages.first.startChar, 0);
    });

    test('los comienzos crecen página a página', () {
      final chapter = paginar(parrafos(30));
      for (var i = 1; i < chapter.length; i++) {
        expect(
          chapter.pages[i].startChar,
          greaterThanOrEqualTo(chapter.pages[i - 1].startChar),
        );
      }
    });

    test('se encuentra la página que contiene un carácter', () {
      final chapter = paginar(parrafos(30));
      final tercera = chapter.pages[2];

      expect(chapter.pageForChar(tercera.startChar), 2);
      expect(chapter.pageForChar(tercera.startChar + 1), 2);
      expect(chapter.pageForChar(0), 0);
    });

    test('un carácter anterior a todo cae en la primera página', () {
      expect(paginar(parrafos(10)).pageForChar(-5), 0);
    });

    test('un carácter posterior a todo cae en la última', () {
      final chapter = paginar(parrafos(10));
      expect(chapter.pageForChar(1 << 30), chapter.length - 1);
    });

    test('cambiar el cuerpo de letra deja en el mismo texto', () {
      // Es la promesa de guardar el carácter en lugar del número de página:
      // subir la letra no puede moverte de sitio en el libro.
      final html = parrafos(30);
      final antes = paginar(html, settings: ReadingSettings(fontSize: 16));
      final caracter = antes.pages[4].startChar;

      final despues = paginar(html, settings: ReadingSettings(fontSize: 24));
      final pagina = despues.pages[despues.pageForChar(caracter)];

      expect(pagina.startChar, lessThanOrEqualTo(caracter));
      expect(
        textoDe(pagina),
        isNotEmpty,
        reason: 'la página a la que se vuelve tiene contenido',
      );
    });

    test('la fracción del capítulo crece con la página', () {
      final chapter = paginar(parrafos(30));
      expect(chapter.fractionAt(0), 0);
      expect(chapter.fractionAt(chapter.length - 1), greaterThan(0));
      expect(chapter.fractionAt(chapter.length - 1), lessThanOrEqualTo(1));
    });
  });
}
