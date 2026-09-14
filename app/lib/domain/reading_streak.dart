/// Un rato de lectura registrado. Es la unidad con la que se construyen las
/// rachas y las estadísticas.
class ReadingSession {
  const ReadingSession({
    required this.startedAt,
    required this.duration,
    required this.bookId,
  });

  /// Momento local en que empezó la sesión.
  final DateTime startedAt;
  final Duration duration;
  final int bookId;
}

/// Conversión entre instantes y «días de lectura».
abstract final class ReadingDay {
  /// A qué día de lectura pertenece [instant].
  ///
  /// No se corta a medianoche sino a [dayStartHour] (por defecto, las 4 de la
  /// madrugada). Quien cierra el libro a la 1:30 de un martes está terminando
  /// su lunes, y cortar a las 00:00 le rompería la racha injustamente.
  ///
  /// El resultado es siempre medianoche local del día que corresponde, para
  /// poder usarse como clave.
  static DateTime keyFor(DateTime instant, {required int dayStartHour}) {
    final shifted = instant.subtract(Duration(hours: dayStartHour));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  /// El día de lectura anterior a [dayKey].
  ///
  /// Se construye con aritmética de calendario —`day - 1`, que Dart normaliza
  /// solo— y no restando 24 horas. Restar una duración se rompe en los cambios
  /// de hora: la noche en que el reloj se adelanta sólo tiene 23 horas, y
  /// restar 24 aterrizaría en el día equivocado.
  static DateTime previous(DateTime dayKey) =>
      DateTime(dayKey.year, dayKey.month, dayKey.day - 1);
}

/// Estado de la racha, tal y como lo pinta la interfaz.
class StreakState {
  const StreakState({
    required this.current,
    required this.longest,
    required this.goalMetToday,
    required this.todayProgress,
  });

  /// Días consecutivos cumpliendo la meta.
  final int current;

  /// La racha más larga jamás alcanzada. No se pierde nunca.
  final int longest;

  final bool goalMetToday;

  /// Avance de hoy sobre la meta, entre 0 y 1, para el anillo de la cabecera.
  final double todayProgress;

  /// La racha sigue viva pero hoy aún no se ha cumplido la meta.
  ///
  /// Es el único momento en que tiene sentido avisar al usuario: ni cuando ya
  /// ha leído hoy, ni cuando la racha ya está rota y no hay nada que salvar.
  bool get isAtRisk => current > 0 && !goalMetToday;

  static const empty = StreakState(
    current: 0,
    longest: 0,
    goalMetToday: false,
    todayProgress: 0,
  );
}

abstract final class StreakCalculator {
  /// Calcula la racha a partir del historial completo de sesiones.
  ///
  /// Una sesión se imputa entera al día en que **empezó**, aunque cruce el
  /// corte. Es lo que espera el usuario: una sesión larga es «la lectura de
  /// anoche», no media hora repartida entre dos días.
  static StreakState compute({
    required Iterable<ReadingSession> sessions,
    required DateTime now,
    required Duration dailyGoal,
    int dayStartHour = 4,
  }) {
    if (dailyGoal <= Duration.zero) return StreakState.empty;

    // Minutos leídos por día.
    final perDay = <DateTime, Duration>{};
    for (final session in sessions) {
      final key = ReadingDay.keyFor(
        session.startedAt,
        dayStartHour: dayStartHour,
      );
      perDay[key] = (perDay[key] ?? Duration.zero) + session.duration;
    }

    final qualifying = {
      for (final entry in perDay.entries)
        if (entry.value >= dailyGoal) entry.key,
    };

    final today = ReadingDay.keyFor(now, dayStartHour: dayStartHour);
    final readToday = perDay[today] ?? Duration.zero;
    final goalMetToday = qualifying.contains(today);

    // La racha se cuenta hacia atrás desde hoy si hoy ya cuenta, y si no desde
    // ayer: no haber leído todavía hoy no rompe la racha, sólo la pone en
    // riesgo hasta que termine el día.
    var cursor = goalMetToday ? today : ReadingDay.previous(today);
    var current = 0;
    while (qualifying.contains(cursor)) {
      current++;
      cursor = ReadingDay.previous(cursor);
    }

    return StreakState(
      current: current,
      longest: _longestRun(qualifying, current),
      goalMetToday: goalMetToday,
      todayProgress: (readToday.inSeconds / dailyGoal.inSeconds).clamp(0.0, 1.0),
    );
  }

  /// La tirada consecutiva más larga del historial.
  static int _longestRun(Set<DateTime> qualifying, int current) {
    if (qualifying.isEmpty) return 0;

    final ordered = qualifying.toList()..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < ordered.length; i++) {
      final expected = DateTime(
        ordered[i - 1].year,
        ordered[i - 1].month,
        ordered[i - 1].day + 1,
      );
      if (ordered[i] == expected) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
    }
    return longest > current ? longest : current;
  }
}
