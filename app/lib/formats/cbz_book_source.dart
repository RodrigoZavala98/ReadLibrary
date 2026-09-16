import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/book_source.dart';
import 'file_naming.dart';
import 'natural_order.dart';

/// Lector de cómics comprimidos.
///
/// Un CBZ no es un formato: es un ZIP lleno de imágenes y una convención de
/// que se leen en orden alfabético. No hay manifiesto, ni índice, ni metadatos
/// obligatorios, así que todo lo que esta clase hace es decidir **qué entradas
/// son páginas y en qué orden van** — y ahí está todo el trabajo, porque los
/// ficheros reales vienen llenos de basura y mal ordenados. Ver
/// [compareNatural] y [_isPage].
///
/// La contrapartida de esa simplicidad es que no hay nada que pueda fallar a
/// medias: si el archivo abre y tiene imágenes, el cómic se lee entero.
class CbzBookSource implements FixedLayoutSource {
  CbzBookSource(this.file);

  final File file;

  /// El fichero abierto. Se conserva para poder cerrarlo: las entradas se
  /// descomprimen cuando se piden, así que el descriptor tiene que seguir vivo
  /// mientras se lea el cómic.
  InputFileStream? _input;

  List<ArchiveFile> _pages = const [];
  BookInfo? _info;
  bool _opened = false;

  @override
  BookFormat get format => BookFormat.cbz;

  @override
  int get pageCount => _pages.length;

  @override
  BookInfo get info => _info ?? (throw StateError('Llama a open() primero'));

  @override
  BookLocator get startLocator => const PageLocator(0);

  @override
  Future<void> open() async {
    if (_opened) return;

    if (!await file.exists()) {
      throw BookOpenException('El fichero ya no está en ${file.path}');
    }

    // El contenedor se decide por los bytes, no por la extensión. Un .cbz que
    // en realidad es un RAR es de los casos más habituales que circulan, y sin
    // esta comprobación el usuario recibiría «no se pudo descomprimir» cuando
    // lo que necesita oír es que convierta el fichero.
    final container = await _containerOf(file);

    final input = InputFileStream(file.path);
    final Archive archive;
    try {
      // Sólo se lee el directorio del archivo, no el contenido: un cómic puede
      // pesar trescientos megabytes y abrirlo entero en memoria dejaría sin
      // aire a la aplicación. Cada página se descomprime al pasarla.
      archive = switch (container) {
        _Container.zip => ZipDecoder().decodeStream(input),
        _Container.tar => TarDecoder().decodeStream(input),
      };
    } on Object catch (error) {
      await _close(input);
      throw BookOpenException(
        'Este cómic está dañado y no se pudo descomprimir.',
        cause: error,
      );
    }

    final pages = archive.files.where(_isPage).toList()
      ..sort((a, b) => compareNatural(a.name, b.name));

    if (pages.isEmpty) {
      await _close(input);
      throw const BookOpenException(
        'Este cómic no tiene ninguna imagen dentro, así que no hay nada que '
        'leer.',
      );
    }

    _input = input;
    _pages = pages;
    _opened = true;
    _info = BookInfo(
      title: titleFromFileName(file.path),
      // La portada se deja sin extraer a propósito. Sacarla obligaría a
      // descomprimir la primera página en cada apertura, y hoy no la pinta
      // nadie: LibraryBook.coverPath se guarda pero ninguna vista lo consume.
      // Cuando se hagan las portadas, la de un cómic es la página 0.
      totalPages: pages.length,
    );
  }

  @override
  Future<void> dispose() async {
    final input = _input;
    _input = null;
    _pages = const [];
    _info = null;
    _opened = false;
    if (input != null) await _close(input);
  }

  /// Los bytes de una página, tal y como venían dentro del archivo.
  ///
  /// [targetWidth] se **ignora**, y conviene entender por qué el parámetro
  /// existe igualmente: lo pide [FixedLayoutSource] para el PDF, que rasteriza
  /// una maqueta vectorial y necesita saber a qué resolución hacerlo. Una
  /// página de cómic ya es un mapa de bits; reescalarla aquí significaría
  /// decodificarla y volver a codificarla, gastando memoria y procesador para
  /// entregar algo peor. Quien la pinta la reduce al decodificarla, que es
  /// donde sale gratis.
  @override
  Future<Uint8List> renderPage(
    int pageIndex, {
    required int targetWidth,
  }) async {
    if (!_opened) throw StateError('Llama a open() primero');
    if (pageIndex < 0 || pageIndex >= _pages.length) {
      throw RangeError.index(pageIndex, _pages, 'pageIndex');
    }

    final bytes = _pages[pageIndex].readBytes();
    if (bytes == null) {
      throw BookOpenException(
        'La página ${pageIndex + 1} de este cómic está dañada.',
      );
    }
    return bytes;
  }

