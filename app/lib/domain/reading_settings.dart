/// Cómo quiere leer el usuario: tema, tipografía y medidas.
///
/// Vive en `domain/` y por tanto **no conoce Flutter**: los temas y las fuentes
/// son enumeraciones, no colores ni `TextStyle`. Los valores concretos —qué
/// crema exactamente, qué familia tipográfica— los pone `core/theme`, que sí es
/// interfaz. Así estos ajustes se guardan, se leen y se prueban sin pintar nada.
///
/// Son **globales, no por libro**. El comentario del antiguo `ReadingStyle`
/// decía lo contrario, «no se lee igual una novela que un manual», pero nunca
/// llegó a implementarse, y cumplirlo significa que cada libro nuevo se abre con
/// la tipografía de fábrica y hay que volver a ajustarla entera. Quien afina su
/// cuerpo de letra lo hace una vez.
library;

/// Las cuatro superficies de lectura.
///
/// [claro] y [sepia] existen porque leer texto blanco sobre negro cansa la
/// vista en sesiones largas; [oscuro] existe porque leer sobre crema a oscuras
/// deslumbra. [altoContraste] no es un capricho estético: es blanco puro sobre
/// negro puro, para quien necesita el máximo contraste posible. Ninguna de las
/// cuatro sobra.
enum ReadingTheme {
  claro(label: 'Claro'),
  sepia(label: 'Sepia'),
  oscuro(label: 'Oscuro'),
  altoContraste(label: 'Blanco y negro');

  const ReadingTheme({required this.label});

  /// Cómo se llama en la hoja de ajustes. Es texto, no interfaz, así que puede
  /// vivir aquí; los colores no.
  final String label;
}

/// Las tipografías que se pueden elegir.
///
/// [roboto], [serifDelSistema] y [monoespaciada] las pone Android y no ocupan
/// nada en el APK. [openSans] y [literata] van incrustadas.
enum ReadingFont {
  roboto(label: 'Roboto'),
  openSans(label: 'Open Sans'),
  literata(label: 'Literata'),
  serifDelSistema(label: 'Serif'),
  monoespaciada(label: 'Monoespaciada');

  const ReadingFont({required this.label});

  final String label;
}

class ReadingSettings {
  /// Los rangos se recortan **aquí**, no en la interfaz.
  ///
  /// El fichero de ajustes es un JSON en el disco del teléfono: puede llegar
  /// editado a mano, a medio escribir o de una versión futura. Dejar que un
  /// cuerpo de letra de cero o un interlineado negativo llegasen al lector
  /// haría ilegible el libro sin que el usuario supiera por qué ni cómo
  /// deshacerlo.
  ReadingSettings({
    this.theme = ReadingTheme.claro,
    this.font = ReadingFont.literata,
    double fontSize = 19,
    double lineHeight = 1.6,
    double margin = 24,
    double? brightness,
  }) : fontSize = _clamp(fontSize, minFontSize, maxFontSize),
       lineHeight = _clamp(lineHeight, minLineHeight, maxLineHeight),
       margin = _clamp(margin, minMargin, maxMargin),
       brightness = brightness == null ? null : _clamp(brightness, 0, 1);

  static const minFontSize = 14.0;
  static const maxFontSize = 28.0;
  static const minLineHeight = 1.2;
  static const maxLineHeight = 2.2;
  static const minMargin = 12.0;
  static const maxMargin = 48.0;

  final ReadingTheme theme;

  /// Por defecto Literata: es una serif diseñada para leer en pantalla, y el
  /// texto largo se lee mejor con serifa que con la sans del sistema.
  final ReadingFont font;

  final double fontSize;

  /// Múltiplo del tamaño de fuente, no píxeles absolutos.
  final double lineHeight;

  /// Margen horizontal en puntos lógicos.
  final double margin;

  /// Brillo de la pantalla dentro del libro, de 0 a 1.
  ///
  /// `null` significa **no tocar el del sistema**, que es distinto de cero: con
  /// cero la pantalla se apaga del todo. Es la diferencia entre «no opino» y
  /// «lo quiero al mínimo», y confundirlas dejaría al usuario a oscuras.
  final double? brightness;

  bool get usesSystemBrightness => brightness == null;

  ReadingSettings copyWith({
    ReadingTheme? theme,
    ReadingFont? font,
    double? fontSize,
    double? lineHeight,
    double? margin,
    double? brightness,
    bool useSystemBrightness = false,
  }) {
    return ReadingSettings(
      theme: theme ?? this.theme,
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      // Hace falta un parámetro aparte para volver al brillo del sistema: con
      // `null` no se distingue «devuélvelo al sistema» de «no lo cambies».
      brightness: useSystemBrightness ? null : (brightness ?? this.brightness),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingSettings &&
      other.theme == theme &&
      other.font == font &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.margin == margin &&
      other.brightness == brightness;

  @override
  int get hashCode =>
      Object.hash(theme, font, fontSize, lineHeight, margin, brightness);

  static double _clamp(double value, double min, double max) {
    if (value.isNaN) return min;
    return value.clamp(min, max);
  }
}
