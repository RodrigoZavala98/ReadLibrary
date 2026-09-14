/// Formatos que la aplicación sabe abrir.
///
/// El alcance de la v1 es EPUB, TXT, PDF y CBZ. FB2, CBR y RTF quedan
/// declarados aquí para que el resto del código ya los contemple, pero
/// [BookFormat.isSupported] los marca como no disponibles:
///
///  - CBR es un contenedor RAR y no existe descompresor en Dart puro; la
///    licencia de unrar prohíbe reimplementar el algoritmo.
///  - RTF no tiene ningún analizador mantenido en el ecosistema Dart.
///  - FB2 sí es viable (XML), pero el paquete fb2_parse lleva cinco años sin
///    mantenerse, así que habrá que escribir el analizador a mano.
enum BookFormat {
  epub(extensions: {'epub'}, isSupported: true),
  txt(extensions: {'txt', 'md'}, isSupported: true),
  pdf(extensions: {'pdf'}, isSupported: true),
  cbz(extensions: {'cbz', 'cbt'}, isSupported: true),

  fb2(extensions: {'fb2'}, isSupported: false),
  cbr(extensions: {'cbr'}, isSupported: false),
  rtf(extensions: {'rtf'}, isSupported: false);

  const BookFormat({required this.extensions, required this.isSupported});

  /// Extensiones de fichero, en minúscula y sin el punto.
  final Set<String> extensions;

  /// Si es `false`, la biblioteca muestra el libro en gris y explica por qué
  /// en lugar de fallar al abrirlo.
  final bool isSupported;

  /// Cómo se recorre el contenido. Determina qué interfaz de lectura se usa.
  LayoutKind get layout => switch (this) {
    BookFormat.epub || BookFormat.txt || BookFormat.fb2 || BookFormat.rtf =>
      LayoutKind.reflowable,
    BookFormat.pdf || BookFormat.cbz || BookFormat.cbr => LayoutKind.fixed,
  };

  /// Deduce el formato por la extensión del nombre de fichero.
  ///
  /// Devuelve `null` si la extensión no corresponde a ningún formato conocido.
  /// Es una heurística: la confirmación real se hace leyendo los primeros
  /// bytes al abrir el fichero, porque la extensión miente con frecuencia
  /// (un .cbz que en realidad es RAR es un caso muy habitual).
  static BookFormat? fromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    for (final format in BookFormat.values) {
      if (format.extensions.contains(ext)) return format;
    }
    return null;
  }
}

/// Cómo se organiza el contenido de un libro.
enum LayoutKind {
  /// El texto se re-maqueta según el tamaño de fuente y la pantalla, así que
  /// el concepto de "página" no es estable: cambiar el cuerpo de letra cambia
  /// el número total de páginas. EPUB, TXT, FB2.
  reflowable,

  /// Las páginas son imágenes o maquetas inmutables. El número de página sí
  /// es estable y significa lo mismo en cualquier dispositivo. PDF, CBZ.
  fixed,
}
