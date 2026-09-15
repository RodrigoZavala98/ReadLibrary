import 'dart:io';
import 'dart:typed_data';

import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/book_source.dart';
import 'epub_archive.dart';
import 'epub_package.dart';
import 'file_naming.dart';

/// Lector de EPUB.
///
/// Es el formato que de verdad importa y el más enrevesado de los cuatro: un
/// ZIP con un índice XML dentro que apunta a una lista de documentos XHTML. La
/// complicación está repartida a propósito en tres piezas —[EpubArchive] para
/// el ZIP, [EpubPackage] para el índice y esta clase para la lectura— porque
/// cada una se puede probar por separado, y en este equipo las pruebas son la
/// única verificación posible.
class EpubBookSource implements ReflowableSource {
  EpubBookSource(this.file);

  final File file;

  EpubArchive? _archive;
  EpubPackage? _package;
  BookInfo? _info;

  /// Tamaño sin comprimir de cada documento del lomo, acumulado.
  ///
  /// `_cumulative[i]` es lo que pesa todo lo anterior al capítulo *i*. Es el
  /// reparto con el que se calcula el progreso, y sale del directorio central
  /// del ZIP: ni un byte descomprimido para saberlo.
  List<int> _cumulative = const [];
  int _totalSize = 0;

  @override
  BookFormat get format => BookFormat.epub;

  @override
  Future<void> open() async {
    if (_archive != null) return;

    if (!await file.exists()) {
      throw BookOpenException('El fichero ya no está en ${file.path}');
    }

    final archive = EpubArchive.openFile(file.path);
    final EpubPackage package;
    try {
      package = EpubPackage.parse(archive);
    } on Object {
      archive.close();
      rethrow;
    }

    final cumulative = <int>[];
    var total = 0;
    for (final document in package.spine) {
      cumulative.add(total);
      total += archive.sizeOf(document.href);
    }

    _archive = archive;
    _package = package;
    _cumulative = cumulative;
    _totalSize = total;
    _info = BookInfo(
      // Un EPUB sin `dc:title` es más común de lo que parece, sobre todo en los
      // convertidos desde otro formato.
      title: package.title ?? titleFromFileName(file.path),
      author: package.author,
    );
  }

  @override
  Future<void> dispose() async {
    _archive?.close();
    _archive = null;
    _package = null;
    _info = null;
    _cumulative = const [];
    _totalSize = 0;
  }

  @override
  BookInfo get info => _info ?? (throw StateError('Llama a open() primero'));

  @override
  BookLocator get startLocator => const EpubLocator(0, 0);

  @override
  List<ChapterRef> get chapters {
    final package = _package;
    if (package == null) throw StateError('Llama a open() primero');
    return [
      for (var i = 0; i < package.spine.length; i++)
        ChapterRef(
          title: package.spine[i].title,
          index: i,
          start: EpubLocator(i, 0),
        ),
    ];
  }

  @override
  Future<String> loadChapter(int chapterIndex) async {
    final archive = _archive;
    final package = _package;
    if (archive == null || package == null) {
      throw StateError('Llama a open() primero');
    }
    if (chapterIndex < 0 || chapterIndex >= package.spine.length) {
      throw RangeError.index(chapterIndex, package.spine, 'chapterIndex');
    }

    final href = package.spine[chapterIndex].href;
    // Un documento que el índice promete y el ZIP no tiene no debe tumbar el
    // libro: se enseña el hueco y se sigue leyendo por el siguiente capítulo.
    return archive.readString(href) ??
        '<p>Este capítulo falta dentro del EPUB.</p>';
  }

  @override
  int chapterIndexFor(BookLocator locator) {
    final package = _package;
    if (package == null) throw StateError('Llama a open() primero');
    if (locator is! EpubLocator) return 0;
    return locator.spineIndex.clamp(0, package.spine.length - 1);
  }

  @override
  double fractionWithin(int chapterIndex, BookLocator locator) {
    // Si el localizador es de otro capítulo —o de otro formato— se empieza por
    // arriba: es la respuesta correcta, no un caso de error.
    if (locator is! EpubLocator) return 0;
    return locator.spineIndex == chapterIndex ? locator.fraction : 0;
  }

  @override
  BookLocator locatorAt(int chapterIndex, double fraction) =>
      EpubLocator.atFraction(chapterIndex, fraction);

  @override
  double progressAt(BookLocator locator) {
    if (_totalSize <= 0 || locator is! EpubLocator) return 0;
    final index = chapterIndexFor(locator);
    final before = _cumulative[index];
    final size = _sizeOf(index);
    return ((before + size * locator.fraction) / _totalSize).clamp(0.0, 1.0);
  }

  /// Bytes de una imagen referenciada desde el capítulo [chapterIndex].
  ///
  /// El `src` de un `<img>` es relativo al documento que lo contiene, no a la
  /// carpeta del OPF: resolverlo contra el OPF funciona por casualidad en los
  /// EPUB que lo tienen todo junto y falla en los que separan `text/` de
  /// `images/`, que son la mayoría.
  Uint8List? imageBytes(int chapterIndex, String src) {
    final archive = _archive;
    final package = _package;
    if (archive == null || package == null) return null;
    if (chapterIndex < 0 || chapterIndex >= package.spine.length) return null;
    if (src.startsWith('data:') || src.contains('://')) return null;

    return archive.read(resolveHref(package.spine[chapterIndex].href, src));
  }

  int _sizeOf(int index) {
    final next = index + 1 < _cumulative.length
        ? _cumulative[index + 1]
        : _totalSize;
    return next - _cumulative[index];
  }
}
