import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/main.dart';
import 'package:lector/shell/home_shell.dart';

void main() {
  testWidgets('arranca en la biblioteca y muestra las cuatro secciones', (
    tester,
  ) async {
    await tester.pumpWidget(const LectorApp());

    // El rótulo de la sección activa aparece dos veces —en la pestaña y como
    // título— así que basta con comprobar que las cuatro están presentes.
    for (final section in HomeSection.values) {
      expect(find.text(section.label), findsAtLeastNWidgets(1));
    }
    expect(find.text('Tus libros, con portada y progreso.'), findsOneWidget);
  });

  testWidgets('cambiar de sección cambia el contenido', (tester) async {
    await tester.pumpWidget(const LectorApp());

    await tester.tap(find.text(HomeSection.notas.label));
    await tester.pumpAndSettle();

    expect(
      find.text('Frases guardadas y subrayados de tus lecturas.'),
      findsOneWidget,
    );
    expect(find.text('Tus libros, con portada y progreso.'), findsNothing);
  });

  testWidgets('la barra de cuatro pestañas no desborda en pantalla estrecha', (
    tester,
  ) async {
    // 320 px lógicos es lo más angosto que se encuentra hoy en Android.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LectorApp());
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'un RenderFlex overflow aparecería aquí',
    );
  });
}
