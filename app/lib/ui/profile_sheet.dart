import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/reader_profile.dart';

/// Ajustes del perfil. Devuelve el perfil modificado, o `null` si se cancela.
Future<ReaderProfile?> showProfileSheet(
  BuildContext context,
  ReaderProfile current,
) {
  return showModalBottomSheet<ReaderProfile>(
    context: context,
    backgroundColor: ChromeTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ProfileSheet(current: current),
  );
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.current});

  final ReaderProfile current;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final _name = TextEditingController(
    text: widget.current.displayName ?? '',
  );
  late int _goal = widget.current.dailyGoalMinutes;

  /// Opciones cerradas en lugar de un campo libre: elegir entre cinco valores
  /// razonables es más rápido que teclear, y evita metas absurdas como cero
  /// minutos —que daría cualquier día por cumplido— o seiscientos.
  static const _goals = [5, 10, 15, 30, 60];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final typed = _name.text.trim();
    Navigator.of(context).pop(
      widget.current.copyWith(
        displayName: typed.isEmpty ? null : typed,
        dailyGoalMinutes: _goal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Deja sitio al teclado: sin esto tapa el botón de guardar.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu perfil',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ChromeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Todo esto se queda en este teléfono. No hay cuenta ni se envía '
            'nada a ningún sitio.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: ChromeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: const TextStyle(color: ChromeTheme.textPrimary),
            decoration: InputDecoration(
              labelText: '¿Cómo quieres que te llame?',
              helperText: 'Puedes dejarlo en blanco',
              labelStyle: const TextStyle(color: ChromeTheme.textMuted),
              helperStyle: const TextStyle(
                color: ChromeTheme.textMuted,
                fontSize: 11,
              ),
              filled: true,
              fillColor: ChromeTheme.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Meta diaria',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ChromeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final minutes in _goals)
                ChoiceChip(
                  label: Text('$minutes min'),
                  selected: _goal == minutes,
                  onSelected: (_) => setState(() => _goal = minutes),
                  showCheckmark: false,
                  backgroundColor: ChromeTheme.surfaceHigh,
                  selectedColor: ChromeTheme.accent,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _goal == minutes
                        ? Colors.white
                        : ChromeTheme.textMuted,
                  ),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: ChromeTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}
