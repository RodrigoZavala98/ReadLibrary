import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../ui/library_screen.dart';

/// Las cuatro secciones de la aplicación.
///
/// Cada una es **contenido al que se vuelve**. Los ajustes y el nombre del
/// lector no están aquí a propósito: se visitan dos veces en la vida de la
/// aplicación y no merecen una cuarta parte de la barra. Viven detrás del
/// avatar, en la cabecera de Mi Refugio.
///
/// Tampoco hay «Explorar»: exigiría un catálogo en línea, y la aplicación es
/// deliberadamente local.
enum HomeSection {
  refugio(label: 'Mi Refugio', icon: Icons.local_fire_department_outlined),
  biblioteca(label: 'Mi Biblioteca', icon: Icons.auto_stories_outlined),
  notas(label: 'Mis Notas', icon: Icons.format_quote_outlined),
  viaje(label: 'Mi Viaje', icon: Icons.insights_outlined);

  const HomeSection({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Contenedor principal: mantiene la sección activa y la barra inferior.
///
/// La barra se esconde al abrir un libro; no se apila sobre el lector. Esa es
/// la razón de que el lector se abra como ruta a pantalla completa por encima
/// de este armazón y no como una cuarta pestaña.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  HomeSection _section = HomeSection.biblioteca;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (_section) {
          HomeSection.refugio => const _Placeholder(
            title: 'Mi Refugio',
            detail: 'Racha de lectura y último libro abierto.',
          ),
          HomeSection.biblioteca => const LibraryScreen(),
          HomeSection.notas => const _Placeholder(
            title: 'Mis Notas',
            detail: 'Frases guardadas y subrayados de tus lecturas.',
          ),
          HomeSection.viaje => const _Placeholder(
            title: 'Mi Viaje',
            detail: 'Logros, estadísticas y tiempo de lectura.',
          ),
        },
      ),
      bottomNavigationBar: _SectionBar(
        current: _section,
        onSelect: (section) => setState(() => _section = section),
      ),
    );
  }
}

/// Barra inferior flotante.
///
/// Se dibuja con widgets normales en lugar de [NavigationBar] porque necesita
/// bordes muy redondeados, fondo propio y quedar despegada del borde inferior,
/// y forzar eso sobre el componente de Material sale más caro que hacerlo
/// directamente.
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.current, required this.onSelect});

  final HomeSection current;
  final ValueChanged<HomeSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ChromeTheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            // Cada pestaña ocupa una fracción igual en lugar de medir según su
            // texto. Con cuatro secciones y rótulos de longitud desigual, dejar
            // que cada una se ajuste a su contenido desborda en pantallas
            // estrechas y descoloca los iconos.
            child: Row(
              children: [
                for (final section in HomeSection.values)
                  Expanded(
                    child: _SectionTab(
                      section: section,
                      selected: section == current,
                      onTap: () => onSelect(section),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final HomeSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ChromeTheme.accent : ChromeTheme.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(section.icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marcador de posición hasta que cada sección tenga contenido real.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: ChromeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ChromeTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
