import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';

/// La hoja de ajustes de lectura.
///
/// Se abre desde los controles del lector y **aplica cada cambio en el acto**,
/// sin botón de guardar. No es por ahorrarse un botón: elegir un cuerpo de
/// letra o un interlineado sin ver el efecto sobre el texto de verdad es
/// imposible, así que la hoja se queda a media pantalla y el libro sigue
/// visible por encima.
///
/// Se pinta con los colores del tema de lectura elegido, no con el índigo del
/// resto de la aplicación: dentro del libro manda el papel.
Future<void> showReadingSettingsSheet(
  BuildContext context, {
  required ReadingSettings current,
  required ValueChanged<ReadingSettings> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // Sin oscurecer lo de detrás: la gracia es ver cómo queda el texto.
    barrierColor: Colors.black12,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(current: current, onChanged: onChanged),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.current, required this.onChanged});

  final ReadingSettings current;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late ReadingSettings _settings = widget.current;

  void _update(ReadingSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _settings.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: palette.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _Label('Tema', palette: palette),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final theme in ReadingTheme.values)
                  _ThemeChip(
                    theme: theme,
                    selected: theme == _settings.theme,
                    onTap: () => _update(_settings.copyWith(theme: theme)),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _Label('Modo de lectura', palette: palette),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ReadingMode.values)
                  _Chip(
                    label: Text(mode.label, style: const TextStyle(fontSize: 14)),
                    selected: mode == _settings.mode,
                    palette: palette,
                    onTap: () => _update(_settings.copyWith(mode: mode)),
                  ),
              ],
            ),
            if (_settings.mode == ReadingMode.paginado) ...[
              const SizedBox(height: 22),
              _Label('Paso de página', palette: palette),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final animation in PageAnimation.values)
                    _Chip(
                      label: Text(
                        animation.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                      selected: animation == _settings.animation,
                      palette: palette,
                      onTap: () =>
                          _update(_settings.copyWith(animation: animation)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            // La animación sólo aparece en modo paginado: en desplazamiento
            // continuo no hay páginas que pasar, y enseñar un ajuste que no
            // hace nada es peor que no enseñarlo.
            _Label('Fuente', palette: palette),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final font in ReadingFont.values)
                  _Chip(
                    // Cada ficha se pinta con su propia tipografía: es la forma
                    // más rápida de elegir, y la única que delata una fuente
                    // que el sistema no tiene y sustituye por otra.
                    label: Text(
                      font.label,
                      style: TextStyle(
                        fontFamily: _settings.copyWith(font: font).fontFamily,
                        fontSize: 14,
                      ),
                    ),
                    selected: font == _settings.font,
                    palette: palette,
                    onTap: () => _update(_settings.copyWith(font: font)),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _Stepper(
              label: 'Tamaño',
              value: '${_settings.fontSize.round()}',
              palette: palette,
              // Menos y más en pasos fijos, no un deslizador: con el pulgar
              // sobre una barra de 200 píxeles no hay forma de repetir el mismo
              // valor dos veces, y esto se ajusta una vez y para siempre.
              onLess: _settings.fontSize > ReadingSettings.minFontSize
                  ? () => _update(
                      _settings.copyWith(fontSize: _settings.fontSize - 1),
                    )
                  : null,
              onMore: _settings.fontSize < ReadingSettings.maxFontSize
                  ? () => _update(
                      _settings.copyWith(fontSize: _settings.fontSize + 1),
                    )
                  : null,
            ),
            _Stepper(
              label: 'Interlineado',
              value: _settings.lineHeight.toStringAsFixed(1),
              palette: palette,
              onLess: _settings.lineHeight > ReadingSettings.minLineHeight
                  ? () => _update(
                      _settings.copyWith(lineHeight: _settings.lineHeight - 0.1),
                    )
                  : null,
              onMore: _settings.lineHeight < ReadingSettings.maxLineHeight
                  ? () => _update(
                      _settings.copyWith(lineHeight: _settings.lineHeight + 0.1),
                    )
                  : null,
            ),
            _Stepper(
              label: 'Margen',
              value: '${_settings.margin.round()}',
              palette: palette,
              onLess: _settings.margin > ReadingSettings.minMargin
                  ? () =>
                        _update(_settings.copyWith(margin: _settings.margin - 4))
                  : null,
              onMore: _settings.margin < ReadingSettings.maxMargin
                  ? () =>
                        _update(_settings.copyWith(margin: _settings.margin + 4))
                  : null,
            ),
            const SizedBox(height: 18),
            _Brightness(
              settings: _settings,
              palette: palette,
              onChanged: _update,
            ),
          ],
        ),
      ),
    );
  }
}

class _Brightness extends StatelessWidget {
  const _Brightness({
    required this.settings,
    required this.palette,
    required this.onChanged,
  });

  final ReadingSettings settings;
  final ReadingPalette palette;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final system = settings.usesSystemBrightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Label('Brillo', palette: palette),
            const Spacer(),
            Text(
              'Usar el del sistema',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
            Switch(
              value: system,
              activeThumbColor: palette.text,
              onChanged: (useSystem) => onChanged(
                useSystem
                    // Volver al del sistema es un caso aparte y no «brillo
                    // cero»: con cero la pantalla se apaga del todo.
                    ? settings.copyWith(useSystemBrightness: true)
                    : settings.copyWith(brightness: 0.7),
              ),
            ),
          ],
        ),
        Slider(
          value: settings.brightness ?? 0.7,
          activeColor: palette.text,
          inactiveColor: palette.muted.withValues(alpha: 0.3),
          // Con el interruptor del sistema puesto, el deslizador no manda: se
          // apaga en lugar de esconderse, para que se vea que existe.
          onChanged: system
              ? null
              : (value) => onChanged(settings.copyWith(brightness: value)),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.palette,
    this.onLess,
    this.onMore,
  });

  final String label;
  final String value;
  final ReadingPalette palette;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _Label(label, palette: palette)),
          IconButton(
            onPressed: onLess,
            icon: const Icon(Icons.remove),
            color: palette.text,
            disabledColor: palette.muted.withValues(alpha: 0.35),
            tooltip: '$label: menos',
          ),
          SizedBox(
            width: 44,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
          IconButton(
            onPressed: onMore,
            icon: const Icon(Icons.add),
            color: palette.text,
            disabledColor: palette.muted.withValues(alpha: 0.35),
            tooltip: '$label: más',
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // La ficha de cada tema se pinta **con ese tema**: se elige mirando el
    // color, no leyendo su nombre.
    final palette = ReadingPalette.of(theme);

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.text : palette.muted.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            theme.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: palette.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final Widget label;
  final bool selected;
  final ReadingPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? palette.muted.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.text : palette.muted.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: palette.text),
            child: label,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.palette});

  final String text;
  final ReadingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
    );
  }
}
