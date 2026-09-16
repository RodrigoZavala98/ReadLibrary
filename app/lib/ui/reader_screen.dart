import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/book_source.dart';
import '../domain/library_book.dart';
import '../domain/reading_settings.dart';
import '../formats/epub_book_source.dart';
import '../formats/txt_book_source.dart';
import 'chapters_sheet.dart';
import 'html_view.dart';
import 'paged_reader.dart';
import 'paginator.dart';
import 'progress_hairline.dart';
import 'reader_session.dart';
import 'reading_settings_sheet.dart';
import 'rich_html.dart';

/// La pantalla de lectura.
///
/// Aquí se cruza al otro mundo: desaparece el índigo del cromo y la pantalla se
/// convierte en papel. No hay barra de navegación ni botones a la vista; un
/// toque en el centro hace aparecer los controles y otro los esconde.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.book, this.now = DateTime.now, super.key});

  final LibraryBook book;

  /// De dónde sale la hora actual. Se puede sustituir en las pruebas para
  /// simular una lectura larga sin esperarla de verdad.
  final DateTime Function() now;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ReaderSessionState<ReaderScreen> {
  final _scroll = ScrollController();

  /// El lector habla con la interfaz, no con un formato.
  ///
  /// Antes era un `TxtBookSource`, y esta pantalla sabía de fragmentos y de
  /// desplazamientos en caracteres, que son cosas del texto plano. Un EPUB no
  /// tiene nada de eso: tiene documentos dentro de un ZIP.
  ReflowableSource? _source;

  List<HtmlBlock> _blocks = const [];
  int _chapterIndex = 0;
  int _chapterCount = 1;
  String _chapterTitle = '';
  String? _error;
  bool _chromeVisible = false;

  /// Tema, tipografía y medidas. Se cargan del disco al entrar y se guardan en
  /// cuanto se tocan.
  ReadingSettings _settings = ReadingSettings();

  /// Avance dentro del libro entero, de 0 a 1.
  ///
  /// Va en un `ValueNotifier` y no en el estado del widget a propósito: se
  /// actualiza en cada fotograma de desplazamiento, y llamar a `setState` tan a
  /// menudo reconstruiría el capítulo entero —con sus imágenes— sesenta veces
  /// por segundo. Así sólo se repinta el hilo del margen.
  final _progress = ValueNotifier<double>(0);

  /// El capítulo repartido en páginas, y la combinación con la que se repartió.
  ///
  /// Se guarda en caché porque paginar mide cada bloque con `TextPainter`, y
  /// eso no se puede rehacer en cada fotograma. Sólo cambia cuando cambia el
  /// capítulo, el tamaño de la pantalla o algún ajuste que mueva el texto.
  PagedChapter? _paged;
  Object? _pagedKey;

  /// Hasta dónde se ha avanzado dentro del fragmento actual, de 0 a 1.
  ///
  /// Se mantiene al día en cada desplazamiento **mientras el widget vive**, en
  /// lugar de consultarse al cerrar. Preguntárselo al `ScrollController` desde
  /// `dispose()` no funciona: Flutter desmonta los hijos antes que los padres,
  /// así que para entonces el `ListView` ya no existe y la posición está
  /// desacoplada. El valor leído sería siempre cero.
  double _lastFraction = 0;

  @override
  LibraryBook get book => widget.book;

  @override
  DateTime Function() get now => widget.now;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_rememberPosition);
  }

  /// Anota el avance dentro del fragmento actual.
  void _rememberPosition() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _updateProgress();
    // Sin nada que desplazar, el fragmento entero está a la vista: se ha visto
    // hasta el final. Tratarlo como «estoy al principio» dejaría un texto corto
    // leído de cabo a rabo marcado al cero por ciento.
    _lastFraction = max <= 0 ? 1 : (_scroll.offset / max).clamp(0.0, 1.0);
  }

  @override
  void releaseResources() {
    _scroll.dispose();
    _progress.dispose();
    _source?.dispose();
  }

  Future<void> _openSettings() async {
    await showReadingSettingsSheet(
      context,
      current: _settings,
      onChanged: (next) {
        setState(() => _settings = next);
        // Se guarda en cada toque en lugar de al cerrar la hoja: si la
        // aplicación muere con los ajustes abiertos, lo elegido ya está en el
        // disco. Son escrituras de doscientos bytes.
        unawaited(services?.settings.save(next) ?? Future<void>.value());
        unawaited(applyBrightness(_settings.brightness));
      },
    );
  }

  Future<void> _openChapters() async {
    final source = _source;
    if (source == null) return;

    final chosen = await showChaptersSheet(
      context,
      chapters: source.chapters,
      current: _chapterIndex,
      settings: _settings,
    );
    if (chosen != null) await _showChapter(chosen);
  }

  void _updateProgress() {
    final locator = currentLocator();
    if (locator == null) return;
    _progress.value = progressAt(locator);
  }

  @override
  Future<void> load() async {
    final settings = await services?.settings.load();
    if (settings != null && mounted) {
      setState(() => _settings = settings);
      await applyBrightness(_settings.brightness);
    }

    final source = _sourceFor(widget.book);
    if (source == null) {
      setState(() {
        _error =
            'Todavía no sé abrir ${widget.book.format.name.toUpperCase()}. '
            'De momento solo texto plano y EPUB.';
      });
      return;
    }

    try {
      await source.open();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _explain(error));
      return;
    }

    if (!mounted) {
      // La pantalla se fue mientras el libro se abría. Hay que soltarlo aquí:
      // `dispose()` ya pasó y no encontró ninguna fuente que cerrar, así que el
      // descriptor del fichero se quedaría abierto durante toda la vida de la
      // aplicación. En un EPUB eso es un ZIP abierto, y en Windows impide hasta
      // borrar el fichero.
      await source.dispose();
      return;
    }

    final saved = widget.book.locator ?? source.startLocator;
    _source = source;
    _chapterCount = source.chapters.length;

    // Abrir por el principio del capítulo dejaría al lector buscando por dónde
    // iba: un capítulo son varias pantallas.
    final index = source.chapterIndexFor(saved);
    await _showChapter(index, atFraction: source.fractionWithin(index, saved));
  }

  /// La única línea de esta pantalla que menciona un formato concreto.
  static ReflowableSource? _sourceFor(LibraryBook book) =>
      switch (book.format) {
        BookFormat.txt => TxtBookSource(File(book.filePath)),
        BookFormat.epub => EpubBookSource(File(book.filePath)),
        _ => null,
      };

  /// Un [BookOpenException] ya trae una explicación escrita para el usuario
  /// —«este EPUB está protegido con DRM»—; enseñar su `toString` le pondría
  /// delante el nombre de una clase de Dart.
  static String _explain(Object error) =>
      error is BookOpenException ? error.message : '$error';

  Future<void> _showChapter(int index, {double atFraction = 0}) async {
    final source = _source;
    if (source == null) return;

    final html = await source.loadChapter(index);
    if (!mounted) return;
    setState(() {
      _chapterIndex = index;
      _blocks = RichHtml.parse(html);
      _chapterTitle = source.chapters[index].title;
      _lastFraction = atFraction;
    });

    // La posición solo se puede fijar cuando la lista ya está maquetada, que es
    // también el único momento en que se conoce su extensión desplazable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(max * atFraction);
      _rememberPosition();
    });
  }

  /// Reparte el capítulo en páginas, o devuelve el reparto ya hecho.
  PagedChapter _pagedFor(Size viewport) {
    final key = (_chapterIndex, viewport, _settings);
    final cached = _paged;
    if (cached != null && _pagedKey == key) return cached;

    final paged = Paginator.paginate(
      blocks: _blocks,
      settings: _settings,
      viewport: viewport,
    );
    _paged = paged;
    _pagedKey = key;
    return paged;
  }

  /// Dónde está el lector ahora mismo.
  ///
  /// Cada formato traduce «voy por la mitad del capítulo siete» a lo suyo: un
  /// desplazamiento en caracteres en un TXT, el documento del lomo y las
  /// milésimas recorridas en un EPUB. La pantalla ya no sabe cuál es cuál.
  ///
  /// `null` mientras el libro no se ha abierto: no hay ninguna posición que
  /// guardar todavía, y devolver el principio del libro la machacaría.
  @override
  BookLocator? currentLocator() =>
      _source?.locatorAt(_chapterIndex, _lastFraction);

  @override
  double progressAt(BookLocator locator) => _source?.progressAt(locator) ?? 0;

  /// Las imágenes salen del propio ZIP del EPUB y son relativas al capítulo que
  /// las enseña. Un TXT no tiene ninguna.
  Uint8List? _imageFor(String src) {
    final source = _source;
    if (source is! EpubBookSource) return null;
    return source.imageBytes(_chapterIndex, src);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _settings.palette;

    return PopScope(
      // Se bloquea el cierre automático para poder guardar antes de irnos.
      // Cubre tanto el botón de la barra como el gesto de atrás de Android.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: _buildReader(palette),
    );
  }

  /// La lectura por páginas.
  ///
  /// El reparto depende del sitio que haya de verdad, así que se calcula dentro
  /// de un `LayoutBuilder` y no antes: el margen lo elige el usuario y la
  /// pantalla cambia al girar el teléfono.
  Widget _buildPaged() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PagedReader.paddingOf(_settings);
        final paged = _pagedFor(
          Size(
            constraints.maxWidth - padding.horizontal,
            constraints.maxHeight - padding.vertical,
          ),
        );

        // La página se **deduce** de dónde estabas, no se guarda. Con otro
        // cuerpo de letra el número de página ya no significa lo mismo, pero el
        // carácter sí: por eso subir la letra te deja en la misma frase.
        final page = paged.pageForChar(
          (_lastFraction * paged.totalChars).round(),
        );

        return PagedReader(
          key: ValueKey(_chapterIndex),
          chapter: paged,
          settings: _settings,
          initialPage: page,
          imageFor: _imageFor,
          onPageChanged: (index) {
            // Sin `setState`: sólo cambia el hilo del avance, que se pinta
            // solo, y reconstruir la página entera al pasarla sería absurdo.
            _lastFraction = paged.fractionAt(index);
            _updateProgress();
          },
          onTapCentre: () => setState(() => _chromeVisible = !_chromeVisible),
          onNextChapter: _chapterIndex < _chapterCount - 1
              ? () => _showChapter(_chapterIndex + 1)
              : null,
          // Hacia atrás se entra por el final del capítulo anterior, que es por
          // donde se entraría pasando la página al revés en un libro.
          onPreviousChapter: _chapterIndex > 0
              ? () => _showChapter(_chapterIndex - 1, atFraction: 1)
              : null,
        );
      },
    );
  }

  Widget _buildReader(ReadingPalette palette) {
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Stack(
          children: [
            if (_error != null)
              _ReaderMessage(text: _error!, palette: palette)
            else if (_source == null)
              const Center(child: CircularProgressIndicator())
            else if (_settings.mode == ReadingMode.paginado)
              _buildPaged()
            else
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    _settings.margin,
                    32,
                    _settings.margin,
                    96,
                  ),
                  itemCount: _blocks.length,
                  itemBuilder: (_, i) => HtmlBlockView(
                    block: _blocks[i],
                    style: _settings,
                    imageFor: _imageFor,
                  ),
                ),
              ),
            // El avance se ve **siempre**, no sólo con los controles fuera.
            // Es una revisión consciente del «dentro del libro no hay cromo»:
            // saber por dónde vas era justo lo que faltaba, y un hilo de dos
            // píxeles en el margen no compite con el texto.
            if (_error == null && _source != null)
              ProgressHairline(progress: _progress, palette: palette),
            if (_chromeVisible || _error != null)
              _ReaderChrome(
                title: widget.book.title,
                palette: palette,
                chapterTitle: _chapterTitle,
                chapterIndex: _chapterIndex,
                chapterCount: _chapterCount,
                onBack: () => unawaited(leave()),
                onChapters: _source == null ? null : _openChapters,
                onSettings: _source == null ? null : _openSettings,
                progress: _progress,
                onPrevious: _chapterIndex > 0
                    ? () => _showChapter(_chapterIndex - 1)
                    : null,
                onNext: _chapterIndex < _chapterCount - 1
                    ? () => _showChapter(_chapterIndex + 1)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderMessage extends StatelessWidget {
  const _ReaderMessage({required this.text, required this.palette});

  final String text;
  final ReadingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, height: 1.5),
        ),
      ),
    );
  }
}

