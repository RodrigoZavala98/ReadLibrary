import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/formats/text_decoding.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('un fichero vacío no revienta', () {
    final r = TextDecoding.decode(bytes([]));
    expect(r.text, '');
  });

  group('UTF-8', () {
    test('lee acentos y eñes', () {
      // "canción" en UTF-8.
      final r = TextDecoding.decode(
        bytes([0x63, 0x61, 0x6E, 0x63, 0x69, 0xC3, 0xB3, 0x6E]),
      );
      expect(r.text, 'canción');
      expect(r.encoding, TextEncodingUsed.utf8);
    });

    test('la marca de orden de bytes no aparece en el texto', () {
      final r = TextDecoding.decode(bytes([0xEF, 0xBB, 0xBF, 0x68, 0x69]));
      expect(r.text, 'hi', reason: 'el BOM se descarta, no se lee');
      expect(r.encoding, TextEncodingUsed.utf8Bom);
    });

    test('emoji y caracteres fuera del plano básico', () {
      // U+1F4D6 📖
      final r = TextDecoding.decode(bytes([0xF0, 0x9F, 0x93, 0x96]));
      expect(r.text, '📖');
    });
  });

  group('UTF-16', () {
    test('little endian', () {
      final r = TextDecoding.decode(bytes([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]));
      expect(r.text, 'hi');
      expect(r.encoding, TextEncodingUsed.utf16le);
    });

    test('big endian', () {
      final r = TextDecoding.decode(bytes([0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]));
      expect(r.text, 'hi');
      expect(r.encoding, TextEncodingUsed.utf16be);
    });
  });

  group('Windows-1252, el caso del Bloc de notas', () {
    test('un texto en español que no es UTF-8 válido se rescata', () {
      // "canción" en cp1252: la ó es un único byte 0xF3, que en UTF-8 sería el
      // arranque de una secuencia de cuatro bytes y aquí no lo es.
      final r = TextDecoding.decode(
        bytes([0x63, 0x61, 0x6E, 0x63, 0x69, 0xF3, 0x6E]),
      );
      expect(r.text, 'canción');
      expect(r.encoding, TextEncodingUsed.windows1252);
    });

    test('el tramo alto trae los signos tipográficos de verdad', () {
      // 0x93/0x94 son comillas curvas y 0x97 la raya de diálogo. En Latin-1
      // los tres serían caracteres de control invisibles.
      final r = TextDecoding.decode(bytes([0x93, 0x41, 0x94, 0x20, 0x97]));
      expect(r.text, '“A” —');
      expect(r.encoding, TextEncodingUsed.windows1252);
    });

    test('conserva los acentos del tramo Latin-1', () {
      // á é í ó ú ñ ¿ ¡
      final r = TextDecoding.decode(
        bytes([0xE1, 0xE9, 0xED, 0xF3, 0xFA, 0xF1, 0xBF, 0xA1]),
      );
      expect(r.text, 'áéíóúñ¿¡');
    });
  });

  test('un texto ASCII puro se considera UTF-8, no cp1252', () {
    final r = TextDecoding.decode(bytes('Hola mundo'.codeUnits));
    expect(r.text, 'Hola mundo');
    expect(r.encoding, TextEncodingUsed.utf8);
  });
}
