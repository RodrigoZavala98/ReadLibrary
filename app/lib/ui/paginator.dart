import 'package:flutter/material.dart';

import '../domain/reading_settings.dart';
import 'block_layout.dart';
import 'rich_html.dart';

/// Una página ya repartida: lo que cabe en una pantalla.
class BookPage {
  const BookPage({required this.blocks, required this.startChar});

  /// Los bloques que se pintan, ya partidos por donde hizo falta.
  final List<HtmlBlock> blocks;

  /// En qué carácter del texto del capítulo empieza esta página.
  ///
  /// Es lo único que ata la paginación al resto del proyecto. El número de
  /// página **no se guarda en ninguna parte**: con otro cuerpo de letra ya no
  /// significa lo mismo. Lo que se guarda es la posición, y sale de aquí:
  /// `startChar / total` es la fracción que `ReflowableSource.locatorAt` sabe
  /// convertir en un `CharLocator` o un `EpubLocator`.
  final int startChar;
}

/// El capítulo repartido en páginas.
class PagedChapter {
  const PagedChapter({required this.pages, required this.totalChars});

  final List<BookPage> pages;

  /// Longitud del texto del capítulo, el denominador de la fracción.
  final int totalChars;

  int get length => pages.length;

  /// Qué página contiene un carácter dado.
  ///
  /// Es la operación de «vuelve a donde estabas» después de repaginar: se
  /// conserva el carácter, no el número de página.
  int pageForChar(int char) {
    for (var i = pages.length - 1; i >= 0; i--) {
      if (pages[i].startChar <= char) return i;
    }
    return 0;
  }

  /// La fracción del capítulo en la que empieza la página [index].
  double fractionAt(int index) {
    if (totalChars <= 0 || pages.isEmpty) return 0;
    final page = pages[index.clamp(0, pages.length - 1)];
    return (page.startChar / totalChars).clamp(0.0, 1.0);
  }
}

/// Reparte los bloques de un capítulo en páginas del tamaño de la pantalla.
///
/// Corta **por línea, nunca a media línea**: un párrafo que no cabe entero se
/// parte por el último renglón que sí cabe y el resto pasa a la página
/// siguiente. Ésa es toda la diferencia entre un lector y un cuadro de texto
/// recortado.
///
/// Se apoya en [BlockLayout] para medir, que es el mismo sitio del que sale lo
/// que después se pinta. Si midiera por su cuenta, las dos mitades divergirían
/// y el texto se cortaría mal.
abstract final class Paginator {
  static PagedChapter paginate({
    required List<HtmlBlock> blocks,
    required ReadingSettings settings,
    required Size viewport,
  }) {
    final width = viewport.width;
    final height = viewport.height;
    // El total se cuenta con la misma regla que los comienzos de página, no
    // con `RichHtml.plainText`, que mete un salto de línea por bloque: si las
    // dos cuentas no coincidieran, la fracción guardada apuntaría a otro sitio.
    final total = blocks.fold<int>(0, (sum, b) => sum + _charsOf(b));

    // Una pantalla imposible —cero de alto, que pasa en el primer fotograma—
    // no debe colgar el bucle ni devolver mil páginas vacías.
    if (blocks.isEmpty || width <= 0 || height <= 0) {
      return PagedChapter(
        // Nunca una lista vacía: quien pinta espera al menos una página.
        pages: [BookPage(blocks: blocks, startChar: 0)],
        totalChars: total,
      );
    }

    final pages = <BookPage>[];
    var current = <HtmlBlock>[];
    var used = 0.0;
    var charsBefore = 0;
    var pageStart = 0;

    void closePage() {
      pages.add(BookPage(blocks: current, startChar: pageStart));
      current = [];
      used = 0;
    }

    for (final block in blocks) {
      final blockChars = _charsOf(block);

      // Una imagen se lleva su página entera: no se sabe lo que mide sin
      // decodificarla, y no hace falta saberlo si nada la acompaña.
      if (BlockLayout.ownPage(block)) {
        if (current.isNotEmpty) closePage();
        pageStart = charsBefore;
        current = [block];
        closePage();
        charsBefore += blockChars;
        pageStart = charsBefore;
        continue;
      }

      var pending = block;
      var pendingChars = charsBefore;

      while (true) {
        final needed = BlockLayout.measure(pending, settings, width);
        if (used + needed <= height) {
          if (current.isEmpty) pageStart = pendingChars;
          current.add(pending);
          used += needed;
          break;
        }

        // No cabe entero. Se intenta partirlo por el último renglón que quepa.
        final split = _splitToFit(
          pending,
          settings,
          width,
          height - used,
        );

        if (split == null) {
          // No cabe ni una línea en lo que queda. Si la página ya tiene algo,
          // se cierra y se reintenta entero en la siguiente; si está vacía, el
          // bloque no cabe ni en una página en blanco —un `<pre>` enorme— y se
          // deja desbordar antes que perderlo o entrar en bucle.
          if (current.isNotEmpty) {
            closePage();
            continue;
          }
          pageStart = pendingChars;
          current.add(pending);
          used = height;
          break;
        }

        if (current.isEmpty) pageStart = pendingChars;
        current.add(split.head);
        closePage();

        pendingChars += _charsOf(split.head);
        pending = split.tail;
      }

      charsBefore += blockChars;
    }

    if (current.isNotEmpty) closePage();
    if (pages.isEmpty) {
      pages.add(const BookPage(blocks: [], startChar: 0));
    }

    return PagedChapter(pages: pages, totalChars: total);
  }

