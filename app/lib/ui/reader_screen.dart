import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/theme/app_theme.dart';
import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/book_source.dart';
import '../domain/library_book.dart';
import '../domain/reading_clock.dart';
import '../formats/epub_book_source.dart';
import '../formats/txt_book_source.dart';
import 'html_view.dart';
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

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _clock = ReadingClock();

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

  final _style = const ReadingStyle();

  /// Hasta dónde se ha avanzado dentro del fragmento actual, de 0 a 1.
  ///
  /// Se mantiene al día en cada desplazamiento **mientras el widget vive**, en
  /// lugar de consultarse al cerrar. Preguntárselo al `ScrollController` desde
  /// `dispose()` no funciona: Flutter desmonta los hijos antes que los padres,
  /// así que para entonces el `ListView` ya no existe y la posición está
  /// desacoplada. El valor leído sería siempre cero.
  double _lastFraction = 0;

  /// Evita guardar dos veces.
  ///
  /// Lo normal es persistir al salir, de forma esperada, para que la
  /// biblioteca ya encuentre los datos frescos al recargar. Pero [dispose]
  /// mantiene un guardado de reserva por si la pantalla desaparece sin pasar
  /// por ahí, y sin este testigo la sesión de lectura se registraría dos veces
  /// y el día contaría doble.
  bool _persisted = false;

  /// Los servicios, capturados mientras el widget está vivo.
  ///
  /// No se puede llamar a `AppScope.of(context)` desde [dispose]: por debajo
  /// usa `dependOnInheritedWidgetOfExactType`, y Flutter lo prohíbe sobre un
  /// widget ya desactivado —«Looking up a deactivated widget's ancestor is
  /// unsafe»—. Hacerlo lanzaba una excepción justo en el momento de guardar, y
  /// ni la posición ni la sesión llegaban nunca al disco.
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_rememberPosition);
    _clock.start(widget.now());
    _load();
  }

  /// Anota el avance dentro del fragmento actual.
  void _rememberPosition() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    // Sin nada que desplazar, el fragmento entero está a la vista: se ha visto
    // hasta el final. Tratarlo como «estoy al principio» dejaría un texto corto
    // leído de cabo a rabo marcado al cero por ciento.
    _lastFraction = max <= 0 ? 1 : (_scroll.offset / max).clamp(0.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Red de seguridad: si la pantalla se va sin pasar por _leave, se intenta
    // guardar igualmente. Aquí no se puede esperar al resultado, así que es
    // «dispara y olvida» y la biblioteca podría no verlo a tiempo. Por eso la
    // salida normal guarda antes de cerrar, no aquí.
    unawaited(_persistAll());
    _scroll.dispose();
    _source?.dispose();
    super.dispose();
  }

  /// Guarda posición y sesión. Idempotente.
  Future<void> _persistAll() async {
    if (_persisted) return;
    _persisted = true;

    final services = _services;
    if (services == null) return;

    final source = _source;
    if (source != null) {
      final locator = _currentLocator();
      await services.repository.save(
        widget.book.copyWith(
          locator: locator,
          progress: source.progressAt(locator),
          lastOpenedAt: widget.now(),
        ),
      );
    }

    final session = _clock.toSession(
      bookId: widget.book.id,
      now: widget.now(),
    );
    // `null` cuando se abrió el libro y se salió enseguida: no ensucia el
    // historial ni regala días de racha.
    if (session != null) await services.sessions.add(session);
  }

  /// Salida ordenada: primero se guarda, después se cierra.
  ///
  /// El orden es lo que arregla que la biblioteca mostrara el avance anterior
  /// hasta cambiar de pestaña y volver: recargaba antes de que el guardado
  /// hubiera terminado.
  Future<void> _leave() async {
    await _persistAll();
    if (mounted) Navigator.of(context).pop();
  }

  /// El cronómetro sigue al ciclo de vida de la aplicación.
  ///
  /// Sin esto, dejar el libro abierto y bloquear el móvil registraría toda la
  /// noche como tiempo de lectura, y la racha dejaría de significar nada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = widget.now();
    switch (state) {
      case AppLifecycleState.resumed:
        _clock.resume(now);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _clock.pause(now);
    }
  }

  Future<void> _load() async {
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

  /// Dónde está el lector ahora mismo.
  ///
  /// Cada formato traduce «voy por la mitad del capítulo siete» a lo suyo: un
  /// desplazamiento en caracteres en un TXT, el documento del lomo y las
  /// milésimas recorridas en un EPUB. La pantalla ya no sabe cuál es cuál.
  BookLocator _currentLocator() {
    final source = _source;
    if (source == null) return const CharLocator(0);
    return source.locatorAt(_chapterIndex, _lastFraction);
  }

  /// Las imágenes salen del propio ZIP del EPUB y son relativas al capítulo que
  /// las enseña. Un TXT no tiene ninguna.
  Uint8List? _imageFor(String src) {
    final source = _source;
    if (source is! EpubBookSource) return null;
    return source.imageBytes(_chapterIndex, src);
  }

  @override
  Widget build(BuildContext context) {
    final surface = _style.surface;

    return PopScope(
      // Se bloquea el cierre automático para poder guardar antes de irnos.
      // Cubre tanto el botón de la barra como el gesto de atrás de Android.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: _buildReader(surface),
    );
  }

  Widget _buildReader(ReadingSurface surface) {
    return Scaffold(
      backgroundColor: surface.background,
      body: SafeArea(
        child: Stack(
          children: [
            if (_error != null)
              _ReaderMessage(text: _error!, surface: surface)
            else if (_source == null)
              const Center(child: CircularProgressIndicator())
            else
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    _style.margin,
                    32,
                    _style.margin,
                    96,
                  ),
                  itemCount: _blocks.length,
                  itemBuilder: (_, i) => HtmlBlockView(
                    block: _blocks[i],
                    style: _style,
                    imageFor: _imageFor,
                  ),
                ),
              ),
            if (_chromeVisible || _error != null)
              _ReaderChrome(
                title: widget.book.title,
                surface: surface,
                chapterTitle: _chapterTitle,
                chapterIndex: _chapterIndex,
                chapterCount: _chapterCount,
                onBack: () => unawaited(_leave()),
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
  const _ReaderMessage({required this.text, required this.surface});

  final String text;
  final ReadingSurface surface;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: surface.muted, height: 1.5),
        ),
      ),
    );
  }
}

/// Los controles: aparecen al tocar el centro y desaparecen al volver a tocar.
class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.title,
    required this.surface,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.onBack,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final ReadingSurface surface;
  /// «Parte 3» en un TXT; el título real del capítulo en un EPUB que lo traiga.
  final String chapterTitle;

  final int chapterIndex;
  final int chapterCount;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: surface.background.withValues(alpha: 0.96),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: surface.text,
                tooltip: 'Volver a la biblioteca',
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: surface.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          color: surface.background.withValues(alpha: 0.96),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
                color: surface.text,
                disabledColor: surface.muted.withValues(alpha: 0.4),
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
                      style: TextStyle(color: surface.text, fontSize: 13),
                    ),
                    Text(
                      '${chapterIndex + 1} de $chapterCount',
                      style: TextStyle(color: surface.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                color: surface.text,
                disabledColor: surface.muted.withValues(alpha: 0.4),
                tooltip: 'Capítulo siguiente',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
