/// Compara nombres de fichero como los ordenaría una persona.
///
/// Es el corazón del formato CBZ, aunque no lo parezca. Un cómic comprimido
/// **no declara en ninguna parte el orden de sus páginas**: el orden es el
/// alfabético de los nombres de las entradas, y ahí está la trampa, porque el
/// alfabético a secas compara carácter a carácter y coloca `pagina10.jpg`
/// entre `pagina1.jpg` y `pagina2.jpg`. Un cómic de cien páginas ordenado así
/// se lee 1, 10, 11, …, 2, 20: barajado, y sin ningún error que lo delate.
///
/// La solución es trocear el nombre en tramos de dígitos y tramos de no
/// dígitos, y comparar los numéricos por su valor en lugar de por su texto.
int compareNatural(String a, String b) {
  final byValue = _compareTokens(a.toLowerCase(), b.toLowerCase());
  if (byValue != 0) return byValue;

  // Mismo nombre salvo mayúsculas, o dos números que valen lo mismo escritos
  // distinto (`07` y `7`). Desempata el texto original para que el orden sea
  // estable: dos páginas que se comparen «iguales» quedarían en el orden en
  // que las devolvió el ZIP, que no es el mismo en todas las máquinas.
  return a.compareTo(b);
}

int _compareTokens(String a, String b) {
  var i = 0;
  var j = 0;

  while (i < a.length && j < b.length) {
    final aDigit = _isDigit(a.codeUnitAt(i));
    final bDigit = _isDigit(b.codeUnitAt(j));

    if (aDigit && bDigit) {
      final aEnd = _endOfDigits(a, i);
      final bEnd = _endOfDigits(b, j);
      final order = _compareNumbers(
        a.substring(i, aEnd),
        b.substring(j, bEnd),
      );
      if (order != 0) return order;
      i = aEnd;
      j = bEnd;
      continue;
    }

    // Un número siempre va antes que una letra en la misma posición, para que
    // `2.jpg` preceda a `portada.jpg`.
    if (aDigit != bDigit) return aDigit ? -1 : 1;

    final order = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
    if (order != 0) return order;
    i++;
    j++;
  }

  // El que se acaba antes es prefijo del otro, y va primero.
  return (a.length - i).compareTo(b.length - j);
}

/// Compara dos tiras de dígitos por su valor.
///
/// Sin convertirlas a `int` a propósito: un nombre de fichero puede traer una
/// tira de treinta dígitos —hay quien numera las páginas con la fecha y un
/// identificador pegados— y `int.parse` desbordaría con una excepción en
/// mitad de la apertura del libro. Comparar la longitud sin ceros a la
/// izquierda, y sólo entonces el texto, da el mismo resultado para cualquier
/// tamaño.
int _compareNumbers(String a, String b) {
  final cleanA = _withoutLeadingZeros(a);
  final cleanB = _withoutLeadingZeros(b);
  if (cleanA.length != cleanB.length) {
    return cleanA.length.compareTo(cleanB.length);
  }
  return cleanA.compareTo(cleanB);
}

String _withoutLeadingZeros(String digits) {
  var start = 0;
  while (start < digits.length - 1 && digits.codeUnitAt(start) == 0x30) {
    start++;
  }
  return digits.substring(start);
}

int _endOfDigits(String text, int from) {
  var end = from;
  while (end < text.length && _isDigit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
