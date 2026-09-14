import 'dart:io';

import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/book_source.dart';
import 'file_naming.dart';
import 'text_chunker.dart';
import 'text_decoding.dart';

/// Lector de ficheros de texto plano.
///
/// Es el formato más simple de los cuatro y por eso es el primero: sirve para
/// validar de punta a punta el circuito completo —abrir, fragmentar, restaurar
/// la posición— sin pelearse todavía con ZIPs ni con PDFium.
class TxtBookSource implements ReflowableSource {
  TxtBookSource(this.file, {this.targetChars = TextChunker.defaultTargetChars});

  final File file;
  final int targetChars;

  String? _text;
  List<TextChunk>? _chunks;
  BookInfo? _info;
  TextEncodingUsed? _encoding;

  /// Con qué codificación se leyó. Útil para mostrarlo en los detalles del
  /// libro cuando el texto salga raro y el usuario quiera entender por qué.
  TextEncodingUsed? get encoding => _encoding;

  /// Longitud total en caracteres. Es el denominador del progreso y el final
  /// del último fragmento.
  int get totalChars => _text?.length ?? 0;

  /// Rango de caracteres que abarca un fragmento.
  (int start, int end) chunkRange(int index) {
    final chunks = _chunks;
    if (chunks == null) throw StateError('Llama a open() primero');
    final chunk = chunks[index];
    return (chunk.start, chunk.end);
  }

  @override
  BookFormat get format => BookFormat.txt;

  @override
  Future<void> open() async {
    if (_text != null) return;

    if (!await file.exists()) {
      throw BookOpenException('El fichero ya no está en ${file.path}');
    }

    try {
      final decoded = TextDecoding.decode(await file.readAsBytes());
      _text = decoded.text;
      _encoding = decoded.encoding;
    } on FileSystemException catch (error) {
      throw BookOpenException('No se pudo leer el fichero', cause: error);
    }

    _chunks = TextChunker.split(_text!, targetChars: targetChars);
    _info = BookInfo(title: titleFromFileName(file.path));
  }

  @override
  Future<void> dispose() async {
    // El texto puede ocupar varios megabytes; conviene soltarlo al cerrar.
    _text = null;
    _chunks = null;
  }

  @override
  BookInfo get info => _info ?? (throw StateError('Llama a open() primero'));

  @override
  BookLocator get startLocator => const CharLocator(0);

  @override
  double progressAt(BookLocator locator) {
    final text = _text;
    if (text == null || text.isEmpty) return 0;
    if (locator is! CharLocator) return 0;
    return (locator.charOffset / text.length).clamp(0.0, 1.0);
  }

  @override
  List<ChapterRef> get chapters {
    final chunks = _chunks;
    if (chunks == null) throw StateError('Llama a open() primero');
    return [
      for (final chunk in chunks)
        ChapterRef(
          title: chunk.title(),
          index: chunk.index,
          start: CharLocator(chunk.start),
        ),
    ];
  }

  @override
  Future<String> loadChapter(int chapterIndex) async {
    final text = _text;
    final chunks = _chunks;
    if (text == null || chunks == null) {
      throw StateError('Llama a open() primero');
    }
    if (chapterIndex < 0 || chapterIndex >= chunks.length) {
      throw RangeError.index(chapterIndex, chunks, 'chapterIndex');
    }

    final chunk = chunks[chapterIndex];
    return _toHtml(text.substring(chunk.start, chunk.end));
  }

  /// Qué fragmento hay que cargar para mostrar una posición dada.
  int chunkIndexFor(BookLocator locator) {
    final chunks = _chunks;
    if (chunks == null) throw StateError('Llama a open() primero');
    final offset = locator is CharLocator ? locator.charOffset : 0;
    return TextChunker.chunkIndexAt(chunks, offset);
  }

  /// Convierte texto plano en HTML mínimo.
  ///
  /// Se devuelve HTML —y no el texto tal cual— para que TXT, EPUB y FB2
  /// compartan un único camino de renderizado: una sola implementación de
  /// tipografía, márgenes y temas, en lugar de una por formato.
  static String _toHtml(String plain) {
    final paragraphs = plain
        .split(RegExp(r'(?:\r\n|\r|\n)\s*(?:\r\n|\r|\n)'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    return paragraphs.map((p) => '<p>${_escape(p)}</p>').join();
  }

  /// Un `.txt` es texto plano, pero puede contener `<`, `>` o `&` como
  /// caracteres literales. Sin escapar, un diálogo como `<<¿vienes?>>` o una
  /// fórmula con `a < b` desaparecerían al interpretarse como etiquetas.
  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
