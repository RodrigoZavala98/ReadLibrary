import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reading_settings.dart';
import 'package:lector/ui/comic_reader_screen.dart';

import 'archive_fixture.dart';

/// El lector de cómics: páginas fijas, sin capítulos y sin tipografía.
///
/// Las ventanas de tiempo real y el orden de los `pump` siguen las mismas
/// reglas que las demás pruebas de lector, y por el mismo motivo: `testWidgets`
/// corre con reloj simulado, así que una operación de disco disparada desde la
/// zona simulada no se completa nunca.
void main() {
  late Directory temp;
  late AppServices services;
  late DateTime ahora;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_comic_');
    services = AppServices.forDirectory(temp);
    ahora = DateTime(2026, 3, 15, 20, 0);
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

  /// Escribe un cómic de [paginas] páginas y lo registra en la biblioteca.
  Future<LibraryBook> prepararComic(
    WidgetTester tester, {
    int paginas = 5,
    BookLocator? locator,
    String name = 'comic.cbz',
  }) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    final book = LibraryBook(
      id: 1,
      filePath: file.path,
      format: BookFormat.cbz,
      title: 'El cómic',
      addedAt: DateTime(2026, 3, 1),
      locator: locator,
    );

    await tester.runAsync(() async {
      await file.writeAsBytes(
        zipOf({
          for (var i = 1; i <= paginas; i++) 'p$i.png': pngBytes(grey: i),
        }),
      );
      await services.repository.save(book);
    });
    return book;
  }

  Future<void> abrirComic(WidgetTester tester, LibraryBook book) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: ChromeTheme.build(),
            home: ComicReaderScreen(book: book, now: () => ahora),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Saca u oculta los controles tocando el centro.
  Future<void> tocarCentro(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(ComicReaderScreen)));
    await tester.pump();
  }

  /// Cierra el lector sustituyendo el árbol, que provoca su dispose().
  Future<void> cerrarComic(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(const MaterialApp(home: SizedBox())),
    );
    await asentar(tester);
  }

  /// Guarda unos ajustes de lectura con el sentido pedido.
  Future<void> guardarSentido(
    WidgetTester tester,
    ComicDirection direction,
  ) async {
    await tester.runAsync(
      () => services.settings.save(ReadingSettings(comicDirection: direction)),
    );
  }

  testWidgets('abre el cómic y enseña su primera página', (tester) async {
    final book = await prepararComic(tester);
    await abrirComic(tester, book);

    expect(find.byType(Image), findsOneWidget);

    await tocarCentro(tester);
    expect(find.text('Página 1 de 5'), findsOneWidget);
  });

  testWidgets('retoma el cómic por la página donde se dejó', (tester) async {
    final book = await prepararComic(tester, locator: const PageLocator(3));
    await abrirComic(tester, book);

    await tocarCentro(tester);
    expect(find.text('Página 4 de 5'), findsOneWidget);
  });

  testWidgets('una página guardada más allá del final no rompe', (
    tester,
  ) async {
    // Pasa de verdad: basta con reemplazar el fichero por una edición con
    // menos páginas. Abrir por la última es preferible a no abrir.
    //
    // Lo que se comprueba es la garantía, no una línea concreta: quitar el
    // recorte de `load()` no hace fallar esta prueba, porque el `PageView`
    // corrige por su cuenta una página inicial fuera de rango. Se deja porque
    // la garantía es real y alguien puede romperla desde cualquiera de los dos
    // lados.
    final book = await prepararComic(
      tester,
      paginas: 3,
      locator: const PageLocator(40),
    );
    await abrirComic(tester, book);

    await tocarCentro(tester);
    expect(find.text('Página 3 de 3'), findsOneWidget);
  });

  testWidgets('tocar el borde derecho pasa de página', (tester) async {
    final book = await prepararComic(tester);
    await abrirComic(tester, book);

    final caja = tester.getRect(find.byType(ComicReaderScreen));
    await tester.tapAt(Offset(caja.right - 20, caja.center.dy));
    await asentar(tester);

    await tocarCentro(tester);
    expect(find.text('Página 2 de 5'), findsOneWidget);
  });

  testWidgets('en sentido manga el borde derecho retrocede', (tester) async {
    // El mismo toque en el mismo sitio tiene que hacer lo contrario: en un
    // manga la página siguiente está a la izquierda.
    await guardarSentido(tester, ComicDirection.manga);
    final book = await prepararComic(tester, locator: const PageLocator(2));
    await abrirComic(tester, book);

    final caja = tester.getRect(find.byType(ComicReaderScreen));
    await tester.tapAt(Offset(caja.right - 20, caja.center.dy));
    await asentar(tester);

    await tocarCentro(tester);
    expect(find.text('Página 2 de 5'), findsOneWidget);
  });

  testWidgets('el sentido guardado invierte el paso de páginas', (
    tester,
  ) async {
    await guardarSentido(tester, ComicDirection.manga);
    final book = await prepararComic(tester);
    await abrirComic(tester, book);

    expect(
      tester.widget<PageView>(find.byType(PageView)).reverse,
      isTrue,
      reason: 'un manga se recorre al revés',
    );
  });

  testWidgets('los controles no ofrecen índice ni tipografía', (tester) async {
    // Un cómic no tiene capítulos ni cuerpo de letra, así que esos dos botones
    // no deben aparecer: prometerían algo que no existe.
    final book = await prepararComic(tester);
    await abrirComic(tester, book);
    await tocarCentro(tester);

    expect(find.byTooltip('Índice'), findsNothing);
    expect(find.byTooltip('Ajustes de lectura'), findsNothing);
    expect(find.byTooltip('Sentido de lectura'), findsOneWidget);
  });

  testWidgets('salir guarda la página, el avance y una sola sesión', (
    tester,
  ) async {
    final book = await prepararComic(tester);
    await abrirComic(tester, book);

    final caja = tester.getRect(find.byType(ComicReaderScreen));
    await tester.tapAt(Offset(caja.right - 20, caja.center.dy));
    await asentar(tester);

    ahora = ahora.add(const Duration(minutes: 7));
    await cerrarComic(tester);

    final guardado = await tester.runAsync(() => services.repository.byId(1));
    expect(guardado!.locator, const PageLocator(1));
    // Segunda de cinco páginas: un cuarto del camino.
    expect(guardado.progress, closeTo(0.25, 0.001));
    // El cómic sabe cuántas páginas tiene, y el campo llevaba vacío desde el
    // primer día.
    expect(guardado.totalPages, 5);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, hasLength(1));
    expect(sesiones!.single.duration, const Duration(minutes: 7));
  });

  testWidgets('un cómic que no se puede abrir lo explica', (tester) async {
    final file = File('${temp.path}${Platform.pathSeparator}roto.cbz');
    final book = LibraryBook(
      id: 1,
      filePath: file.path,
      format: BookFormat.cbz,
      title: 'Roto',
      addedAt: DateTime(2026, 3, 1),
    );
    await tester.runAsync(() async {
      await file.writeAsBytes(zipOf({'leeme.txt': 'aquí no hay cómic'}));
      await services.repository.save(book);
    });

    await abrirComic(tester, book);

    expect(find.textContaining('ninguna imagen'), findsOneWidget);
  });

  testWidgets('salir de un cómic que no abrió no registra nada', (
    tester,
  ) async {
    // Sin páginas no hay posición que guardar, y machacar la que hubiera con
    // el principio del libro sería peor que no guardar.
    final file = File('${temp.path}${Platform.pathSeparator}roto.cbz');
    final book = LibraryBook(
      id: 1,
      filePath: file.path,
      format: BookFormat.cbz,
      title: 'Roto',
      addedAt: DateTime(2026, 3, 1),
      locator: const PageLocator(9),
    );
    await tester.runAsync(() async {
      await file.writeAsBytes(zipOf({'leeme.txt': 'nada'}));
      await services.repository.save(book);
    });

    await abrirComic(tester, book);
    await cerrarComic(tester);

    final guardado = await tester.runAsync(() => services.repository.byId(1));
    expect(guardado!.locator, const PageLocator(9));
  });
}
