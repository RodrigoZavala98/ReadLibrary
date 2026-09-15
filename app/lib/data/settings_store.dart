import 'dart:convert';
import 'dart:io';

import '../domain/reading_settings.dart';

/// Guarda los ajustes de lectura. Un único objeto, en su propio fichero.
///
/// Va aparte del perfil por la misma razón que el perfil va aparte de la
/// biblioteca: se tocan en momentos distintos. Los ajustes cambian mientras se
/// lee, con el libro abierto; el perfil, dos veces en la vida de la aplicación.
class SettingsStore {
  SettingsStore(this.file);

  final File file;

  ReadingSettings? _cache;

  Future<ReadingSettings> load() async {
    return _cache ??= await _readFromDisk();
  }

  Future<void> save(ReadingSettings settings) async {
    _cache = settings;
    await file.parent.create(recursive: true);

    await file.writeAsString(
      jsonEncode({
        'version': 1,
        // Por nombre y no por posición: añadir un tema en medio de la
        // enumeración renumeraría los de después y cambiaría los ajustes de
        // quien ya tuviera la aplicación instalada.
        'theme': settings.theme.name,
        'font': settings.font.name,
        'fontSize': settings.fontSize,
        'lineHeight': settings.lineHeight,
        'margin': settings.margin,
        if (settings.brightness != null) 'brightness': settings.brightness,
      }),
      flush: true,
    );
  }

  Future<ReadingSettings> _readFromDisk() async {
    if (!await file.exists()) return ReadingSettings();

    final Object? parsed;
    try {
      parsed = jsonDecode(await file.readAsString());
    } on Object {
      // Unos ajustes ilegibles se sustituyen por los de fábrica. Es la pérdida
      // menos grave posible: se vuelven a poner en diez segundos, y el libro se
      // puede leer mientras tanto.
      return ReadingSettings();
    }
    if (parsed is! Map) return ReadingSettings();

    return ReadingSettings(
      theme: _byName(ReadingTheme.values, parsed['theme'], ReadingTheme.claro),
      font: _byName(ReadingFont.values, parsed['font'], ReadingFont.literata),
      fontSize: _number(parsed['fontSize']) ?? 19,
      lineHeight: _number(parsed['lineHeight']) ?? 1.6,
      margin: _number(parsed['margin']) ?? 24,
      brightness: _number(parsed['brightness']),
    );
  }

  /// Busca un valor de enumeración por su nombre.
  ///
  /// Un nombre desconocido cae al de por defecto en lugar de fallar: puede
  /// venir de una versión posterior de la aplicación —alguien que instaló una
  /// más nueva y volvió atrás— o de un fichero manipulado.
  static T _byName<T extends Enum>(List<T> values, Object? raw, T fallback) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }

  static double? _number(Object? raw) {
    if (raw is num) {
      final value = raw.toDouble();
      return value.isFinite ? value : null;
    }
    return null;
  }
}
