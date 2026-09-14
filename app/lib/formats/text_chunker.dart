/// Un fragmento de un texto largo.
///
/// Los desplazamientos son en caracteres sobre el texto completo, que es
/// exactamente la unidad que usa `CharLocator`. Así, restaurar la posición de
/// lectura no requiere ninguna conversión.
class TextChunk {
  const TextChunk({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;

  /// Primer carácter del fragmento, incluido.
  final int start;

  /// Primer carácter del fragmento siguiente, excluido.
  final int end;

  int get length => end - start;

  bool contains(int charOffset) => charOffset >= start && charOffset < end;

  String title() => 'Parte ${index + 1}';
}

/// Parte un texto largo en fragmentos manejables.
///
/// Un `.txt` puede ser un libro entero de varios megabytes. Entregárselo de una
/// pieza a un widget de texto obliga a Flutter a maquetar millones de
/// caracteres antes de pintar el primer píxel, y la aplicación se queda
/// congelada varios segundos.
///
/// Los cortes se hacen **siempre en un salto de párrafo**, nunca a mitad de
/// frase: el fragmento es una unidad de carga, pero el lector la percibe como
/// una página, y cortar por el medio de una palabra se nota.
abstract final class TextChunker {
  /// Tamaño al que se aspira. No es un máximo estricto: el corte se retrasa
  /// hasta el siguiente final de párrafo.
  static const defaultTargetChars = 20000;

  /// Por debajo de esta fracción del objetivo, el resto sobrante se pega al
  /// fragmento anterior en lugar de quedarse como un fragmento diminuto.
  static const _minTailFraction = 0.25;

  static List<TextChunk> split(
    String text, {
    int targetChars = defaultTargetChars,
  }) {
    assert(targetChars > 0);
    if (text.isEmpty) {
      return const [TextChunk(index: 0, start: 0, end: 0)];
    }

    final chunks = <TextChunk>[];
    var start = 0;
    while (start < text.length) {
      final target = start + targetChars;
      if (target >= text.length) {
        chunks.add(
          TextChunk(index: chunks.length, start: start, end: text.length),
        );
        break;
      }

      final cut = _paragraphBreakAtOrAfter(text, target);
      final end = cut ?? text.length;

      // Si lo que queda detrás es un resto minúsculo, se absorbe aquí y se
      // evita un fragmento de tres líneas al final del libro.
      final remaining = text.length - end;
      if (remaining > 0 && remaining < targetChars * _minTailFraction) {
        chunks.add(
          TextChunk(index: chunks.length, start: start, end: text.length),
        );
        break;
      }

      chunks.add(TextChunk(index: chunks.length, start: start, end: end));
      start = end;
    }

    return chunks;
  }

  /// Primer final de párrafo en [from] o después. `null` si ya no hay ninguno.
  ///
  /// Reconoce los tres finales de línea que circulan por ahí: `\n` de Unix,
  /// `\r\n` de Windows y `\r` suelto de los Mac antiguos, que todavía aparece
  /// en ficheros de bibliotecas digitales veteranas.
  static int? _paragraphBreakAtOrAfter(String text, int from) {
    for (var i = from; i < text.length - 1; i++) {
      final current = text.codeUnitAt(i);
      if (current != 0x0A && current != 0x0D) continue;

      // Se avanza sobre la secuencia completa de espacios en blanco verticales
      // y se comprueba si contiene al menos dos saltos: eso es un párrafo.
      var breaks = 0;
      var j = i;
      while (j < text.length) {
        final unit = text.codeUnitAt(j);
        if (unit == 0x0A) {
          breaks++;
        } else if (unit != 0x0D && unit != 0x20 && unit != 0x09) {
          break;
        }
        j++;
      }
      if (breaks >= 2) return j;
      i = j - 1;
    }
    return null;
  }

  /// A qué fragmento pertenece un desplazamiento.
  ///
  /// Devuelve el último fragmento si el desplazamiento se sale por el final,
  /// que puede pasar si el fichero se editó fuera de la aplicación.
  static int chunkIndexAt(List<TextChunk> chunks, int charOffset) {
    for (final chunk in chunks) {
      if (chunk.contains(charOffset)) return chunk.index;
    }
    return charOffset <= 0 ? 0 : chunks.length - 1;
  }
}
