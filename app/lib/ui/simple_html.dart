/// Extrae los párrafos del HTML mínimo que genera el lector de TXT.
///
/// Deliberadamente **no** es un analizador de HTML. Entiende exactamente el
/// subconjunto que produce `TxtBookSource` —una sucesión de `<p>` con las
/// entidades básicas escapadas— y nada más.
///
/// La alternativa era traer un paquete de renderizado de HTML, y se descartó a
/// propósito: en un lector, la tipografía es el producto. Pintar los párrafos
/// con widgets propios da control exacto sobre interlineado, sangrías y saltos,
/// que es justo lo que un renderizador genérico no permite afinar.
///
/// Cuando llegue EPUB hará falta algo de verdad, porque ahí el HTML es
/// arbitrario y viene con estilos, tablas e imágenes. Esto es el puente hasta
/// entonces.
abstract final class SimpleHtml {
  static final _paragraph = RegExp(r'<p>(.*?)</p>', dotAll: true);

  static List<String> toParagraphs(String html) {
    final result = <String>[];
    for (final match in _paragraph.allMatches(html)) {
      final text = unescape(match.group(1) ?? '').trim();
      if (text.isNotEmpty) result.add(text);
    }

    // Si no hay ni una etiqueta, se trata el contenido como texto suelto en
    // lugar de devolver una pantalla en blanco.
    if (result.isEmpty) {
      final plain = unescape(html).trim();
      if (plain.isNotEmpty) result.add(plain);
    }
    return result;
  }

  /// Deshace el escapado. El orden importa: `&amp;` va el último, porque si se
  /// sustituyera primero convertiría `&amp;lt;` —un «&lt;» literal escapado dos
  /// veces— en un «<» real.
  static String unescape(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
