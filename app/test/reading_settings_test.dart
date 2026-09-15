import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/reading_settings.dart';

void main() {
  test('los valores de fábrica son los de siempre', () {
    final settings = ReadingSettings();
    expect(settings.theme, ReadingTheme.claro);
    expect(settings.font, ReadingFont.literata);
    expect(settings.fontSize, 19);
    expect(settings.lineHeight, 1.6);
    expect(settings.margin, 24);
    expect(settings.brightness, isNull);
  });

  group('los rangos se recortan en el constructor', () {
    // No en la interfaz: el fichero de ajustes es un JSON en el disco y puede
    // llegar editado a mano o de una versión futura. Un cuerpo de letra de cero
    // deja el libro ilegible y sin forma evidente de deshacerlo.
    test('el tamaño de fuente no se sale por abajo ni por arriba', () {
      expect(ReadingSettings(fontSize: 0).fontSize, ReadingSettings.minFontSize);
      expect(
        ReadingSettings(fontSize: 400).fontSize,
        ReadingSettings.maxFontSize,
      );
    });

    test('el interlineado tampoco', () {
      expect(
        ReadingSettings(lineHeight: -3).lineHeight,
        ReadingSettings.minLineHeight,
      );
      expect(
        ReadingSettings(lineHeight: 99).lineHeight,
        ReadingSettings.maxLineHeight,
      );
    });

    test('el margen tampoco', () {
      expect(ReadingSettings(margin: 0).margin, ReadingSettings.minMargin);
      expect(ReadingSettings(margin: 5000).margin, ReadingSettings.maxMargin);
    });

    test('el brillo se queda entre cero y uno', () {
      expect(ReadingSettings(brightness: -1).brightness, 0);
      expect(ReadingSettings(brightness: 7).brightness, 1);
    });

    test('un número imposible cae al mínimo en vez de propagarse', () {
      // `double.nan` sobrevive a un clamp: compararlo siempre da falso. Sin
      // tratarlo aparte se colaría hasta el motor de texto.
      expect(
        ReadingSettings(fontSize: double.nan).fontSize,
        ReadingSettings.minFontSize,
      );
    });
  });

  group('el brillo del sistema no es el brillo cero', () {
    test('sin brillo elegido, manda el sistema', () {
      expect(ReadingSettings().usesSystemBrightness, isTrue);
    });

    test('el brillo al mínimo es una elección, no una ausencia', () {
      // Confundirlas apagaría la pantalla de quien sólo quería no opinar.
      final oscuro = ReadingSettings(brightness: 0);
      expect(oscuro.usesSystemBrightness, isFalse);
      expect(oscuro.brightness, 0);
    });
  });

  group('copyWith', () {
    test('cambia sólo lo que se le pasa', () {
      final antes = ReadingSettings(fontSize: 22, theme: ReadingTheme.sepia);
      final despues = antes.copyWith(font: ReadingFont.openSans);

      expect(despues.font, ReadingFont.openSans);
      expect(despues.fontSize, 22);
      expect(despues.theme, ReadingTheme.sepia);
    });

    test('también recorta lo que recibe', () {
      expect(
        ReadingSettings().copyWith(fontSize: 999).fontSize,
        ReadingSettings.maxFontSize,
      );
    });

    test('volver al brillo del sistema necesita su propio parámetro', () {
      // Con `null` no se distingue «devuélvelo al sistema» de «no lo toques».
      final conBrillo = ReadingSettings(brightness: 0.4);
      expect(conBrillo.copyWith().brightness, 0.4);
      expect(conBrillo.copyWith(useSystemBrightness: true).brightness, isNull);
    });
  });

  test('dos ajustes iguales se comparan como iguales', () {
    // Lo usa la pantalla para no guardar en disco cuando no ha cambiado nada.
    expect(
      ReadingSettings(fontSize: 20),
      ReadingSettings(fontSize: 20),
    );
    expect(
      ReadingSettings(fontSize: 20) == ReadingSettings(fontSize: 21),
      isFalse,
    );
  });

  test('cada tema y cada fuente tienen nombre para enseñar', () {
    for (final theme in ReadingTheme.values) {
      expect(theme.label, isNotEmpty);
    }
    for (final font in ReadingFont.values) {
      expect(font.label, isNotEmpty);
    }
  });
}
