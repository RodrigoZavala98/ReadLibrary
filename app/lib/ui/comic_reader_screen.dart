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
import '../formats/cbz_book_source.dart';
import 'comic_settings_sheet.dart';
import 'progress_hairline.dart';
import 'reader_session.dart';

/// Los colores del lector de cómics.
///
/// Van aquí y no en `core/theme` porque no son un tema de lectura: el lector
/// de texto ofrece cuatro superficies de papel a elegir, y un cómic no ofrece
/// ninguna. Es siempre negro, y por eso es una constante y no un ajuste.
const _background = Colors.black;
const _surface = Color(0xE6161616);
const _text = Color(0xFFECECEC);
const _muted = Color(0xFF9A9A9A);

/// La pantalla de lectura de un cómic.
///
/// Es hermana de `ReaderScreen` y no una variante suya: comparten por la clase
/// base todo lo que es leer —cronómetro, posición, salida ordenada, brillo— y
/// no comparten nada de lo que es pintar. Un cómic no se re-maqueta, no tiene
/// capítulos, no tiene tipografía y no admite que le cambies el margen: es una
/// sucesión de imágenes con un número de página estable.
///
/// El fondo es **negro**, no el papel cálido del lector de texto. Es la
/// excepción razonada a los dos mundos visuales del proyecto: la página de un
/// cómic trae su propio papel dibujado dentro, y rodearla de crema hace que
/// pelee con el color de la propia viñeta.
class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    required this.book,
    this.now = DateTime.now,
    super.key,
  });

  final LibraryBook book;

  /// De dónde sale la hora actual. Se puede sustituir en las pruebas para
  /// simular una lectura larga sin esperarla de verdad.
  final DateTime Function() now;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends ReaderSessionState<ComicReaderScreen> {
  /// La paleta que necesita el hilo de avance, que está escrito contra los
  /// temas de lectura. Aquí se le da una oscura a mano en lugar de arrastrar el
  /// tema del papel, que no pinta nada sobre negro.
  static const _palette = ReadingPalette(
    background: _background,
    text: _text,
    muted: _muted,
  );

  FixedLayoutSource? _source;
  PageController? _pages;

  int _page = 0;
  int _pageCount = 0;
  String? _error;
  bool _chromeVisible = false;

  ComicDirection _direction = ComicDirection.occidental;

  /// Escala del zoom de la página actual.
  ///
  /// No es decorativa: mientras vale 1 el arrastre pasa página, y en cuanto se
  /// amplía el arrastre tiene que ser del zoom. Ver [_zoom].
  final _zoom = TransformationController();
  bool _zoomed = false;

  /// Avance dentro del cómic, de 0 a 1. En un `ValueNotifier` por lo mismo que
  /// en el lector de texto: para repintar el hilo sin reconstruir la página.
  final _progress = ValueNotifier<double>(0);

  /// Las páginas ya descomprimidas.
  ///
  /// Sólo la actual y sus vecinas: un cómic entero en memoria son cientos de
  /// megabytes. Se guardan los bytes comprimidos tal y como salen del archivo,
  /// no el mapa de bits decodificado, que ocupa mucho más.
  final _cache = <int, Uint8List>{};

  @override
  LibraryBook get book => widget.book;

  @override
  DateTime Function() get now => widget.now;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_watchZoom);
  }

  @override
  void releaseResources() {
    _zoom.dispose();
    _pages?.dispose();
    _progress.dispose();
    _source?.dispose();
  }

  /// Un cómic sí sabe cuántas páginas tiene, y el modelo tenía el campo sin
  /// rellenar desde el primer día. La biblioteca puede enseñarlo sin abrirlo.
  @override
  LibraryBook bookToSave(BookLocator locator) =>
      super.bookToSave(locator).copyWith(totalPages: _source?.pageCount);

  @override
  BookLocator? currentLocator() => _source == null ? null : PageLocator(_page);

  @override
  double progressAt(BookLocator locator) => _source?.progressAt(locator) ?? 0;

  @override
  Future<void> load() async {
    final settings = await services?.settings.load();
    if (settings != null && mounted) {
      setState(() => _direction = settings.comicDirection);
      await applyBrightness(settings.brightness);
    }

    final source = _sourceFor(widget.book);
    if (source == null) {
      setState(() {
        _error =
            'Todavía no sé abrir ${widget.book.format.name.toUpperCase()}. '
            'De los formatos de página fija, de momento solo CBZ.';
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
      // La pantalla se fue mientras el cómic se abría. Hay que soltarlo aquí:
      // `dispose()` ya pasó y no encontró ninguna fuente que cerrar, así que el
      // archivo se quedaría abierto durante toda la vida de la aplicación, y en
      // Windows eso impide hasta borrar el fichero.
      await source.dispose();
      return;
    }

    final saved = widget.book.locator ?? source.startLocator;
    // Un localizador de otro formato ya lo descarta `BookLocator.decode`, pero
    // uno de este que apunte más allá del final sí puede llegar: basta con
    // reemplazar el fichero por una edición con menos páginas.
    //
    // El recorte es un cinturón sobre los tirantes, y conviene saberlo: el
    // `PageView` también corrige solo una página inicial fuera de rango, y de
    // hecho es él quien salva el caso en las pruebas. Se recorta igualmente
    // para que `_page`, el avance y la posición que se guardaría al salir sean
    // coherentes **antes** del primer fotograma, sin depender de que el
    // viewport haya llegado a maquetarse.
    final page = saved is PageLocator
        ? saved.pageIndex.clamp(0, source.pageCount - 1)
        : 0;

    setState(() {
      _source = source;
      _pageCount = source.pageCount;
      _page = page;
      _pages = PageController(initialPage: page);
    });
    _progress.value = source.progressAt(PageLocator(page));
    unawaited(_warm(page));
  }

  /// La única línea de esta pantalla que menciona un formato concreto.
  static FixedLayoutSource? _sourceFor(LibraryBook book) =>
      switch (book.format) {
        BookFormat.cbz => CbzBookSource(File(book.filePath)),
        _ => null,
      };

  /// Un [BookOpenException] ya trae una explicación escrita para el usuario;
  /// enseñar su `toString` le pondría delante el nombre de una clase de Dart.
  static String _explain(Object error) =>
      error is BookOpenException ? error.message : '$error';

  /// Deja en la caché la página [index] y sus vecinas, y tira el resto.
  ///
  /// Se piden las de al lado por adelantado porque descomprimir ocurre en el
  /// hilo de la interfaz: hacerlo en el momento de pasar la página se notaría
  /// como un tirón. Limitación asumida, y la salida si algún día molesta es un
  /// isolate con su propio descriptor del archivo, no una caché más pequeña.
  Future<void> _warm(int index) async {
    final source = _source;
    if (source == null) return;

    _cache.removeWhere((page, _) => (page - index).abs() > 1);

    for (final page in [index, index + 1, index - 1]) {
      if (page < 0 || page >= source.pageCount) continue;
      if (_cache.containsKey(page)) continue;
      try {
        // El ancho da igual en un CBZ, que devuelve la imagen tal cual; lo
        // pide la interfaz por el PDF, que sí rasteriza.
        final bytes = await source.renderPage(page, targetWidth: 0);
        if (!mounted) return;
        _cache[page] = bytes;
        // Sólo se repinta si la página que acaba de llegar es la que se está
        // mirando; las vecinas se quedan calientes sin mover nada.
        if (page == _page) setState(() {});
      } on Object {
        // Una página dañada no puede tumbar el cómic entero: se queda sin
        // pintar y las demás siguen pasándose.
      }
    }
  }

  void _watchZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _goTo(int page) {
    final controller = _pages;
    if (controller == null || page < 0 || page >= _pageCount) return;
    controller.jumpToPage(page);
  }

  void _onPageChanged(int page) {
    // Al cambiar de página el zoom vuelve a uno: quedarse ampliado en la
    // esquina de la página siguiente desorienta, porque no se sabe qué trozo
    // de viñeta se está mirando.
    _zoom.value = Matrix4.identity();
    setState(() => _page = page);
    _progress.value = progressAt(PageLocator(page));
    unawaited(_warm(page));
  }

  Future<void> _openSettings() async {
    await showComicSettingsSheet(
      context,
      current: _direction,
      onChanged: (next) {
        setState(() => _direction = next);
        final settings = services?.settings;
        if (settings == null) return;
        unawaited(
          settings.load().then(
            (current) => settings.save(current.copyWith(comicDirection: next)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Se bloquea el cierre automático para poder guardar antes de irnos.
      // Cubre tanto el botón de la barra como el gesto de atrás de Android.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Stack(
            children: [
              if (_error != null)
                _ComicMessage(text: _error!)
              else if (_source == null)
                const Center(child: CircularProgressIndicator())
              else
                _buildPages(),
              if (_error == null && _source != null)
                ProgressHairline(progress: _progress, palette: _palette),
              if (_chromeVisible || _error != null)
                _ComicChrome(
                  title: widget.book.title,
                  page: _page,
                  pageCount: _pageCount,
                  onBack: () => unawaited(leave()),
                  onSettings: _source == null ? null : _openSettings,
                  onJump: _source == null ? null : _goTo,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPages() {
    return Stack(
      children: [
        PageView.builder(
          controller: _pages,
          // Es lo único que cambia entre un cómic y un manga: el eje se
          // invierte y con él las dos zonas de toque, que van sobre él.
          reverse: _direction == ComicDirection.manga,
          // Con la página ampliada el arrastre es del zoom, no del pase de
          // página: si no, mover la vista dentro de una viñeta saltaría de
          // página a la mitad del gesto.
          physics: _zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: _pageCount,
          onPageChanged: _onPageChanged,
          itemBuilder: (_, index) => _ComicPage(
            bytes: _cache[index],
            // Sólo la página que se está mirando es ampliable. Compartir el
            // controlador entre todas dejaría las vecinas con el mismo zoom.
            controller: index == _page ? _zoom : null,
          ),
        ),
        // Las zonas de toque van **encima** de la superficie, por lo mismo que
        // en el lector de texto: quien gobierna los gestos de debajo se los
        // come. Con la página ampliada se apagan, para no robarle el arrastre
        // al zoom.
        if (!_zoomed)
          Positioned.fill(
            child: Row(
              children: [
                _TapZone(onTap: () => _turn(back: true)),
                _TapZone(
                  flex: 2,
                  onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                ),
                _TapZone(onTap: () => _turn(back: false)),
              ],
            ),
          ),
      ],
    );
  }

  /// Pasa página hacia delante o hacia atrás **en el sentido de la lectura**.
  ///
  /// En un manga el borde derecho es el que retrocede, así que no se puede
  /// hablar de «izquierda» y «derecha» sino de antes y después.
  void _turn({required bool back}) {
    final forward = _direction == ComicDirection.manga ? back : !back;
    _goTo(_page + (forward ? 1 : -1));
  }
}

/// Una página del cómic, ampliable con dos dedos.
class _ComicPage extends StatelessWidget {
  const _ComicPage({required this.bytes, this.controller});

  final Uint8List? bytes;
  final TransformationController? controller;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return InteractiveViewer(
      transformationController: controller,
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.memory(
          data,
          fit: BoxFit.contain,
          // Sin esto la página parpadea en blanco al volver a ella.
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const _ComicMessage(
            text: 'Esta página está dañada y no se puede enseñar.',
          ),
        ),
      ),
    );
  }
}

/// Una franja que sólo escucha toques y deja pasar todo lo demás.
class _TapZone extends StatelessWidget {
  const _TapZone({required this.onTap, this.flex = 1});

  final VoidCallback onTap;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
      ),
    );
  }
}

class _ComicMessage extends StatelessWidget {
  const _ComicMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.5),
        ),
      ),
    );
  }
}

