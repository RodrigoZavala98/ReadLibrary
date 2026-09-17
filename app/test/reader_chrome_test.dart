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

/// El cromo del lector: la píldora flotante y sus paneles.
///
/// Antes los controles eran dos barras llenas y una hoja modal. La hoja tapaba
/// el libro tras una barrera, así que pasar de los temas a la tipografía
/// obligaba a cerrarla y volver a abrirla. Lo que se comprueba aquí es lo que
/// cambió: que todo vive en la píldora, que los paneles se turnan sin cerrarse
/// y que A− y A+ actúan sin abrir nada.
void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_cromo_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

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

  Future<void> abrirLector(
    WidgetTester tester, {
    ReadingSettings? ajustes,
  }) async {
    final book = await prepararTxt(tester);
    if (ajustes != null) {
      await tester.runAsync(() => services.settings.save(ajustes));
    }
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

  Future<void> sacarControles(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(ReaderScreen)));
    await tester.pump();
  }

  Future<void> tocarBoton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await asentar(tester);
  }

  ReadingSettings estiloAplicado(WidgetTester tester) =>
      tester.widget<HtmlBlockView>(find.byType(HtmlBlockView).first).style;

  /// Cada panel se reconoce por una etiqueta que sólo aparece en él.
  final panelTexto = find.text('Interlineado');
  final panelTemas = find.text('Tema');
  final panelBrillo = find.text('Brillo');

  group('la píldora', () {
    testWidgets('está escondida hasta tocar el centro', (tester) async {
      await abrirLector(tester);

      for (final boton in ['Texto', 'Brillo', 'Temas', 'Índice']) {
        expect(find.byTooltip(boton), findsNothing, reason: boton);
      }

      await sacarControles(tester);

      for (final boton in ['Texto', 'Brillo', 'Temas', 'Índice']) {
        expect(find.byTooltip(boton), findsOneWidget, reason: boton);
      }
    });

    testWidgets('la cabecera se quedó sin iconos', (tester) async {
      // Lo que antes eran dos iconos sueltos arriba está ahora en la píldora.
      // Sólo sobrevive la flecha de volver.
      await abrirLector(tester);
      await sacarControles(tester);

      expect(find.byTooltip('Volver a la biblioteca'), findsOneWidget);
      expect(find.byTooltip('Ajustes de lectura'), findsNothing);
    });

    testWidgets('la barra de capítulos sigue bajo la píldora', (tester) async {
      // Se mantuvo a propósito aunque no esté en el diseño.
      await abrirLector(tester);
      await sacarControles(tester);

      expect(find.textContaining('Capítulo 1 de'), findsOneWidget);
      expect(find.byTooltip('Capítulo siguiente'), findsOneWidget);
    });
  });

  group('los paneles se turnan', () {
    testWidgets('un botón abre su panel y el mismo botón lo cierra', (
      tester,
    ) async {
      await abrirLector(tester);
      await sacarControles(tester);
      expect(panelTexto, findsNothing);

      await tocarBoton(tester, 'Texto');
      expect(panelTexto, findsOneWidget);

      await tocarBoton(tester, 'Texto');
      expect(panelTexto, findsNothing);
    });

    testWidgets('otro botón cambia de panel sin cerrar nada', (tester) async {
      // Éste es el motivo de todo el rediseño: con la hoja modal había que
      // cerrarla y volver a abrirla para ver otra cosa.
      await abrirLector(tester);
      await sacarControles(tester);

      await tocarBoton(tester, 'Texto');
      expect(panelTexto, findsOneWidget);

      await tocarBoton(tester, 'Temas');
      expect(panelTemas, findsOneWidget);
      expect(panelTexto, findsNothing);

      await tocarBoton(tester, 'Brillo');
      expect(panelBrillo, findsOneWidget);
      expect(panelTemas, findsNothing);
    });

    testWidgets('esconder los controles se lleva el panel abierto', (
      tester,
    ) async {
      // Un cajón desplegado sin la píldora que lo abrió se queda huérfano.
      await abrirLector(tester);
      await sacarControles(tester);
      await tocarBoton(tester, 'Texto');
      expect(panelTexto, findsOneWidget);

      await sacarControles(tester);
      expect(panelTexto, findsNothing);

      // Y al volver a sacarlos no reaparece solo.
      await sacarControles(tester);
      expect(find.byTooltip('Texto'), findsOneWidget);
      expect(panelTexto, findsNothing);
    });

    testWidgets('el índice salta de capítulo y se cierra al elegir', (
      tester,
    ) async {
      await abrirLector(tester);
      await sacarControles(tester);
      await tocarBoton(tester, 'Índice');

      await tester.tap(find.text('Parte 2').first);
      await asentar(tester);

      expect(find.textContaining('Capítulo 2 de'), findsOneWidget);
      // Has terminado de navegar: dejarlo abierto taparía el sitio al que
      // acabas de saltar.
      expect(find.text('Parte 2'), findsNothing);
    });
  });

  group('A− y A+', () {
    testWidgets('cambian el cuerpo de letra sin abrir ningún panel', (
      tester,
    ) async {
      await abrirLector(tester);
      final antes = estiloAplicado(tester).fontSize;
      await sacarControles(tester);

      await tocarBoton(tester, 'Más tamaño');

      expect(estiloAplicado(tester).fontSize, antes + 1);
      expect(panelTexto, findsNothing, reason: 'son acción directa');

      await tocarBoton(tester, 'Menos tamaño');
      expect(estiloAplicado(tester).fontSize, antes);
    });

    testWidgets('se guardan solos, como el resto de ajustes', (tester) async {
      await abrirLector(tester);
      await sacarControles(tester);

      await tocarBoton(tester, 'Más tamaño');

      final guardados = await tester.runAsync(services.settings.load);
      expect(guardados!.fontSize, ReadingSettings().fontSize + 1);
    });

    testWidgets('se apagan al llegar a los topes', (tester) async {
      await abrirLector(
        tester,
        ajustes: ReadingSettings(fontSize: ReadingSettings.maxFontSize),
      );
      await sacarControles(tester);

      final iconButtons = tester.widgetList<IconButton>(find.byType(IconButton));
      final mas = iconButtons.firstWhere((button) => button.tooltip == 'Más tamaño');
      final menos = iconButtons.firstWhere((button) => button.tooltip == 'Menos tamaño');

      expect(mas.onPressed, isNull, reason: 'no se puede pasar del tope');
      expect(menos.onPressed, isNotNull);
    });
  });
}
