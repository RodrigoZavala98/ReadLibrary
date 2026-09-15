import 'package:flutter_test/flutter_test.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/reading_settings.dart';

void main() {
  group('paletas de lectura', () {
    test('los cuatro temas se distinguen entre sí', () {
      final fondos = {
        for (final theme in ReadingTheme.values)
          ReadingPalette.of(theme).background,
      };
      expect(fondos.length, ReadingTheme.values.length);
    });

    test('ningún tema deja el texto del color del fondo', () {
      for (final theme in ReadingTheme.values) {
        final palette = ReadingPalette.of(theme);
        expect(
          palette.text,
          isNot(palette.background),
          reason: 'el tema ${theme.label} sería ilegible',
        );
      }
    });

    test('el tema de alto contraste es blanco y negro puros', () {
      // Es su razón de ser: no es un claro más bonito, es el máximo contraste
      // que puede dar la pantalla.
      final palette = ReadingPalette.of(ReadingTheme.altoContraste);
      expect(palette.background.toARGB32(), 0xFFFFFFFF);
      expect(palette.text.toARGB32(), 0xFF000000);
    });

    test('el oscuro es más oscuro que el claro', () {
      expect(
        ReadingPalette.of(ReadingTheme.oscuro).background.computeLuminance(),
        lessThan(
          ReadingPalette.of(ReadingTheme.claro).background.computeLuminance(),
        ),
      );
    });
  });

  group('tipografías', () {
    test('cada fuente pide la familia que le toca', () {
      String familyOf(ReadingFont font) =>
          ReadingSettings(font: font).fontFamily;

      expect(familyOf(ReadingFont.roboto), 'Roboto');
      expect(familyOf(ReadingFont.openSans), 'Open Sans');
      expect(familyOf(ReadingFont.literata), 'Literata');
      expect(familyOf(ReadingFont.serifDelSistema), 'serif');
      expect(familyOf(ReadingFont.monoespaciada), 'monospace');
    });

    test('ninguna pide Georgia', () {
      // La regresión del fallo que duró todo el proyecto: Georgia es una fuente
      // de Microsoft, no existe en Android, y Flutter caía en silencio a la de
      // por defecto. El modo «con serifa» nunca tuvo serifa.
      for (final font in ReadingFont.values) {
        expect(ReadingSettings(font: font).fontFamily, isNot('Georgia'));
      }
    });

    test('las dos familias incrustadas se piden por su nombre declarado', () {
      // Tienen que coincidir exactamente con el `family:` del pubspec, o Flutter
      // no las encuentra y vuelve a caer a la de por defecto sin avisar.
      expect(
        ReadingSettings(font: ReadingFont.literata).fontFamily,
        'Literata',
      );
      expect(
        ReadingSettings(font: ReadingFont.openSans).fontFamily,
        'Open Sans',
      );
    });
  });

  group('el estilo de texto sale de los ajustes', () {
    test('lleva el tamaño, el interlineado y el color del tema', () {
      final style = ReadingSettings(
        theme: ReadingTheme.oscuro,
        fontSize: 22,
        lineHeight: 1.8,
      ).toTextStyle();

      expect(style.fontSize, 22);
      expect(style.height, 1.8);
      expect(style.color, ReadingPalette.of(ReadingTheme.oscuro).text);
    });

    test('cambiar de tema cambia el color del texto', () {
      expect(
        ReadingSettings(theme: ReadingTheme.claro).toTextStyle().color,
        isNot(ReadingSettings(theme: ReadingTheme.oscuro).toTextStyle().color),
      );
    });
  });
}
