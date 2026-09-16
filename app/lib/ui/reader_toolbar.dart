import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Un botón de la píldora del lector.
///
/// Hay dos clases, y la diferencia se ve: los que **abren panel** se quedan
/// marcados mientras el suyo está desplegado, para que se sepa qué se está
/// mirando; los de **acción directa** —A− y A+— no se marcan nunca, porque no
/// dejan nada abierto detrás.
class ReaderToolbarItem {
  const ReaderToolbarItem({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.panelId,
  });

  /// Atajo para los botones que hacen algo en el acto.
  const ReaderToolbarItem.action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  }) : panelId = null;

  final Widget icon;
  final String tooltip;

  /// `null` deshabilita el botón, que es como A− y A+ avisan de que se ha
  /// llegado al tope del cuerpo de letra.
  final VoidCallback? onTap;

  /// Qué panel abre este botón, o `null` si no abre ninguno.
  final String? panelId;
}

/// La píldora flotante de controles del lector.
///
/// Es deliberadamente tonta: recibe los botones hechos y no sabe si detrás hay
/// tipografías, temas o el sentido de lectura de un manga. Eso es lo que
/// permite que la usen tanto el lector de texto como el de cómics, que no
/// comparten ni un solo ajuste.
///
/// Flota sobre el libro en lugar de ocupar una barra llena: dentro de la
/// lectura el texto es lo único que debe pesar, y una cápsula con sombra se
/// posa encima sin partir la página en dos.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({
    required this.items,
    required this.palette,
    this.openPanel,
    super.key,
  });

  final List<ReaderToolbarItem> items;
  final ReadingPalette palette;

  /// El `panelId` del panel abierto ahora mismo, si hay alguno.
  final String? openPanel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.muted.withValues(alpha: 0.2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _ToolbarButton(
                item: item,
                palette: palette,
                active: item.panelId != null && item.panelId == openPanel,
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.item,
    required this.palette,
    required this.active,
  });

  final ReaderToolbarItem item;
  final ReadingPalette palette;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: IconButton(
        onPressed: item.onTap,
        icon: item.icon,
        tooltip: item.tooltip,
        color: palette.text,
        disabledColor: palette.muted.withValues(alpha: 0.35),
        style: IconButton.styleFrom(
          // El panel abierto se marca con un fondo tenue y no cambiando el
          // color del icono: sobre las cuatro superficies de lectura, un color
          // que destaque en crema se pierde en el tema de alto contraste.
          backgroundColor: active
              ? palette.muted.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ),
    );
  }
}

/// Los dos botones que cambian el cuerpo de letra en el acto.
///
/// Van con letras y no con los iconos de más y menos porque es lo que dice el
/// diseño y porque se entienden sin tooltip: una A pequeña y una A grande.
class ToolbarLetter extends StatelessWidget {
  const ToolbarLetter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }
}
