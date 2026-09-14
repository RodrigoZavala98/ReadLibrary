import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/ui/reader_screen.dart';

/// Regresión de un fallo real: al salir del lector no se guardaba nada.
///
/// La causa era que `dispose()` llamaba a `AppScope.of(context)`, y Flutter
/// prohíbe buscar un antecesor heredado desde un widget ya desactivado. La
/// excepción saltaba justo en el momento de persistir, así que ni la posición
/// ni la sesión llegaban al disco: el libro seguía marcado «sin empezar» y la
/// racha no avanzaba por muchos minutos que se leyera.
void main() {
  late Directory temp;
  late AppServices services;
  late DateTime ahora;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_persist_');
    services = AppServices.forDirectory(temp);
    ahora = DateTime(2026, 3, 15, 20, 0);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<LibraryBook> prepararLibro(WidgetTester tester) async {
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

  /// Monta el lector solo, con un reloj que controlamos.
  Future<void> abrirLector(WidgetTester tester, LibraryBook book) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: ChromeTheme.build(),
            home: ReaderScreen(book: book, now: () => ahora),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Cierra el lector sustituyendo el árbol, que provoca su dispose().
  Future<void> cerrarLector(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(const MaterialApp(home: SizedBox())),
    );
    await asentar(tester);
  }

  testWidgets('el libro se abre y muestra su texto', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    expect(find.textContaining('Párrafo 0.'), findsOneWidget);
  });

  testWidgets('al salir se registra la sesión de lectura', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    // Nueve minutos de lectura, como en el informe del fallo.
    ahora = ahora.add(const Duration(minutes: 9));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, hasLength(1));
    expect(sesiones!.single.duration, const Duration(minutes: 9));
    expect(sesiones.single.bookId, 1);
  });

  testWidgets('al salir se marca el libro como empezado', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    ahora = ahora.add(const Duration(minutes: 9));
    await cerrarLector(tester);

    final guardado = await tester.runAsync(() => services.repository.byId(1));
    expect(guardado, isNotNull);
    expect(
      guardado!.lastOpenedAt,
      isNotNull,
      reason: 'sin esto la biblioteca lo seguiría llamando «sin empezar»',
    );
    expect(guardado.isStarted, isTrue);
  });

  testWidgets('abrir y salir enseguida no registra sesión', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    ahora = ahora.add(const Duration(seconds: 3));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, isEmpty, reason: 'no debe regalar racha por un despiste');
  });

  testWidgets('el tiempo en segundo plano no se contabiliza', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    // Lee seis minutos, bloquea el móvil, y lo recupera dos horas después.
    ahora = ahora.add(const Duration(minutes: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    ahora = ahora.add(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ahora = ahora.add(const Duration(minutes: 4));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(
      sesiones!.single.duration,
      const Duration(minutes: 10),
      reason: 'las dos horas con la pantalla apagada no son lectura',
    );
  });
}