/// Los controles: aparecen al tocar el centro y desaparecen al volver a tocar.
class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.title,
    required this.palette,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.progress,
    required this.onBack,
    this.onChapters,
    this.onSettings,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final ReadingPalette palette;

  /// «Parte 3» en un TXT; el título real del capítulo en un EPUB que lo traiga.
  final String chapterTitle;

  final int chapterIndex;
  final int chapterCount;
  final ValueListenable<double> progress;
  final VoidCallback onBack;
  final VoidCallback? onChapters;
  final VoidCallback? onSettings;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final bar = palette.background.withValues(alpha: 0.96);

    return Column(
      children: [
        Container(
          color: bar,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: palette.text,
                tooltip: 'Volver a la biblioteca',
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onChapters,
                icon: const Icon(Icons.list),
                color: palette.text,
                disabledColor: palette.muted.withValues(alpha: 0.4),
                tooltip: 'Índice',
              ),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.text_fields),
                color: palette.text,
                disabledColor: palette.muted.withValues(alpha: 0.4),
                tooltip: 'Ajustes de lectura',
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          color: bar,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
                color: palette.text,
                disabledColor: palette.muted.withValues(alpha: 0.4),
                tooltip: 'Capítulo anterior',
              ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.text, fontSize: 13),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (_, value, _) => Text(
                        'Capítulo ${chapterIndex + 1} de $chapterCount  ·  '
                        '${(value * 100).round()} % del libro',
                        style: TextStyle(color: palette.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                color: palette.text,
                disabledColor: palette.muted.withValues(alpha: 0.4),
                tooltip: 'Capítulo siguiente',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
