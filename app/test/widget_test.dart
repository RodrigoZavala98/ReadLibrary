import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/main.dart';
import 'package:lector/shell/home_shell.dart';

void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_ui_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Monta la aplicación y espera a que la biblioteca termine de cargarse.
  ///
  /// No se usa `pumpAndSettle`: mientras la carga está en curso se muestra un
  /// `CircularProgressIndicator`, que anima sin parar y hace que «asentar» no
  /// ocurra jamás — la prueba se quedaría colgada hasta agotar su plazo interno
  /// de diez minutos. `runAsync` deja correr la lectura real de disco, y los
  /// `pump` posteriores pintan el resultado.
  Future<void> arrancar(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(LectorApp(services: services));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
  }

  /// Guarda un libro antes de montar la interfaz.
  ///
  /// El `runAsync` es imprescindible: `testWidgets` ejecuta el cuerpo de la
  /// prueba con un reloj simulado, y las entradas/salidas de disco reales se
  /// resuelven en el bucle de eventos de verdad. Sin esto, el `await` de un
  /// guardado no vuelve nunca y la prueba se cuelga.
  Future<void> guardar(WidgetTester tester, LibraryBook book) =>
      tester.runAsync(() => services.repository.save(book));

  testWidgets('arranca en la biblioteca y muestra las cuatro secciones',
      (tester) async {
    await arrancar(tester);

    // El rótulo de la sección activa puede aparecer también como título, así
    // que basta con comprobar que las cuatro están presentes.
    for (final section in HomeSection.values) {
      expect(find.text(section.label), findsAtLeastNWidgets(1));
    }
  });

  testWidgets('una biblioteca vacía invita a añadir un libro', (tester) async {
    await arrancar(tester);

    expect(find.text('Tu biblioteca está vacía'), findsOneWidget);
    expect(find.text('Añadir un libro'), findsOneWidget);
  });

  testWidgets('los libros guardados aparecen con su progreso', (tester) async {
    await guardar(
      tester,
      LibraryBook(
        id: 1,
        filePath: '${temp.path}/dune.txt',
        format: BookFormat.txt,
        title: 'Dune',
        addedAt: DateTime(2026, 3, 1),
        progress: 0.65,
      ),
    );

    await arrancar(tester);

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('65 %'), findsOneWidget);
    expect(find.text('Tu biblioteca está vacía'), findsNothing);
  });

  testWidgets('un libro sin empezar se distingue de uno en curso',
      (tester) async {
    await guardar(
      tester,
      LibraryBook(
        id: 1,
        filePath: '${temp.path}/nuevo.txt',
        format: BookFormat.txt,
        title: 'Recién llegado',
        addedAt: DateTime(2026, 3, 1),
      ),
    );

    await arrancar(tester);

    expect(find.text('Sin empezar'), findsOneWidget);
  });

  testWidgets('cambiar de sección cambia el contenido', (tester) async {
    await arrancar(tester);

    await tester.tap(find.text(HomeSection.notas.label));
    await tester.pump();

    expect(
      find.text('Frases guardadas y subrayados de tus lecturas.'),
      findsOneWidget,
    );
    expect(find.text('Tu biblioteca está vacía'), findsNothing);
  });

  testWidgets('la barra de cuatro pestañas no desborda en pantalla estrecha',
      (tester) async {
    // 320 px lógicos es lo más angosto que se encuentra hoy en Android.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await arrancar(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'un RenderFlex overflow aparecería aquí',
    );
  });
}
