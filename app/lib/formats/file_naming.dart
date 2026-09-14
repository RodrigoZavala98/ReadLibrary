/// Deduce un título legible a partir del nombre de un fichero.
///
/// Los libros que circulan por Internet llegan con nombres como
/// `El_nombre_del_viento.epub` o `dune - frank herbert.txt`. Es lo único que
/// hay cuando el fichero no trae metadatos, así que conviene dejarlo presentable.
String titleFromFileName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  final bare = dot > 0 ? name.substring(0, dot) : name;

  return bare
      .replaceAll(RegExp(r'[_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Un nombre de fichero seguro para guardar en disco.
///
/// El nombre original lo eligió alguien ajeno a la aplicación y puede contener
/// cualquier cosa: separadores de ruta, `..`, caracteres prohibidos en Windows
/// o rutas absolutas. Sin sanear, un fichero llamado `../../datos.db` escribiría
/// fuera de la carpeta de la biblioteca.
String safeFileName(String original, {int maxLength = 80}) {
  final name = original.split(RegExp(r'[/\\]')).last;

  // Caracteres que Windows prohíbe, más los de control.
  var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

  // Un nombre formado solo por puntos apuntaría al directorio actual o al padre.
  clean = clean.replaceAll(RegExp(r'^\.+'), '');
  clean = clean.trim();

  if (clean.isEmpty) clean = 'libro';
  if (clean.length > maxLength) {
    final dot = clean.lastIndexOf('.');
    if (dot > 0 && clean.length - dot <= 6) {
      final ext = clean.substring(dot);
      clean = clean.substring(0, maxLength - ext.length) + ext;
    } else {
      clean = clean.substring(0, maxLength);
    }
  }
  return clean;
}
