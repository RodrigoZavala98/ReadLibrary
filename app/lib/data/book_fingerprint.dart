import 'dart:io';
import 'dart:typed_data';

/// Huella de un fichero, para detectar que un libro ya está en la biblioteca.
///
/// No se lee el fichero entero: un cómic puede pesar cientos de megabytes y
/// recorrerlo completo al importar congelaría la interfaz. Se combinan el
/// **tamaño exacto** y un hash de los **primeros 256 KB**, que en la práctica
/// distingue cualquier par de libros reales.
///
/// No es criptográfico ni pretende serlo: aquí solo se trata de no duplicar
/// entradas cuando el usuario importa dos veces el mismo fichero.
abstract final class BookFingerprint {
  static const sampleBytes = 256 * 1024;

  static Future<String> ofFile(File file) async {
    final length = await file.length();

    final handle = await file.open();
    try {
      final sample = await handle.read(
        length < sampleBytes ? length : sampleBytes,
      );
      return '$length-${_fnv1a64(sample).toRadixString(16)}';
    } finally {
      await handle.close();
    }
  }

  /// FNV-1a de 64 bits.
  ///
  /// Se implementa aquí en lugar de traer una dependencia porque son seis
  /// líneas y, a diferencia del `hashCode` de Dart, da siempre el mismo
  /// resultado entre ejecuciones — imprescindible si el valor se guarda en
  /// disco y se compara más tarde.
  static int _fnv1a64(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      // El desbordamiento de los enteros de 64 bits es justo lo que pide el
      // algoritmo: equivale al módulo 2^64.
      hash *= 0x100000001b3;
    }
    return hash;
  }
}