  /// Parte [block] para que su primera mitad quepa en [available].
  ///
  /// Devuelve `null` si no cabe ni la primera línea, o si el bloque no se puede
  /// partir. El texto preformateado entra en el segundo caso: partirlo por un
  /// renglón cualquiera destruiría justo lo que lo hace preformateado.
  static _Split? _splitToFit(
    HtmlBlock block,
    ReadingSettings settings,
    double width,
    double available,
  ) {
    if (block is HtmlPre || block is HtmlRule || block is HtmlImage) return null;

    final span = BlockLayout.spanOf(block, settings);
    if (span == null) return null;

    final insets = BlockLayout.insetsOf(block);
    // Los márgenes de **los dos lados** se descuentan del sitio disponible. El
    // de abajo también, aunque detrás no vaya nada: el widget lo pinta igual, y
    // olvidarlo hacía que la página desbordara justo por ese hueco.
    final room = available - insets.vertical;
    if (room <= 0) return null;

    final painter = BlockLayout.paint(span, width - insets.horizontal);
    final lines = painter.computeLineMetrics();

    var consumed = 0.0;
    var fits = 0;
    for (final line in lines) {
      if (consumed + line.height > room) break;
      consumed += line.height;
      fits++;
    }

    // Ni una línea entera, o todas: en ninguno de los dos casos hay que partir.
    if (fits == 0 || fits >= lines.length) {
      painter.dispose();
      return null;
    }

    // Dónde empieza la primera línea que no cabe. Se pregunta por el carácter
    // que hay justo debajo del corte, en el borde izquierdo.
    final cut = painter
        .getPositionForOffset(Offset(0, consumed + 1))
        .offset;
    painter.dispose();

    final runs = _runsOf(block);
    if (cut <= 0) return null;
    final (head, tail) = _splitRuns(runs, cut);
    if (head.isEmpty || tail.isEmpty) return null;

    return _Split(_withRuns(block, head), _withRuns(block, tail));
  }

  static List<TextRun> _runsOf(HtmlBlock block) => switch (block) {
    HtmlParagraph(:final runs) => runs,
    HtmlHeading(:final runs) => runs,
    HtmlQuote(:final runs) => runs,
    HtmlListItem(:final runs) => runs,
    _ => const [],
  };

  /// El mismo bloque con otros trozos de texto dentro.
  static HtmlBlock _withRuns(HtmlBlock block, List<TextRun> runs) =>
      switch (block) {
        HtmlParagraph() => HtmlParagraph(runs),
        HtmlHeading(:final level) => HtmlHeading(level, runs),
        HtmlQuote() => HtmlQuote(runs),
        // La continuación de un elemento de lista en la página siguiente no
        // repite la viñeta: no es otro elemento, es el mismo partido en dos.
        HtmlListItem(:final depth) => HtmlListItem(
          marker: '',
          runs: runs,
          depth: depth,
        ),
        _ => block,
      };

  /// Parte una lista de trozos por un desplazamiento en caracteres.
  static (List<TextRun>, List<TextRun>) _splitRuns(
    List<TextRun> runs,
    int offset,
  ) {
    final head = <TextRun>[];
    final tail = <TextRun>[];
    var seen = 0;

    for (final run in runs) {
      final end = seen + run.text.length;
      if (end <= offset) {
        head.add(run);
      } else if (seen >= offset) {
        tail.add(run);
      } else {
        // El corte cae dentro de este trozo: se parte conservando su énfasis.
        head.add(run.withText(run.text.substring(0, offset - seen)));
        tail.add(run.withText(run.text.substring(offset - seen)));
      }
      seen = end;
    }

    return (head, tail);
  }

  static int _charsOf(HtmlBlock block) => switch (block) {
    HtmlPre(:final text) => text.length,
    HtmlRule() || HtmlImage() => 0,
    _ => _runsOf(block).fold(0, (sum, run) => sum + run.text.length),
  };
}

class _Split {
  const _Split(this.head, this.tail);

  final HtmlBlock head;
  final HtmlBlock tail;
}