/// Los controles del cómic: aparecen al tocar el centro.
///
/// No traen ni índice ni ajustes de tipografía —un cómic no tiene capítulos ni
/// cuerpo de letra— y sí traen un deslizador, que es lo que de verdad hace
/// falta para moverse por un tomo de doscientas páginas.
class _ComicChrome extends StatelessWidget {
  const _ComicChrome({
    required this.title,
    required this.page,
    required this.pageCount,
    required this.onBack,
    this.onSettings,
    this.onJump,
  });

  final String title;
  final int page;
  final int pageCount;
  final VoidCallback onBack;
  final VoidCallback? onSettings;
  final ValueChanged<int>? onJump;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: _surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: _text,
                tooltip: 'Volver a la biblioteca',
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.swap_horiz),
                color: _text,
                disabledColor: _muted,
                tooltip: 'Sentido de lectura',
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Página ${page + 1} de $pageCount',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              if (pageCount > 1)
                Slider(
                  value: page.toDouble(),
                  max: (pageCount - 1).toDouble(),
                  // Una parada por página: no existe media página en un cómic.
                  divisions: pageCount - 1,
                  label: '${page + 1}',
                  activeColor: _text,
                  inactiveColor: _muted,
                  onChanged: onJump == null
                      ? null
                      : (value) => onJump!(value.round()),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
