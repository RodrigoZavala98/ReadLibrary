import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';
import 'block_layout.dart';
import 'html_view.dart';
import 'paginator.dart';

/// La superficie de lectura por páginas.
///
/// Envuelve las cuatro animaciones para que la pantalla de lectura no sepa cuál
/// está usando. Tres son nuestras, sobre `PageView`; la de doblar la hoja la
/// pone `page_flip`, que es **la única dependencia de terceros de todo el
/// lector** y está encerrada aquí a propósito: es un paquete 0.2.5, pre-1.0, y
/// si algún día rompe con una versión de Flutter lo que se cae es una animación
/// y no la lectura.
class PagedReader extends StatefulWidget {
  const PagedReader({
    required this.chapter,
    required this.settings,
    required this.initialPage,
    required this.onPageChanged,
    required this.onTapCentre,
    this.imageFor,
    this.onNextChapter,
    this.onPreviousChapter,
    super.key,
  });

  final PagedChapter chapter;
  final ReadingSettings settings;
  final int initialPage;
  final ValueChanged<int> onPageChanged;

  /// Un toque en el centro saca u oculta los controles.
  final VoidCallback onTapCentre;

  final ImageResolver? imageFor;

  /// Qué hacer al intentar pasar de la última página, o de la primera hacia
  /// atrás. `null` si no hay capítulo al que ir.
  final VoidCallback? onNextChapter;
  final VoidCallback? onPreviousChapter;

  /// El hueco entre el borde de la pantalla y el texto.
  ///
  /// Lo usa también quien pagina para saber cuánto sitio hay de verdad. Tiene
  /// que salir de un único sitio: si el que mide creyera que hay más alto del
  /// que hay, la última línea de cada página quedaría cortada.
  static EdgeInsets paddingOf(ReadingSettings settings) =>
      EdgeInsets.symmetric(horizontal: settings.margin, vertical: 28);

