import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reading_settings.dart';
import 'package:lector/ui/paged_reader.dart';
import 'package:lector/ui/reader_screen.dart';

import 'epub_fixture.dart';

void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_paginas_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Un TXT con párrafos numerados: saber qué página se está viendo es tan
  /// fácil como mirar qué número sale.
  Future<LibraryBook> prepararTxt(
    WidgetTester tester, {
    int parrafos = 120,
    ReadingSettings? settings,
  }) async {
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
        List.generate(
          parrafos,
          (i) => 'Párrafo $i. ${'palabra ' * 20}',
        ).join('\n\n'),
      );
      await services.repository.save(book);
      if (settings != null) await services.settings.save(settings);
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

  /// Toca en un punto horizontal de la pantalla del lector.
  Future<void> tocarEn(WidgetTester tester, double fraccionAncho) async {
    final rect = tester.getRect(find.byType(ReaderScreen));
    await tester.tapAt(
      Offset(rect.left + rect.width * fraccionAncho, rect.center.dy),
    );
    await asentar(tester);
  }

  /// El porcentaje del hilo del margen, que es «por dónde voy».
  ///
  /// No vale mirar qué párrafo aparece en el árbol: un `PageView` mantiene
  /// vivas las páginas de al lado, así que el texto de la página anterior sigue
  /// encontrándose aunque ya no se vea. El porcentaje, en cambio, sale de la
  /// página en la que el lector cree estar, que es justo lo que se comprueba.
  int avance(WidgetTester tester) {
    final texto = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.endsWith(' %'), orElse: () => '');
    expect(texto, isNotEmpty, reason: 'el hilo de avance siempre está');
    return int.parse(texto.replaceAll(' %', ''));
  }

  group('pasar página', () {
    testWidgets('de fábrica el lector está paginado', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));

      expect(find.byType(PagedReader), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReaderScreen),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
    });

    testWidgets('tocar el borde derecho avanza', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      final antes = avance(tester);

      await tocarEn(tester, 0.9);

      expect(avance(tester), greaterThan(antes));
    });

    testWidgets('tocar el borde izquierdo retrocede', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      await tocarEn(tester, 0.9);
      final avanzado = avance(tester);

      await tocarEn(tester, 0.1);

      expect(avance(tester), lessThan(avanzado));
    });

    testWidgets('tocar el centro saca los controles y no pasa página',
        (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      final antes = avance(tester);

      await tocarEn(tester, 0.5);

      expect(find.byTooltip('Ajustes de lectura'), findsOneWidget);
      expect(avance(tester), antes);
    });

    testWidgets('deslizar el dedo también pasa página', (tester) async {
      await abrirLector(tester, await prepararTxt(tester));
      final antes = avance(tester);

      // Se arrastra una pantalla entera: a media pantalla justa, el `PageView`
      // decide por velocidad y el gesto puede quedarse donde estaba.
      await tester.drag(find.byType(PagedReader), const Offset(-700, 0));
      await asentar(tester);

      expect(avance(tester), greaterThan(antes));
    });
  });

  group('entre capítulos', () {
    testWidgets('pasar de la última página entra en el capítulo siguiente',
        (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      expect(find.textContaining('Primera página'), findsOneWidget);

      // El capítulo de prueba cabe en una página, así que la primera es también
      // la última: un toque adelante ya tiene que saltar de capítulo.
      await tocarEn(tester, 0.9);

      expect(find.textContaining('Última página'), findsOneWidget);
      expect(find.textContaining('Primera página'), findsNothing);
    });

    testWidgets('retroceder desde la primera vuelve al capítulo anterior',
        (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      await tocarEn(tester, 0.9);
      expect(find.textContaining('Última página'), findsOneWidget);

      await tocarEn(tester, 0.1);

      expect(find.textContaining('Primera página'), findsOneWidget);
    });

    testWidgets('en el último capítulo, avanzar no hace nada', (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      await tocarEn(tester, 0.9);

      await tocarEn(tester, 0.9);

      expect(find.textContaining('Última página'), findsOneWidget);
    });
  });

  group('los ajustes mueven las páginas, no al lector', () {
    testWidgets('cambiar el cuerpo de letra deja en el mismo texto',
        (tester) async {
      // Es la promesa de guardar el carácter y no el número de página.
      await abrirLector(tester, await prepararTxt(tester));
      await tocarEn(tester, 0.9);
      await tocarEn(tester, 0.9);
      final antes = avance(tester);

      await tocarEn(tester, 0.5);
      await tester.tap(find.byTooltip('Ajustes de lectura'));
      await asentar(tester);
      final mas = find.byTooltip('Tamaño: más');
      await tester.ensureVisible(mas);
      await tester.pump();
      await tester.tap(mas);
      await asentar(tester);

      // Con letra más grande cabe menos en cada página, así que el número de
      // página cambia; el punto del libro en el que estabas, no.
      expect(avance(tester), closeTo(antes, 2));
    });

    testWidgets('la escala de fuente del sistema no descuadra las páginas',
        (tester) async {
      // Regresión de la trampa más fina de toda la paginación: `Text` aplica la
      // escala de fuente del sistema y el paginador mide sin ella. Con la
      // escala al 180 %, lo pintado sería casi el doble de alto que lo medido y
      // cada página desbordaría. El lector fija `noScaling` al pintar por eso:
      // el cuerpo de letra se elige dentro de la aplicación.
      final book = await prepararTxt(tester);

      await tester.runAsync(
        () => tester.pumpWidget(
          AppScope(
            services: services,
            child: MaterialApp(
              theme: ChromeTheme.build(),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.8),
                  ),
                  child: ReaderScreen(book: book),
                ),
              ),
            ),
          ),
        ),
      );
      await asentar(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'ninguna página se desborda con la letra del sistema al 180 %',
      );
      expect(find.byType(PagedReader), findsOneWidget);
    });

    testWidgets('en modo continuo vuelve el desplazamiento vertical',
        (tester) async {
      await abrirLector(
        tester,
        await prepararTxt(
          tester,
          settings: ReadingSettings(mode: ReadingMode.continuo),
        ),
      );

      expect(find.byType(PagedReader), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ReaderScreen),
          matching: find.byType(ListView),
        ),
        findsOneWidget,
      );
    });
  });

  group('animaciones', () {
    for (final animation in PageAnimation.values) {
      testWidgets('el lector se monta y pasa página con «${animation.label}»',
          (tester) async {
        // Con `doblar` esta prueba hace algo más que comprobar el gesto:
        // compila `page_flip`, que es la única dependencia de terceros del
        // lector. Si rompiera con una versión de Flutter, saltaría aquí y no
        // en integración continua.
        await abrirLector(
          tester,
          await prepararTxt(
            tester,
            settings: ReadingSettings(animation: animation),
          ),
        );

        expect(find.byType(PagedReader), findsOneWidget);
        final antes = avance(tester);

        await tocarEn(tester, 0.9);

        expect(
          avance(tester),
          greaterThan(antes),
          reason: 'con ${animation.label} también se pasa página',
        );
      });
    }
  });
}
