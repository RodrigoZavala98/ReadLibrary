import 'dart:convert';
import 'dart:io';

import '../domain/reader_profile.dart';

/// Guarda el perfil del lector. Un único objeto, en su propio fichero.
///
/// Va aparte de la biblioteca porque cambia con muchísima menos frecuencia:
/// mezclarlo obligaría a reescribir todo el índice de libros cada vez que
/// alguien ajusta su meta diaria.
class ProfileStore {
  ProfileStore(this.file);

  final File file;

  ReaderProfile? _cache;

  Future<ReaderProfile> load() async {
    return _cache ??= await _readFromDisk();
  }

  Future<void> save(ReaderProfile profile) async {
    _cache = profile;
    await file.parent.create(recursive: true);

    await file.writeAsString(
      jsonEncode({
        'version': 1,
        if (profile.displayName != null) 'displayName': profile.displayName,
        'accentSeed': profile.accentSeed,
        'dailyGoalMinutes': profile.dailyGoalMinutes,
        'dayStartHour': profile.dayStartHour,
        if (profile.reminder != null)
          'reminder': {
            'hour': profile.reminder!.hour,
            'minute': profile.reminder!.minute,
          },
      }),
      flush: true,
    );
  }

  Future<ReaderProfile> _readFromDisk() async {
    if (!await file.exists()) return const ReaderProfile();

    final Object? parsed;
    try {
      parsed = jsonDecode(await file.readAsString());
    } on Object {
      // Un perfil ilegible se sustituye por el de fábrica. Es la pérdida menos
      // grave posible: un nombre y una meta se vuelven a poner en diez segundos.
      return const ReaderProfile();
    }
    if (parsed is! Map) return const ReaderProfile();

    final name = parsed['displayName'];
    final goal = parsed['dailyGoalMinutes'];
    final dayStart = parsed['dayStartHour'];

    return ReaderProfile(
      displayName: name is String && name.trim().isNotEmpty ? name : null,
      accentSeed: parsed['accentSeed'] is int ? parsed['accentSeed'] as int : 0,
      // Una meta de cero haría que cualquier día contase como cumplido y la
      // racha dejaría de significar nada.
      dailyGoalMinutes: goal is int && goal > 0 ? goal : 15,
      dayStartHour: dayStart is int && dayStart >= 0 && dayStart < 24
          ? dayStart
          : 4,
      reminder: _readReminder(parsed['reminder']),
    );
  }

  static ReminderTime? _readReminder(Object? raw) {
    if (raw is! Map) return null;
    final hour = raw['hour'];
    final minute = raw['minute'];
    if (hour is! int || minute is! int) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return ReminderTime(hour, minute);
  }
}
