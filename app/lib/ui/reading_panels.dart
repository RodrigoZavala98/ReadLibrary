/// Los paneles de ajustes que despliega la píldora del lector.
///
/// Antes esto era una sola hoja modal con todo dentro. El problema de la hoja
/// no era el tamaño: era la barrera. Para pasar de los temas a la tipografía
/// había que cerrarla y volver a abrirla, y elegir un cuerpo de letra sin ver
/// el texto debajo es justo lo que no se puede hacer.
///
/// Repartido en paneles, cada botón de la píldora enseña el suyo y se cambia de
/// uno a otro sin cerrar nada.
///
/// Los paneles no se dibujan su propio fondo: sólo el contenido. El marco —la
/// superficie, las esquinas y la sombra— lo pone quien los aloja, que es el que
/// sabe si está dentro de un libro de papel o de un cómic sobre negro.
library;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reading_settings.dart';

/// Todo lo que cambia cómo se compone y se recorre el texto.
///
/// Incluye el modo de lectura y el paso de página, que no tienen botón propio
/// en la píldora: son de la misma familia que el resto —cómo se recorre el
/// texto— y darles un botón para algo que se toca una vez en la vida alargaría
/// la píldora por nada.
class TextSettingsPanel extends StatelessWidget {
  const TextSettingsPanel({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('Modo de lectura', palette: palette),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ReadingMode.values)
                _Chip(
                  label: Text(mode.label, style: const TextStyle(fontSize: 14)),
                  selected: mode == settings.mode,
                  palette: palette,
                  onTap: () => onChanged(settings.copyWith(mode: mode)),
                ),
            ],
          ),
          // El paso de página sólo aparece en modo paginado: en desplazamiento
          // continuo no hay páginas que pasar, y enseñar un ajuste que no hace
          // nada es peor que no enseñarlo.
          if (settings.mode == ReadingMode.paginado) ...[
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
                    selected: animation == settings.animation,
                    palette: palette,
                    onTap: () =>
                        onChanged(settings.copyWith(animation: animation)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _Label('Fuente', palette: palette),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final font in ReadingFont.values)
                _Chip(
                  // Cada ficha se pinta con su propia tipografía: es la forma
                  // más rápida de elegir, y la única que delata una fuente que
                  // el sistema no tiene y sustituye por otra.
                  label: Text(
                    font.label,
                    style: TextStyle(
                      fontFamily: settings.copyWith(font: font).fontFamily,
                      fontSize: 14,
                    ),
                  ),
                  selected: font == settings.font,
                  palette: palette,
                  onTap: () => onChanged(settings.copyWith(font: font)),
                ),
            ],
          ),
          const SizedBox(height: 22),
          // El tamaño conserva aquí su paso a paso aunque A− y A+ estén en la
          // píldora. No sobra: el atajo es para ajustar sin abrir nada, y este
          // es el único sitio donde se ve el número.
          _Stepper(
            label: 'Tamaño',
            value: '${settings.fontSize.round()}',
            palette: palette,
            // Menos y más en pasos fijos, no un deslizador: con el pulgar sobre
            // una barra de 200 píxeles no hay forma de repetir el mismo valor
            // dos veces, y esto se ajusta una vez y para siempre.
            onLess: settings.fontSize > ReadingSettings.minFontSize
                ? () => onChanged(
                    settings.copyWith(fontSize: settings.fontSize - 1),
                  )
                : null,
            onMore: settings.fontSize < ReadingSettings.maxFontSize
                ? () => onChanged(
                    settings.copyWith(fontSize: settings.fontSize + 1),
                  )
                : null,
          ),
          _Stepper(
            label: 'Interlineado',
            value: settings.lineHeight.toStringAsFixed(1),
            palette: palette,
            onLess: settings.lineHeight > ReadingSettings.minLineHeight
                ? () => onChanged(
                    settings.copyWith(lineHeight: settings.lineHeight - 0.1),
                  )
                : null,
            onMore: settings.lineHeight < ReadingSettings.maxLineHeight
                ? () => onChanged(
                    settings.copyWith(lineHeight: settings.lineHeight + 0.1),
                  )
                : null,
          ),
          _Stepper(
            label: 'Margen',
            value: '${settings.margin.round()}',
            palette: palette,
            onLess: settings.margin > ReadingSettings.minMargin
                ? () =>
                      onChanged(settings.copyWith(margin: settings.margin - 4))
                : null,
            onMore: settings.margin < ReadingSettings.maxMargin
                ? () =>
                      onChanged(settings.copyWith(margin: settings.margin + 4))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Las cuatro superficies de lectura.
class ThemeSettingsPanel extends StatelessWidget {
  const ThemeSettingsPanel({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Tema', palette: settings.palette),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final theme in ReadingTheme.values)
              _ThemeChip(
                theme: theme,
                selected: theme == settings.theme,
                onTap: () => onChanged(settings.copyWith(theme: theme)),
              ),
          ],
        ),
      ],
    );
  }
}

/// El brillo de la pantalla dentro del libro.
///
/// Recibe la paleta en lugar de sacarla de los ajustes porque es el único panel
/// que también usa el lector de cómics, y allí no hay tema de papel que valga:
/// se le pasa una paleta oscura.
class BrightnessPanel extends StatelessWidget {
  const BrightnessPanel({
    required this.settings,
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final ReadingSettings settings;
  final ReadingPalette palette;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final system = settings.usesSystemBrightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
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

/// Hacia dónde se pasa la página en un cómic.
///
/// Es el único ajuste propio del cómic, y no se deduce del fichero porque el
/// fichero no lo dice: un CBZ es un ZIP con imágenes.
class ComicDirectionPanel extends StatelessWidget {
  const ComicDirectionPanel({
    required this.direction,
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final ComicDirection direction;
  final ReadingPalette palette;
  final ValueChanged<ComicDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Sentido de lectura', palette: palette),
        const SizedBox(height: 4),
        Text(
          'Un manga se lee al revés que un cómic occidental, y el fichero no '
          'dice cuál es cuál.',
          style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in ComicDirection.values)
              _Chip(
                label: Text(option.label, style: const TextStyle(fontSize: 14)),
                selected: option == direction,
                palette: palette,
                onTap: () => onChanged(option),
              ),
          ],
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
              color: selected
                  ? palette.text
                  : palette.muted.withValues(alpha: 0.4),
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
              color: selected
                  ? palette.text
                  : palette.muted.withValues(alpha: 0.4),
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
