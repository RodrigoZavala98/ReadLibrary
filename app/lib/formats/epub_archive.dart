import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

import '../domain/book_source.dart';

/// Resuelve [href] —escrito dentro del documento [from] y relativo a él, como
/// manda HTML— a una ruta relativa a la carpeta del OPF.
///
/// Lo usan tanto el índice, cuyos enlaces son relativos al propio índice, como
/// las imágenes de un capítulo, que son relativas al capítulo. Resolverlas
/// contra la carpeta del OPF —el error fácil— funciona sólo en los EPUB que lo
/// tienen todo en la misma carpeta.
String resolveHref(String from, String href) {
  final target = withoutFragment(decodeHref(href));
  if (target.startsWith('/')) return target.substring(1);
  final slash = from.lastIndexOf('/');
  final base = slash == -1 ? '' : from.substring(0, slash + 1);
  return collapseDots('$base$target');
}

/// Quita el `#ancla` de un href.
String withoutFragment(String href) {
  final hash = href.indexOf('#');
  return hash == -1 ? href : href.substring(0, hash);
}

/// Las rutas dentro de un EPUB van escapadas como URL: un capítulo llamado
/// «El día 1.xhtml» aparece como `El%20d%C3%ADa%201.xhtml`, y sin deshacerlo no
/// se encuentra la entrada en el ZIP.
String decodeHref(String href) {
  try {
    return Uri.decodeFull(href);
  } on FormatException {
    return href;
  }
}

