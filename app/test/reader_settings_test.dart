import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reading_settings.dart';
import 'package:lector/ui/html_view.dart';
import 'package:lector/ui/reader_screen.dart';

import 'epub_fixture.dart';

void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_ajustes_ui_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Las mismas trampas de siempre: reloj simulado por un lado y disco real por
  /// otro, y nada de `pumpAndSettle` mientras haya un indicador girando.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<LibraryBook> prepararTxt(WidgetTester tester) async {
    final file = File('${temp.path}${Platform.pathSeparator}dune.txt');
    final book = LibraryBook(
      id: 1,
      filePath: file.path,
      format: BookFormat.txt,
      title: 'Dune',
      addedAt: DateTime(2026, 3, 1),
    );
    await tester.runAsync(() async {
      await file.writeAsString(
        List.generate(400, (i) => 'Párrafo $i. ${'palabra ' * 20}').join('\n\n'),
      );
      await services.repository.save(book);
    });
    return book;
  }

  Future<LibraryBook> prepararEpub(WidgetTester tester) async {
    final file = File('${temp.path}${Platform.pathSeparator}libro.epub');
    final book = LibraryBook(
      id: 2,
      filePath: file.path,
      format: BookFormat.epub,
      title: 'El libro',
      addedAt: DateTime(2026, 3, 1),
    );
    await tester.runAsync(() async {
      await file.writeAsBytes(zipOf(sampleEpub2()));
      await services.repository.save(book);
    });
    return book;
  }

  Future<void> abrirLector(WidgetTester tester, LibraryBook book) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: ChromeTheme.build(),
            home: ReaderScreen(book: book),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> cerrarLector(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(const MaterialApp(home: SizedBox())),
    );
    await asentar(tester);
  }

  /// Los controles están escondidos hasta que se toca el centro.
  Future<void> sacarControles(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ReaderScreen),
        matching: find.byType(ListView),
      ),
    );
    await tester.pump();
  }

  Future<void> abrirAjustes(WidgetTester tester) async {
    await sacarControles(tester);
    await tester.tap(find.byTooltip('Ajustes de lectura'));
    await asentar(tester);
  }

  Color fondoDelLector(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

  ReadingSettings estiloAplicado(WidgetTester tester) =>
      tester.widget<HtmlBlockView>(find.byType(HtmlBlockView).first).style;

  group('avance visible', () {
    testWidgets('el porcentaje se ve sin sacar los controles', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));

      expect(
        find.text('0 %'),
        findsOneWidget,
        reason: 'el hilo del margen está siempre, los controles no',
      );
      expect(find.byTooltip('Ajustes de lectura'), findsNothing);
    });

    testWidgets('con los controles fuera se dice también el capítulo',
        (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      await sacarControles(tester);

      expect(find.textContaining('% del libro'), findsOneWidget);
      expect(find.textContaining('Capítulo 1 de'), findsOneWidget);
    });
  });

  group('ajustes de lectura', () {
    testWidgets('cambiar de tema repinta el libro al momento', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      final antes = fondoDelLector(tester);
      await abrirAjustes(tester);

      await tester.tap(find.text('Oscuro'));
      await asentar(tester);

      expect(fondoDelLector(tester), isNot(antes));
      expect(
        fondoDelLector(tester),
        ReadingPalette.of(ReadingTheme.oscuro).background,
      );
    });

    testWidgets('cambiar la fuente llega al texto', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      await abrirAjustes(tester);

      await tester.tap(find.text('Open Sans'));
      await asentar(tester);

      expect(estiloAplicado(tester).fontFamily, 'Open Sans');
    });

    testWidgets('el tamaño sube de uno en uno y se aplica', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      final antes = estiloAplicado(tester).fontSize;
      await abrirAjustes(tester);

      await tester.tap(find.byTooltip('Tamaño: más'));
      await asentar(tester);

      expect(estiloAplicado(tester).fontSize, antes + 1);
    });

    testWidgets('lo elegido sobrevive a cerrar y reabrir el libro',
        (tester) async {
      final book = await prepararTxt(tester);
      await abrirLector(tester, book);
      await abrirAjustes(tester);

      await tester.tap(find.byTooltip('Interlineado: más'));
      await asentar(tester);
      await tester.tap(find.text('Sepia'));
      await asentar(tester);

      // Se guarda en cada toque, no al cerrar la hoja.
      final guardados = await tester.runAsync(services.settings.load);
      expect(guardados!.theme, ReadingTheme.sepia);

      await cerrarLector(tester);
      await abrirLector(tester, book);

      expect(
        fondoDelLector(tester),
        ReadingPalette.of(ReadingTheme.sepia).background,
      );
      expect(estiloAplicado(tester).lineHeight, closeTo(1.7, 0.001));
    });

    testWidgets('el brillo del sistema y el brillo al mínimo no se confunden',
        (tester) async {
      // El interruptor empieza puesto: de fábrica no se toca el brillo.
      await abrirLector(tester, await prepararTxt(tester));
      await abrirAjustes(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await asentar(tester);

      final guardados = await tester.runAsync(services.settings.load);
      expect(guardados!.usesSystemBrightness, isFalse);
      expect(guardados.brightness, isNotNull);
      expect(guardados.brightness, greaterThan(0));
    });
  });

  group('índice', () {
    testWidgets('lista los capítulos con su título real', (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      await sacarControles(tester);

      await tester.tap(find.byTooltip('Índice'));
      await asentar(tester);

      expect(find.text('2 capítulos'), findsOneWidget);
      expect(find.text('El principio'), findsWidgets);
      expect(find.text('El final'), findsOneWidget);
    });

    testWidgets('tocar un capítulo salta a él', (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      expect(find.textContaining('Primera página'), findsOneWidget);

      await sacarControles(tester);
      await tester.tap(find.byTooltip('Índice'));
      await asentar(tester);
      await tester.tap(find.text('El final'));
      await asentar(tester);

      expect(find.textContaining('Última página'), findsOneWidget);
      expect(find.textContaining('Primera página'), findsNothing);
    });

    testWidgets('un TXT también tiene índice, con sus partes', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      await sacarControles(tester);

      await tester.tap(find.byTooltip('Índice'));
      await asentar(tester);

      // El mismo índice sirve para los dos formatos porque los dos rellenan
      // `chapters`: en un TXT son los trozos en que se parte el fichero.
      expect(find.textContaining('capítulos'), findsOneWidget);
      expect(find.text('Parte 1'), findsWidgets);
    });
  });
}
