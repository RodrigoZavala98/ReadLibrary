import 'dart:io';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/theme/app_theme.dart';
import '../domain/book_format.dart';
import '../domain/book_locator.dart';
import '../domain/library_book.dart';
import '../domain/reading_clock.dart';
import '../formats/txt_book_source.dart';
import 'simple_html.dart';

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

  TxtBookSource? _source;
  List<String> _paragraphs = const [];
  int _chunkIndex = 0;
  int _chunkCount = 1;
  String? _error;
  bool _chromeVisible = false;

  final _style = const ReadingStyle();

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
    _clock.start(widget.now());
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Se guarda aquí y no en cada desplazamiento: escribir el índice entero en
    // disco docenas de veces por minuto sería desperdiciar batería para nada.
    _persistPosition();
    _persistSession();
    _scroll.dispose();
    _source?.dispose();
    super.dispose();
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
    if (widget.book.format != BookFormat.txt) {
      setState(() {
        _error =
            'Todavía no sé abrir ${widget.book.format.name.toUpperCase()}. '
            'De momento solo texto plano.';
      });
      return;
    }

    final source = TxtBookSource(File(widget.book.filePath));
    try {
      await source.open();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
      return;
    }

    final start = widget.book.locator ?? source.startLocator;
    _source = source;
    _chunkCount = source.chapters.length;
    await _showChunk(source.chunkIndexFor(start));
  }

  Future<void> _showChunk(int index) async {
    final source = _source;
    if (source == null) return;

    final html = await source.loadChapter(index);
    if (!mounted) return;
    setState(() {
      _chunkIndex = index;
      _paragraphs = SimpleHtml.toParagraphs(html);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Dónde está el lector ahora mismo, en caracteres desde el inicio del libro.
  ///
  /// Es una estimación: se reparte el desplazamiento del scroll de forma lineal
  /// sobre el rango de caracteres del fragmento. No es exacta —los párrafos no
  /// miden todos lo mismo— pero devuelve al lector a la misma pantalla, que es
  /// lo que importa. La posición exacta al carácter exigiría medir cada línea
  /// tras maquetarla, y el coste no compensa.
  CharLocator _currentLocator() {
    final source = _source;
    if (source == null) return const CharLocator(0);

    final (start, end) = source.chunkRange(_chunkIndex);
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) {
      return CharLocator(start);
    }
    final fraction =
        (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0.0, 1.0);
    return CharLocator(start + ((end - start) * fraction).round());
  }

  void _persistPosition() {
    final source = _source;
    final services = _services;
    if (source == null || services == null) return;

    final locator = _currentLocator();
    final updated = widget.book.copyWith(
      locator: locator,
      progress: source.progressAt(locator),
      lastOpenedAt: widget.now(),
    );
    // Sin await: estamos en dispose y el guardado es de tipo «dispara y olvida».
    // Un fallo aquí solo cuesta la posición de lectura, no el libro.
    services.repository.save(updated);
  }

  void _persistSession() {
    final services = _services;
    if (services == null) return;

    final session = _clock.toSession(
      bookId: widget.book.id,
      now: widget.now(),
    );
    // `null` cuando se abrió el libro y se salió enseguida: no ensucia el
    // historial ni regala días de racha.
    if (session == null) return;
    services.sessions.add(session);
  }

  @override
  Widget build(BuildContext context) {
    final surface = _style.surface;

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
                  itemCount: _paragraphs.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      _paragraphs[i],
                      style: _style.toTextStyle(),
                      textAlign: TextAlign.justify,
                    ),
                  ),
                ),
              ),
            if (_chromeVisible || _error != null)
              _ReaderChrome(
                title: widget.book.title,
                surface: surface,
                chunkIndex: _chunkIndex,
                chunkCount: _chunkCount,
                onBack: () => Navigator.of(context).pop(),
                onPrevious:
                    _chunkIndex > 0 ? () => _showChunk(_chunkIndex - 1) : null,
                onNext: _chunkIndex < _chunkCount - 1
                    ? () => _showChunk(_chunkIndex + 1)
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
    required this.chunkIndex,
    required this.chunkCount,
    required this.onBack,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final ReadingSurface surface;
  final int chunkIndex;
  final int chunkCount;
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
                tooltip: 'Parte anterior',
              ),
              Text(
                'Parte ${chunkIndex + 1} de $chunkCount',
                style: TextStyle(color: surface.muted, fontSize: 13),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                color: surface.text,
                disabledColor: surface.muted.withValues(alpha: 0.4),
                tooltip: 'Parte siguiente',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