/// Resuelve los `..` y los `.` de una ruta.
///
/// Hacen falta de verdad: un EPUB con los capítulos en `OEBPS/text/` y las
/// imágenes en `OEBPS/images/` referencia `../images/foto.jpg`.
String collapseDots(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

/// El ZIP de un EPUB y su contenedor, sin nada del formato todavía.
///
/// Un EPUB es un ZIP con una convención encima: `META-INF/container.xml` dice
/// dónde está el fichero de paquete (el OPF), y todo lo demás cuelga de ahí con
/// rutas relativas. Esta clase resuelve exactamente eso y nada más, para poder
/// probarla contra ZIPs construidos en memoria sin arrastrar el resto.
class EpubArchive {
  EpubArchive._(this._archive, this.opfPath, this._input);

  final Archive _archive;

  /// El fichero abierto, cuando se abrió desde disco. Se conserva para poder
  /// cerrarlo: `decodeStream` descomprime cada entrada cuando se le pide, así
  /// que el descriptor tiene que seguir vivo mientras se lea el libro.
  final InputFileStream? _input;

  /// Ruta del OPF dentro del ZIP, tal y como la declara el contenedor.
  final String opfPath;

  /// Carpeta del OPF. Las rutas del manifiesto son relativas a ella, no a la
  /// raíz del ZIP, y es un error clásico saltárselo: en los EPUB que meten todo
  /// dentro de `OEBPS/` funcionaría igual por casualidad, y en los que no,
  /// nada cargaría.
  String get opfDir {
    final slash = opfPath.lastIndexOf('/');
    return slash == -1 ? '' : opfPath.substring(0, slash + 1);
  }

  /// Abre un EPUB desde disco sin cargarlo entero en memoria.
  ///
  /// Un cómic o un libro muy ilustrado pueden pesar decenas de megabytes, y
  /// sólo hace falta el directorio central del ZIP para empezar.
  static EpubArchive openFile(String path) {
    final input = InputFileStream(path);
    try {
      return _decode(ZipDecoder().decodeStream(input), input);
    } on BookOpenException {
      input.closeSync();
      rethrow;
    } on Object catch (error) {
      input.closeSync();
      throw BookOpenException(
        'Este fichero no es un EPUB: no se pudo descomprimir.',
        cause: error,
      );
    }
  }

  /// Cierra el fichero. Después de esto no se puede leer nada más.
  void close() => _input?.closeSync();

  /// Abre un EPUB a partir de los bytes del fichero.
  ///
  /// Lanza [BookOpenException] con una explicación en cualquier caso que no sea
  /// un EPUB legible. La extensión miente con frecuencia, así que aquí es donde
  /// se comprueba de verdad qué había dentro.
  static EpubArchive open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw BookOpenException(
        'Este fichero no es un EPUB: no se pudo descomprimir.',
        cause: error,
      );
    }
    return _decode(archive, null);
  }

  static EpubArchive _decode(Archive archive, InputFileStream? input) {
    // Un fichero que no es un ZIP no hace fallar al descompresor: devuelve un
    // archivo vacío. Sin esta comprobación, quien abre un fichero corrupto o
    // renombrado leería que «le falta el container.xml», que no le dice nada.
    if (archive.isEmpty) {
      throw const BookOpenException(
        'Este fichero no es un EPUB: no hay nada dentro que se pueda abrir.',
      );
    }

    final container = archive.findFile('META-INF/container.xml');
    if (container == null) {
      throw const BookOpenException(
        'Este EPUB no trae META-INF/container.xml, así que no hay forma de '
        'saber por dónde empieza.',
      );
    }

    final opfPath = _rootfilePath(_utf8OrThrow(container));
    if (archive.findFile(opfPath) == null) {
      throw BookOpenException(
        'El EPUB dice que su índice está en «$opfPath», pero ahí no hay nada.',
      );
    }

    final epub = EpubArchive._(archive, opfPath, input);
    epub._rejectIfEncrypted();
    return epub;
  }

  /// Bytes de una entrada, o `null` si no está.
  ///
  /// [path] se interpreta relativo a la carpeta del OPF salvo que empiece por
  /// `/`, que en un EPUB significa la raíz del ZIP.
  Uint8List? read(String path) {
    final entry = _archive.findFile(_resolve(path));
    if (entry == null || !entry.isFile) return null;
    return entry.readBytes();
  }

  /// Texto de una entrada, decodificado como UTF-8.
  ///
  /// UTF-8 sin alternativa porque la especificación de EPUB lo exige para el
  /// OPF y los documentos de contenido. `allowMalformed` evita que un fichero
  /// con un byte suelto mal codificado —que los hay— tire el libro entero; se
  /// verá un rombo en una letra en lugar de una pantalla de error.
  String? readString(String path) {
    final bytes = read(path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Tamaño sin comprimir de una entrada, o 0 si no está.
  ///
  /// Sale del directorio central del ZIP, así que no descomprime nada: es lo
  /// que permite repartir el progreso entre capítulos sin abrir ninguno.
  int sizeOf(String path) => _archive.findFile(_resolve(path))?.size ?? 0;

  bool contains(String path) => _archive.findFile(_resolve(path)) != null;

  String _resolve(String path) {
    if (path.startsWith('/')) return collapseDots(path.substring(1));
    return collapseDots('$opfDir$path');
  }

  /// Un EPUB con DRM no se puede leer, y hay que decirlo en lugar de enseñar
  /// caracteres sin sentido.
  ///
  /// Que exista `encryption.xml` no basta para rechazarlo: el mismo fichero se
  /// usa para la **ofuscación de tipografías**, que es un mecanismo legítimo y
  /// frecuente del propio estándar. Eso no estorba, porque las fuentes
  /// embebidas no se usan: la tipografía la pone el lector.
  void _rejectIfEncrypted() {
    final encryption = _archive.findFile('META-INF/encryption.xml');
    if (encryption == null) return;

    final XmlDocument document;
    try {
      document = XmlDocument.parse(_utf8OrThrow(encryption));
    } on XmlException {
      // Ilegible pero presente: no se puede saber qué cifra. Se deja pasar y
      // que falle más adelante el capítulo concreto, si es que falla.
      return;
    }

    for (final reference in document.findAllElements(
      'CipherReference',
      namespaceUri: '*',
    )) {
      final target = reference.getAttribute('URI');
      if (target == null) continue;
      if (_isFont(target)) continue;
      throw const BookOpenException(
        'Este EPUB está protegido con DRM y no se puede abrir. Los libros con '
        'DRM solo se leen en la aplicación de la tienda donde se compraron.',
      );
    }
  }

  static bool _isFont(String path) {
    final clean = path.toLowerCase().split('?').first;
    return clean.endsWith('.ttf') ||
        clean.endsWith('.otf') ||
        clean.endsWith('.woff') ||
        clean.endsWith('.woff2');
  }

  static String _utf8OrThrow(ArchiveFile file) {
    final bytes = file.readBytes();
    if (bytes == null) {
      throw BookOpenException('No se pudo leer «${file.name}» del EPUB.');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Saca del contenedor la ruta del primer `rootfile`.
  ///
  /// Un EPUB puede declarar varias representaciones del mismo libro; se coge la
  /// primera, que es lo que hacen todos los lectores.
  static String _rootfilePath(String containerXml) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(containerXml);
    } on XmlException catch (error) {
      throw BookOpenException(
        'El container.xml de este EPUB está mal formado.',
        cause: error,
      );
    }

    // Se busca ignorando el espacio de nombres: la mitad de los EPUB que
    // circulan lo declaran de formas distintas, y algunos ni lo declaran.
    for (final rootfile in document.findAllElements(
      'rootfile',
      namespaceUri: '*',
    )) {
      final path = rootfile.getAttribute('full-path');
      if (path != null && path.trim().isNotEmpty) {
        return collapseDots(path.trim());
      }
    }

    throw const BookOpenException(
      'El container.xml de este EPUB no dice dónde está el índice.',
    );
  }
}
