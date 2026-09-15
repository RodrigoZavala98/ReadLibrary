import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/main.dart';
import 'package:lector/shell/home_shell.dart';
import 'package:lector/ui/reader_screen.dart';

/// Regresión: al volver del lector, la biblioteca seguía mostrando el avance
/// anterior hasta cambiar de pestaña y regresar.
///
/// La causa era una carrera. El guardado se hacía en `dispose()` sin esperar
/// su resultado, y la biblioteca recargaba en cuanto el Navigator devolvía el
/// control — a veces antes de que el guardado hubiera terminado, y a veces
/// antes incluso de que `dispose()` se ejecutara, porque la ruta se destruye
/// al acabar la animación de cierre.
void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_refresh_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  /// La biblioteca queda montada detrás del lector, así que hay dos listas en
  /// el árbol. Hay que apuntar a la del lector explícitamente.
  final textoDelLibro = find.descendant(
    of: find.byType(ReaderScreen),
    matching: find.byType(ListView),
  );

  Future<void> arrancarConUnLibro(WidgetTester tester) async {
    final file = File('${temp.path}${Platform.pathSeparator}dune.txt');
    await tester.runAsync(() async {
      await file.writeAsString(
        List.generate(400, (i) => 'Párrafo $i. ${'palabra ' * 20}').join('\n\n'),
      );
      await services.repository.save(
        LibraryBook(
          id: 1,
          filePath: file.path,
          format: BookFormat.txt,
          title: 'Dune',
          addedAt: DateTime(2026, 3, 1),
        ),
      );
    });

    await tester.runAsync(
      () => tester.pumpWidget(LectorApp(services: services)),
    );
    await asentar(tester);
  }

  testWidgets('el avance se ve al volver, sin cambiar de pestaña',
      (tester) async {
    await arrancarConUnLibro(tester);
    expect(find.text('Sin empezar'), findsOneWidget);

    await tester.tap(find.text('Dune'));
    await asentar(tester);

    await tester.drag(textoDelLibro, const Offset(0, -30000));
    await tester.pump();

    // Los controles del lector están ocultos hasta tocar el centro.
    await tester.tap(textoDelLibro);
    await tester.pump();
    await tester.tap(find.byTooltip('Volver a la biblioteca'));
    await asentar(tester);

    // Sin tocar ninguna pestaña, la biblioteca ya refleja el avance.
    expect(find.text('Dune'), findsOneWidget);
    expect(
      find.text('Sin empezar'),
      findsNothing,
      reason: 'antes había que salir y volver para ver esto',
    );
    expect(find.textContaining('%'), findsOneWidget);
  });

  testWidgets('el gesto de atrás de Android también guarda', (tester) async {
    await arrancarConUnLibro(tester);

    await tester.tap(find.text('Dune'));
    await asentar(tester);
    await tester.drag(textoDelLibro, const Offset(0, -30000));
    await tester.pump();

    // Equivale al botón físico o al gesto de retroceso del sistema.
    await tester.binding.handlePopRoute();
    await asentar(tester);

    expect(find.text(HomeSection.biblioteca.label), findsAtLeastNWidgets(1));
    expect(find.text('Sin empezar'), findsNothing);
  });
}
