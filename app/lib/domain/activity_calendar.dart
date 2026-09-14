import 'reading_streak.dart';

/// Intensidad de lectura de un día, para colorear el calendario.
///
/// A diferencia de GitHub, que reparte los tonos según el máximo del propio
/// historial, aquí los niveles se miden **contra la meta diaria del usuario**.
/// La razón es que el criterio relativo engaña: quien un día maratonea seis
/// horas dejaría el resto del año pintado de un gris casi uniforme, como si no
/// hubiera leído. Midiendo contra la meta, el color significa siempre lo mismo
/// —«cumplí», «me quedé corto», «me pasé de largo»— y es comparable entre meses.
enum ActivityLevel {
  /// Ni un minuto.
  none,

  /// Se leyó, pero sin llegar a la meta.
  partial,

  /// Meta cumplida.
  met,

  /// El doble de la meta o más.
  strong,

  /// El triple o más.
  intense;

  static ActivityLevel forDuration(Duration read, Duration goal) {
    if (read <= Duration.zero) return ActivityLevel.none;
    if (goal <= Duration.zero) return ActivityLevel.met;
    final ratio = read.inSeconds / goal.inSeconds;
    if (ratio < 1) return ActivityLevel.partial;
    if (ratio < 2) return ActivityLevel.met;
    if (ratio < 3) return ActivityLevel.strong;
    return ActivityLevel.intense;
  }

  bool get goalMet => index >= ActivityLevel.met.index;
}

/// Un día dentro de la cuadrícula del calendario.
class DayActivity {
  const DayActivity({
    required this.day,
    required this.read,
    required this.level,
  });

  /// Medianoche local del día de lectura.
  final DateTime day;
  final Duration read;
  final ActivityLevel level;

  bool get hasActivity => read > Duration.zero;
}

/// Un mes completo de actividad, ya listo para pintarse como cuadrícula.
class MonthActivity {
  const MonthActivity({
    required this.year,
    required this.month,
    required this.days,
    required this.leadingBlanks,
    required this.goal,
  });

  final int year;
  final int month;

  /// Los días del mes, del 1 al último, en orden.
  final List<DayActivity> days;

  /// Cuántas casillas vacías hay que pintar antes del día 1 para que caiga en
  /// su columna correcta.
  ///
  /// La semana empieza en **lunes**, no en domingo: es la convención en España
  /// y en la mayor parte de Europa, y usar la estadounidense haría que el fin
  /// de semana apareciera partido en dos extremos de la cuadrícula.
  final int leadingBlanks;

  final Duration goal;

  /// Tiempo total leído en el mes.
  Duration get total =>
      days.fold(Duration.zero, (sum, day) => sum + day.read);

  /// Días en los que se leyó algo, aunque fuera poco.
  int get daysWithActivity => days.where((d) => d.hasActivity).length;

  /// Días en los que se cumplió la meta.
  int get daysGoalMet => days.where((d) => d.level.goalMet).length;

  /// Media por día **de los que se leyó**.
  ///
  /// Se calcula así y no sobre los días del mes porque es la cifra que la gente
  /// espera ver: «cuando leo, leo una media de 40 minutos». Dividir entre 30
  /// incluyendo los días en blanco da un número deprimente y poco informativo.
  Duration get averagePerActiveDay {
    final active = daysWithActivity;
    if (active == 0) return Duration.zero;
    return Duration(seconds: total.inSeconds ~/ active);
  }

  /// El día que más se leyó, o `null` si el mes está vacío.
  DayActivity? get bestDay {
    DayActivity? best;
    for (final day in days) {
      if (!day.hasActivity) continue;
      if (best == null || day.read > best.read) best = day;
    }
    return best;
  }
}

abstract final class ActivityCalendar {
  /// Construye la cuadrícula de un mes a partir del historial de sesiones.
  ///
  /// Las sesiones se agrupan por día de lectura, respetando el corte de
  /// [dayStartHour]: lo leído a la 1:00 del día 5 cuenta en la casilla del 4.
  static MonthActivity forMonth({
    required Iterable<ReadingSession> sessions,
    required int year,
    required int month,
    required Duration goal,
    int dayStartHour = 4,
  }) {
    final perDay = <DateTime, Duration>{};
    for (final session in sessions) {
      final key = ReadingDay.keyFor(
        session.startedAt,
        dayStartHour: dayStartHour,
      );
      if (key.year != year || key.month != month) continue;
      perDay[key] = (perDay[key] ?? Duration.zero) + session.duration;
    }

    // El día 0 del mes siguiente es el último del actual: así se resuelven
    // febrero y los años bisiestos sin tabla de longitudes ni casos especiales.
    final dayCount = DateTime(year, month + 1, 0).day;

    final days = <DayActivity>[];
    for (var d = 1; d <= dayCount; d++) {
      final key = DateTime(year, month, d);
      final read = perDay[key] ?? Duration.zero;
      days.add(
        DayActivity(
          day: key,
          read: read,
          level: ActivityLevel.forDuration(read, goal),
        ),
      );
    }

    // weekday: 1 = lunes … 7 = domingo.
    final leadingBlanks = DateTime(year, month, 1).weekday - 1;

    return MonthActivity(
      year: year,
      month: month,
      days: days,
      leadingBlanks: leadingBlanks,
      goal: goal,
    );
  }
}
