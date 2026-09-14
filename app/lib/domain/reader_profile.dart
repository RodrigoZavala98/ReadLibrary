/// El perfil del lector. Vive **sólo** en este dispositivo.
///
/// No hay cuenta, ni registro, ni sincronización, ni identificador que viaje a
/// ningún servidor. El nombre existe para dos cosas: personalizar la cabecera
/// («La biblioteca de Aria») y poder redactar notificaciones que suenen a algo
/// dirigido a una persona y no a un usuario anónimo.
///
/// Esa restricción es deliberada y conviene no erosionarla más adelante: en
/// cuanto este nombre se envíe a cualquier parte, la aplicación pasa a tratar
/// datos personales y arrastra consigo consentimiento, política de privacidad y
/// el formulario de seguridad de datos de Google Play.
class ReaderProfile {
  const ReaderProfile({
    this.displayName,
    this.accentSeed = 0,
    this.dailyGoalMinutes = 15,
    this.reminder,
    this.dayStartHour = 4,
  });

  /// Cómo quiere que le llamen. `null` si prefirió no decirlo.
  ///
  /// Es opcional a propósito: pedir un nombre obligatorio antes de dejar leer
  /// es fricción pura en una aplicación que funciona perfectamente sin él.
  /// Cuando es `null`, la interfaz usa fórmulas impersonales.
  final String? displayName;

  /// Semilla para el color del avatar, derivado del nombre. Evita pedir
  /// permiso de cámara o galería para algo puramente decorativo.
  final int accentSeed;

  /// Meta diaria en minutos. Alimenta la racha.
  final int dailyGoalMinutes;

  /// A qué hora recordar la lectura. `null` si no quiere avisos.
  final ReminderTime? reminder;

  /// A qué hora empieza un «día de lectura», en hora local.
  ///
  /// No son las 00:00. Mucha gente lee justo antes de dormir, y quien termina
  /// su capítulo a la una de la madrugada del martes considera —con razón— que
  /// ha leído el lunes. Cortar a medianoche le rompería la racha por un rato
  /// de lectura que para esa persona pertenece al día anterior.
  final int dayStartHour;

  bool get hasName => displayName != null && displayName!.trim().isNotEmpty;

  /// Saludo para la cabecera.
  String greeting() => hasName ? 'La biblioteca de ${displayName!.trim()}' : 'Tu biblioteca';

  ReaderProfile copyWith({
    String? displayName,
    int? accentSeed,
    int? dailyGoalMinutes,
    ReminderTime? reminder,
    bool clearReminder = false,
    int? dayStartHour,
  }) {
    return ReaderProfile(
      displayName: displayName ?? this.displayName,
      accentSeed: accentSeed ?? this.accentSeed,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
      reminder: clearReminder ? null : (reminder ?? this.reminder),
      dayStartHour: dayStartHour ?? this.dayStartHour,
    );
  }
}

/// Hora del día para el recordatorio, sin fecha asociada.
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