  @override
  State<PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<PagedReader> {
  late PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  final _flip = PageFlipController();

  /// La página actual, llevada por nosotros.
  ///
  /// No se le pregunta al `PageController` porque con la animación de doblar la
  /// hoja no hay `PageView` al que preguntar: el controlador existe pero nunca
  /// se engancha, y devolvería siempre la página inicial.
  late int _page = widget.initialPage;

  /// Evita que un arrastre largo al final del capítulo dispare dos saltos.
  bool _changingChapter = false;

  @override
  void didUpdateWidget(PagedReader old) {
    super.didUpdateWidget(old);
    // Al repaginar —otro cuerpo de letra, otra pantalla— el número de página
    // cambia de significado, y el padre ya ha calculado cuál es la equivalente.
    if (widget.initialPage != old.initialPage ||
        widget.chapter != old.chapter) {
      _changingChapter = false;
      final page = widget.initialPage.clamp(0, widget.chapter.length - 1);
      _page = page;
      if (_controller.hasClients) {
        _controller.jumpToPage(page);
      } else {
        _controller.dispose();
        _controller = PageController(initialPage: page);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _current => _page;

  void _setPage(int page) {
    _page = page;
    widget.onPageChanged(page);
  }

  void _next() {
    if (_current >= widget.chapter.length - 1) {
      _goToChapter(widget.onNextChapter);
      return;
    }
    _turnTo(_current + 1);
  }

  void _previous() {
    if (_current <= 0) {
      _goToChapter(widget.onPreviousChapter);
      return;
    }
    _turnTo(_current - 1);
  }

  void _goToChapter(VoidCallback? go) {
    if (go == null || _changingChapter) return;
    _changingChapter = true;
    go();
  }

  void _turnTo(int page) {
    if (widget.settings.animation == PageAnimation.doblar) {
      // Paso a paso se usan `nextPage` y `previousPage` porque son las que
      // animan el doblado y avisan al terminar; `goToPage` salta sin avisar,
      // así que ahí hay que llevar la cuenta a mano.
      if (page == _page + 1) {
        _flip.nextPage();
      } else if (page == _page - 1) {
        _flip.previousPage();
      } else {
        _flip.goToPage(page);
        _setPage(page);
      }
      return;
    }
    if (widget.settings.animation == PageAnimation.ninguna) {
      // «Ninguna» significa ninguna: saltar sin recorrido ni desvanecido.
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: widget.settings.animation == PageAnimation.doblar
                ? _buildFlip()
                : _buildPageView(constraints.maxWidth),
          ),
          // Las zonas de toque van **encima** de la superficie, no alrededor.
          //
          // `page_flip` monta su propio `GestureDetector` opaco con `onTapUp`
          // vacío, y al ser más profundo que el nuestro se quedaba con el toque
          // y no pasaba nada. Puestas encima, el toque lo recogen ellas; los
          // arrastres siguen llegando abajo, porque aquí no hay ningún
          // reconocedor de arrastre que compita.
          Positioned.fill(child: _tapZones()),
        ],
      ),
    );
  }

  /// Tercio izquierdo atrás, tercio derecho adelante, centro los controles.
  ///
  /// Es lo que espera cualquiera que haya usado un lector, y convive con el
  /// gesto de deslizar sin estorbarlo.
  Widget _tapZones() {
    return Row(
      children: [
        Expanded(child: _zone(_previous, 'Página anterior')),
        Expanded(child: _zone(widget.onTapCentre, 'Mostrar los controles')),
        Expanded(child: _zone(_next, 'Página siguiente')),
      ],
    );
  }

  Widget _zone(VoidCallback onTap, String label) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        // Translúcido para que el arrastre siga llegando a la superficie.
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
      ),
    );
  }

  Widget _buildFlip() {
    return PageFlipWidget(
      key: ValueKey(widget.chapter),
      controller: _flip,
      backgroundColor: widget.settings.palette.background,
      initialIndex: widget.initialPage.clamp(0, widget.chapter.length - 1),
      onPageFlipped: _setPage,
      children: [
        for (final page in widget.chapter.pages)
          _PageSurface(
            page: page,
            settings: widget.settings,
            imageFor: widget.imageFor,
          ),
      ],
    );
  }

  Widget _buildPageView(double width) {
    return NotificationListener<OverscrollNotification>(
      // Tirar más allá del final es la forma natural de pedir el capítulo
      // siguiente: el `PageView` no puede ir más lejos, pero avisa de que lo
      // han intentado.
      onNotification: (notification) {
        if (notification.overscroll > 0) {
          _goToChapter(widget.onNextChapter);
        } else if (notification.overscroll < 0) {
          _goToChapter(widget.onPreviousChapter);
        }
        return false;
      },
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.chapter.length,
        onPageChanged: _setPage,
        itemBuilder: (context, index) {
          final surface = _PageSurface(
            page: widget.chapter.pages[index],
            settings: widget.settings,
            imageFor: widget.imageFor,
          );

          if (widget.settings.animation != PageAnimation.desvanecer) {
            return surface;
          }

          // El desvanecido se pinta sobre el propio `PageView`: se deja que
          // desplace, pero cada página se apaga según lo lejos que esté del
          // centro, así que lo que se ve es un fundido y no un arrastre.
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final page = _controller.hasClients && _controller.page != null
                  ? _controller.page!
                  : widget.initialPage.toDouble();
              final distance = (page - index).abs().clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - distance,
                child: Transform.translate(
                  // Se compensa el desplazamiento del PageView para que la
                  // página no se mueva mientras se funde. El ancho viene de
                  // fuera: preguntárselo al contexto en pleno maquetado lanza
                  // «cannot get size during build».
                  offset: Offset((page - index) * width, 0),
                  child: child,
                ),
              );
            },
            child: surface,
          );
        },
      ),
    );
  }
}

/// Una página pintada: sus bloques, con el margen del lector.
class _PageSurface extends StatelessWidget {
  const _PageSurface({
    required this.page,
    required this.settings,
    this.imageFor,
  });

  final BookPage page;
  final ReadingSettings settings;
  final ImageResolver? imageFor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: settings.palette.background,
      padding: PagedReader.paddingOf(settings),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in page.blocks)
            if (BlockLayout.ownPage(block))
              // La imagen se estira hasta llenar la página, que es toda suya.
              Expanded(
                child: HtmlBlockView(
                  block: block,
                  style: settings,
                  imageFor: imageFor,
                ),
              )
            else
              HtmlBlockView(
                block: block,
                style: settings,
                imageFor: imageFor,
              ),
        ],
      ),
    );
  }
}
