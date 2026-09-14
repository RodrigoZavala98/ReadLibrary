import 'dart:convert';
import 'dart:typed_data';

/// Con qué codificación se acabó leyendo un fichero.
enum TextEncodingUsed {
  utf8Bom,
  utf8,
  utf16le,
  utf16be,

  /// El recurso de última hora. Ver [TextDecoding.decode].
  windows1252,
}

class DecodedText {
  const DecodedText(this.text, this.encoding);

  final String text;
  final TextEncodingUsed encoding;
}

/// Averigua con qué codificación está escrito un fichero de texto y lo decodifica.
///
/// Esto no es una florituras: es la diferencia entre que una novela en español
/// se lea bien o aparezca plagada de «Ã±» y «Â¿». Un `.txt` no declara en
/// ninguna parte su codificación, así que hay que deducirla.
///
/// El orden de intentos es deliberado:
///
///  1. **Marca de orden de bytes (BOM)**, si la hay. Es una declaración
///     explícita y no se discute.
///  2. **UTF-8 en modo estricto.** Es el estándar actual, y lo bueno de UTF-8
///     es que casi ningún texto en otra codificación pasa su validación: las
///     secuencias de continuación son demasiado específicas para aparecer por
///     azar. Si decodifica sin error, es UTF-8.
///  3. **Windows-1252.** Es lo que produce el Bloc de notas de Windows y buena
///     parte de los ficheros que circulan por ahí. Nunca falla —cualquier byte
///     es válido— así que va el último, como red de seguridad.
abstract final class TextDecoding {
  static DecodedText decode(Uint8List bytes) {
    if (bytes.isEmpty) return const DecodedText('', TextEncodingUsed.utf8);

    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
      return DecodedText(
        utf8.decode(bytes.sublist(3), allowMalformed: true),
        TextEncodingUsed.utf8Bom,
      );
    }
    if (_startsWith(bytes, const [0xFF, 0xFE])) {
      return DecodedText(
        _decodeUtf16(bytes, 2, littleEndian: true),
        TextEncodingUsed.utf16le,
      );
    }
    if (_startsWith(bytes, const [0xFE, 0xFF])) {
      return DecodedText(
        _decodeUtf16(bytes, 2, littleEndian: false),
        TextEncodingUsed.utf16be,
      );
    }

    try {
      // allowMalformed: false a propósito. Queremos que falle si no es UTF-8,
      // porque ese fallo es justamente la señal que nos hace probar cp1252.
      return DecodedText(
        const Utf8Decoder(allowMalformed: false).convert(bytes),
        TextEncodingUsed.utf8,
      );
    } on FormatException {
      return DecodedText(_decodeCp1252(bytes), TextEncodingUsed.windows1252);
    }
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _decodeUtf16(
    Uint8List bytes,
    int offset, {
    required bool littleEndian,
  }) {
    final units = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    // fromCharCodes recompone por su cuenta los pares suplentes.
    return String.fromCharCodes(units);
  }

  /// Windows-1252 coincide con Latin-1 salvo en el tramo 0x80–0x9F, donde
  /// Latin-1 tiene caracteres de control invisibles y cp1252 coloca los signos
  /// tipográficos que de verdad aparecen en los libros: comillas curvas, raya
  /// de diálogo y puntos suspensivos. Decodificar ese tramo como Latin-1
  /// convertiría las comillas de una novela en caracteres invisibles.
  static String _decodeCp1252(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0x9F) {
        buffer.writeCharCode(_cp1252High[byte - 0x80]);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }

  /// Tramo 0x80–0x9F de Windows-1252. 0xFFFD marca las posiciones que la
  /// codificación deja sin definir.
  static const _cp1252High = <int>[
    0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
    0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
  ];
}
