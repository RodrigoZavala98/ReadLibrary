import 'package:flutter/material.dart';

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

/// Las tres superficies de lectura posibles.
///
/// Papel y sepia existen porque leer texto blanco sobre negro cansa la vista en
/// sesiones largas; noche existe porque leer blanco sobre crema a oscuras
/// deslumbra. Ninguna de las tres es prescindible.
enum ReadingSurface {
  /// Crema. Imita papel bajo luz de día.
  paper(
    background: Color(0xFFF5EFE3),
    text: Color(0xFF23201B),
    muted: Color(0xFF6B6458),
  ),

  /// Sepia. Menos contraste, más cálido, para sesiones largas.
  sepia(
    background: Color(0xFFEADBC0),
    text: Color(0xFF3A2E1E),
    muted: Color(0xFF7A6748),
  ),

  /// Noche. Negro real —no gris— para que en pantallas OLED el texto flote.
  night(
    background: Color(0xFF0D0D0F),
    text: Color(0xFFD8D4CC),
    muted: Color(0xFF807C74),
  );

  const ReadingSurface({
    required this.background,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color text;
  final Color muted;
}

/// Ajustes tipográficos del lector, los que el usuario controla desde la
/// píldora flotante.
class ReadingStyle {
  const ReadingStyle({
    this.surface = ReadingSurface.paper,
    this.fontSize = 19,
    this.lineHeight = 1.6,
    this.serif = true,
    this.margin = 24,
  });

  final ReadingSurface surface;
  final double fontSize;

  /// Múltiplo del tamaño de fuente, no píxeles absolutos.
  final double lineHeight;

  /// Con serifa para narrativa, sin ella para documentación técnica. La
  /// preferencia se guarda por libro, no global: no se lee igual una novela
  /// que un manual.
  final bool serif;

  /// Margen horizontal en puntos lógicos.
  final double margin;

  TextStyle toTextStyle() => TextStyle(
    fontSize: fontSize,
    height: lineHeight,
    color: surface.text,
    fontFamily: serif ? 'Georgia' : null,
  );

  ReadingStyle copyWith({
    ReadingSurface? surface,
    double? fontSize,
    double? lineHeight,
    bool? serif,
    double? margin,
  }) {
    return ReadingStyle(
      surface: surface ?? this.surface,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      serif: serif ?? this.serif,
      margin: margin ?? this.margin,
    );
  }
}
