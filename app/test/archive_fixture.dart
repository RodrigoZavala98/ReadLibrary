import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Fabrica archivos comprimidos para las pruebas.
///
/// Se construyen **en memoria** en lugar de guardar ficheros de ejemplo en el
/// repositorio. Dos razones: no se versiona ni un binario, y —la que de verdad
/// importa— se pueden fabricar a voluntad los archivos rotos, que son los casos
/// interesantes. Un EPUB sin índice o un cómic con las páginas mal numeradas no
/// se consiguen descargando; se construyen.
Uint8List zipOf(Map<String, Object> entries) {
  return Uint8List.fromList(ZipEncoder().encode(_archiveOf(entries)));
}

/// El mismo contenido, pero en un TAR: es lo que hay dentro de un `.cbt`.
Uint8List tarOf(Map<String, Object> entries) {
  return Uint8List.fromList(TarEncoder().encode(_archiveOf(entries)));
}

Archive _archiveOf(Map<String, Object> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.add(
      content is String
          ? ArchiveFile.string(name, content)
          : ArchiveFile.bytes(name, content as List<int>),
    );
  });
  return archive;
}

/// Un PNG de verdad, del tamaño que se pida.
///
/// Tiene que ser válido y no unos bytes cualesquiera: las pruebas de widget
/// pintan estas páginas con `Image.memory`, y un PNG inventado haría fallar al
/// decodificador con un error que no tendría nada que ver con lo que se está
/// probando. Se construye con el zlib de la plataforma y los CRC de verdad, en
/// lugar de pegar aquí una constante de sesenta bytes que nadie sabría revisar.
Uint8List pngBytes({int width = 1, int height = 1, int grey = 0}) {
  // Cada fila va precedida de su byte de filtro —0, «sin filtro»— y lleva tres
  // bytes por píxel, porque el tipo de color 2 es RGB sin transparencia.
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add([grey, grey, grey]);
    }
  }

  final header = BytesBuilder()
    ..add(_be32(width))
    ..add(_be32(height))
    ..add([8, 2, 0, 0, 0]);

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._chunk('IHDR', header.takeBytes()),
    ..._chunk('IDAT', zlib.encode(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ]);
}

/// Un trozo de PNG: longitud, tipo, datos y el CRC de los dos últimos.
List<int> _chunk(String type, List<int> data) {
  final typed = [...type.codeUnits, ...data];
  return [..._be32(data.length), ...typed, ..._be32(getCrc32(typed))];
}

List<int> _be32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];
