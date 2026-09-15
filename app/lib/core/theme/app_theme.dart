import 'package:flutter/material.dart';

import '../../domain/reading_settings.dart';

/// El tema de la aplicación parte de una idea: **hay dos mundos**.
///
/// Alrededor de la lectura —biblioteca, estadísticas, ajustes— todo vive en un
/// índigo nocturno, denso, donde las portadas son lo único que tiene color. En
/// cuanto se abre un libro, la pantalla se convierte en papel: cálido, con
/// serifa y sin ningún elemento de interfaz a la vista.
///
/// Por eso hay dos paletas separadas en este fichero y no una sola. [ChromeTheme]
/// no es «el modo oscuro» de [ReadingSurface]: son dos cosas distintas que
/// conviven en la misma aplicación, y el usuario puede tener el lector en papel
/// claro mientras la biblioteca sigue en índigo.
abstract final class ChromeTheme {
  /// Fondo general.
  static const background = Color(0xFF16143A);

  /// Tarjetas y superficies elevadas.
  static const surface = Color(0xFF211E52);
  static const surfaceHigh = Color(0xFF2C2866);

  /// Ámbar cálido. Es el único color saturado del cromo, así que marca
  /// siempre la acción principal: continuar leyendo.
  static const accent = Color(0xFFF2793D);
  static const accentSoft = Color(0xFFFF9A62);

  static const textPrimary = Color(0xFFF3F1FF);
  static const textMuted = Color(0xFFA8A3C7);

  /// Degradado del botón principal y de los indicadores de racha.
  static const accentGradient = LinearGradient(
    colors: [accent, accentSoft],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: background,
        primary: accent,
        secondary: accentSoft,
        onPrimary: Color(0xFF2A1206),
        onSurface: textPrimary,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            bodySmall: base.textTheme.bodySmall?.copyWith(color: textMuted),
          ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}


/// Los colores de una superficie de lectura.
///
/// Es la mitad de interfaz de [ReadingTheme], que vive en el dominio y sólo
/// sabe cuántos temas hay y cómo se llaman. Los colores están aquí porque
/// `Color` es de Flutter y `domain/` no conoce Flutter.
class ReadingPalette {
  const ReadingPalette({
    required this.background,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color text;

  /// Para lo secundario: citas, notas al pie, el avance del margen.
  final Color muted;

  static ReadingPalette of(ReadingTheme theme) => switch (theme) {
    // Crema. Imita papel bajo luz de día.
    ReadingTheme.claro => const ReadingPalette(
      background: Color(0xFFF5EFE3),
      text: Color(0xFF23201B),
      muted: Color(0xFF6B6458),
    ),

    // Menos contraste, más cálido, para sesiones largas.
    ReadingTheme.sepia => const ReadingPalette(
      background: Color(0xFFEADBC0),
      text: Color(0xFF3A2E1E),
      muted: Color(0xFF7A6748),
    ),

    // Negro real —no gris— para que en pantallas OLED el texto flote.
    ReadingTheme.oscuro => const ReadingPalette(
      background: Color(0xFF0D0D0F),
      text: Color(0xFFD8D4CC),
      muted: Color(0xFF807C74),
    ),

    // Blanco y negro puros. No es una variante estética del claro: es el
    // máximo contraste que puede dar una pantalla, y para quien lo necesita
    // el crema del papel ya es insuficiente.
    ReadingTheme.altoContraste => const ReadingPalette(
      background: Color(0xFFFFFFFF),
      text: Color(0xFF000000),
      muted: Color(0xFF555555),
    ),
  };
}

/// Convierte los ajustes del usuario en tipografía y color.
///
/// Va como extensión para que el dominio siga sin saber de Flutter y la
/// interfaz siga escribiendo `settings.toTextStyle()`, que es lo natural donde
/// se usa.
extension ReadingSettingsStyle on ReadingSettings {
  ReadingPalette get palette => ReadingPalette.of(theme);

  /// La familia tipográfica que hay que pedirle a Flutter.
  ///
  /// Aquí estuvo un fallo que duró todo el proyecto: se pedía `'Georgia'`, que
  /// es una fuente de Microsoft y no existe en Android. Flutter no la
  /// encontraba y caía a la de por defecto, así que el modo «con serifa» nunca
  /// tuvo serifa. De ahí que la serif buena —Literata— vaya **incrustada** en
  /// el APK en lugar de pedírsela al sistema: una familia que no está no avisa,
  /// simplemente se ve distinta de lo que dice el código.
  String get fontFamily => switch (font) {
    ReadingFont.roboto => 'Roboto',
    ReadingFont.openSans => 'Open Sans',
    ReadingFont.literata => 'Literata',
    // Alias que Android resuelve a Noto Serif. Va como opción extra, nunca
    // como la serif principal, justamente porque depende del fabricante.
    ReadingFont.serifDelSistema => 'serif',
    ReadingFont.monoespaciada => 'monospace',
  };

  TextStyle toTextStyle() => TextStyle(
    fontSize: fontSize,
    height: lineHeight,
    color: palette.text,
    fontFamily: fontFamily,
  );
}