  @override
  double progressAt(BookLocator locator) {
    if (locator is! PageLocator) return 0;

    final last = _pages.length - 1;
    // Un cómic de una sola página está entero a la vista en cuanto se abre.
    // Dejarlo al 0 % sería el mismo error que marcar al cero por ciento un
    // texto corto que cabe en la pantalla sin desplazarse.
    if (last <= 0) return _pages.isEmpty ? 0 : 1;

    return (locator.pageIndex / last).clamp(0.0, 1.0);
  }

  Future<void> _close(InputFileStream input) async {
    // Cerrar no es cosmético: en Windows un archivo abierto impide hasta
    // borrar el fichero, y la biblioteca tiene que poder quitar un libro.
    try {
      await input.close();
    } on Object {
      // Ya estaba cerrado, o el fichero desapareció. No hay nada que hacer, y
      // desde luego no impedir que se cierre el cómic.
    }
  }

  /// Extensiones que Flutter sabe decodificar. Lo que no esté aquí no es una
  /// página aunque lo parezca.
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Si una entrada del archivo es una página del cómic.
  ///
  /// El filtro no es paranoia: los CBZ que circulan vienen con ComicInfo.xml,
  /// con Thumbs.db, con ficheros de créditos en texto y —constantemente— con
  /// la basura que deja macOS al comprimir. Un `__MACOSX/._pagina1.jpg` es un
  /// fork de recursos de unos pocos bytes, no una imagen: colarlo duplicaría
  /// cada página del cómic y la mitad saldrían rotas.
  static bool _isPage(ArchiveFile entry) {
    if (!entry.isFile) return false;

    // Una entrada vacía no puede ser una imagen, y sí puede ser el marcador de
    // carpeta que dejan algunos compresores.
    if (entry.size <= 0) return false;

    final segments = entry.name.split('/');
    if (segments.any((segment) => segment == '__MACOSX')) return false;

    final name = segments.last;
    if (name.startsWith('.')) return false;

    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false;
    return _imageExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Mira los primeros bytes para saber qué clase de archivo es.
  static Future<_Container> _containerOf(File file) async {
    final Uint8List head;
    try {
      // La cabecera de un TAR mide 512 bytes y hay que verla entera para
      // comprobar su suma de control.
      final handle = await file.open();
      try {
        head = await handle.read(_tarHeaderSize);
      } finally {
        await handle.close();
      }
    } on FileSystemException catch (error) {
      throw BookOpenException('No se pudo leer el cómic', cause: error);
    }

    if (_startsWith(head, _rarMagic) || _startsWith(head, _rar5Magic)) {
      throw const BookOpenException(
        'Este fichero se llama .cbz pero por dentro es un RAR, que es lo que '
        'hay en un CBR y no se puede descomprimir legalmente desde Dart. '
        'Conviértelo a CBZ de verdad y funcionará.',
      );
    }

    if (_startsWith(head, _zipMagic)) return _Container.zip;
    if (_looksLikeTar(head)) return _Container.tar;

    throw const BookOpenException(
      'Este fichero no es un cómic: no es ni un ZIP ni un TAR.',
    );
  }

  static const _zipMagic = [0x50, 0x4B];
  static const _rarMagic = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];
  static const _rar5Magic = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00];

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static const _tarHeaderSize = 512;

  /// Si la cabecera es la de un TAR, que es lo que hay dentro de un `.cbt`.
  ///
  /// Se comprueba la **suma de control** de la cabecera en lugar de buscar la
  /// marca «ustar» del desplazamiento 257, que sería lo evidente. El motivo es
  /// que esa marca la escriben las variantes POSIX y GNU, pero no el formato
  /// original: un tar v7 —el que produce, sin ir más lejos, el codificador del
  /// propio paquete `archive`— es un TAR perfectamente legítimo y no la lleva.
  /// La suma de control, en cambio, la tienen las tres.
  ///
  /// Que un fichero cualquiera la cumpla por casualidad es inverosímil: exige
  /// que ocho bytes en octal coincidan con la suma de los otros quinientos.
  static bool _looksLikeTar(Uint8List bytes) {
    if (bytes.length < _tarHeaderSize) return false;

    // El campo ocupa los bytes 148 a 155, en octal y terminado en nulo o
    // espacio.
    final declared = _parseOctal(bytes, 148, 8);
    if (declared == null) return false;

    var sum = 0;
    for (var i = 0; i < _tarHeaderSize; i++) {
      // Al calcularla, el propio campo de la suma se cuenta como ocho
      // espacios; si no, no habría forma de escribirla dentro de la cabecera
      // que ella misma resume.
      sum += (i >= 148 && i < 156) ? 0x20 : bytes[i];
    }
    return sum == declared;
  }

  static int? _parseOctal(Uint8List bytes, int start, int length) {
    var value = 0;
    var digits = 0;
    for (var i = start; i < start + length; i++) {
      final byte = bytes[i];
      if (byte == 0x00 || byte == 0x20) {
        // Los espacios y nulos del principio se saltan; los del final cierran
        // el número.
        if (digits > 0) break;
        continue;
      }
      if (byte < 0x30 || byte > 0x37) return null;
      value = value * 8 + (byte - 0x30);
      digits++;
    }
    return digits == 0 ? null : value;
  }
}

enum _Container { zip, tar }
