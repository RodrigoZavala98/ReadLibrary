import 'library_book.dart';
import 'reading_streak.dart';

/// Una insignia del viaje del lector.
///
/// Se llama `Achievement` y no `Badge` **a propósito**: Material exporta un
/// widget llamado `Badge`, y la colisión obligaría a un `import as` en cada
/// pantalla que quisiera pintar una de estas.
///
/// El título y la descripción viven aquí porque son texto, no interfaz. El
/// icono **no**: `IconData` es de Flutter, y `domain/` no lo conoce. Ese mapa
/// está en la pantalla.
enum AchievementKind {
  // --- Arranque ---
  firstStep(
    title: 'Primer paso',
    description: 'Registra tu primer rato de lectura.',
    target: 1,
  ),

  // --- Constancia: la racha más larga del historial ---
  streak3(
    title: 'Tres en raya',
    description: 'Tres días seguidos cumpliendo tu meta.',
    target: 3,
    unit: 'días',
  ),
  streak7(
    title: 'Una semana entera',
    description: 'Siete días seguidos cumpliendo tu meta.',
    target: 7,
    unit: 'días',
  ),
  streak30(
    title: 'Un mes sin fallar',
    description: 'Treinta días seguidos cumpliendo tu meta.',
    target: 30,
    unit: 'días',
  ),

  // --- Tiempo acumulado ---
  hours10(
    title: 'Diez horas',
    description: 'Diez horas de lectura acumuladas.',
    target: 10,
    unit: 'h',
  ),
  hours50(
    title: 'Cincuenta horas',
    description: 'Cincuenta horas de lectura acumuladas.',
    target: 50,
    unit: 'h',
  ),
  hours100(
    title: 'Cien horas',
    description: 'Cien horas de lectura acumuladas.',
    target: 100,
    unit: 'h',
  ),

  // --- De una sentada ---
  marathon(
    title: 'Sin levantar la vista',
    description: 'Una hora de lectura en una sola sesión.',
    target: 60,
    unit: 'min',
  ),

  // --- Horario ---
  earlyBird(
    title: 'Madrugador',
    description: 'Empieza a leer entre las 5:00 y las 7:00.',
    target: 1,
  ),
  nightOwl(
    title: 'Noctámbulo',
    description: 'Empieza a leer entre medianoche y las 4:00.',
    target: 1,
  ),

  // --- Libros terminados ---
  finished1(
    title: 'Punto final',
    description: 'Termina un libro.',
    target: 1,
    unit: 'libros',
  ),
  finished5(
    title: 'Cinco lomos',
    description: 'Termina cinco libros.',
    target: 5,
    unit: 'libros',
  ),
  finished20(
    title: 'Veinte lomos',
    description: 'Termina veinte libros.',
    target: 20,
    unit: 'libros',
  );

  const AchievementKind({
    required this.title,
    required this.description,
    required this.target,
    this.unit,
  });

  final String title;

  /// Cómo se consigue, redactado como instrucción. Se muestra igual estando
  /// bloqueada que conseguida: saber qué hiciste para ganarla es parte de la
  /// recompensa.
  final String description;

  /// Cuánto hace falta, en las unidades de [unit].
  final int target;

  /// Unidad de la cuenta, o `null` si la insignia es de sí o no. Sin unidad no
  /// tiene sentido enseñar «0 / 1»: o has madrugado o no.
  final String? unit;

  bool get isCountable => unit != null;
}

/// Lo conseguido de una insignia concreta.
class AchievementProgress {
  const AchievementProgress({
    required this.kind,
    required this.current,
  }) : assert(current >= 0);

  final AchievementKind kind;

  /// Cuánto se lleva, **topado a la meta**. Que la mejor racha sea de treinta
  /// días no se enseña como «30 / 3 días» en la insignia de tres.
  final int current;

  int get target => kind.target;

  bool get unlocked => current >= target;

  double get ratio => (current / target).clamp(0.0, 1.0);

  /// «4 / 7 días». Vacío en las insignias de sí o no.
  String get countLabel => kind.isCountable ? '$current / $target ${kind.unit}' : '';

  @override
  String toString() => '${kind.name}: $current/$target';
}

abstract final class AchievementCatalog {
  /// Evalúa las trece insignias contra el historial completo.
  ///
  /// Se **derivan** cada vez en lugar de guardarse al desbloquearse. Así no hay
  /// un segundo fichero que pueda quedar a medias ni desincronizarse del
  /// historial, que es la única fuente de verdad. El precio, que conviene tener
  /// presente: borrar de la biblioteca un libro terminado puede volver a
  /// bloquear una insignia, y cambiar un criterio reescribe el pasado.
  static List<AchievementProgress> evaluate({
    required Iterable<ReadingSession> sessions,
    required Iterable<LibraryBook> books,
    required DateTime now,
    required Duration dailyGoal,
    int dayStartHour = 4,
  }) {
    var totalSeconds = 0;
    var longestSessionMinutes = 0;
    var any = false;
    var early = false;
    var night = false;

    for (final session in sessions) {
      any = true;
      totalSeconds += session.duration.inSeconds;
      final minutes = session.duration.inMinutes;
      if (minutes > longestSessionMinutes) longestSessionMinutes = minutes;

      final hour = session.startedAt.hour;
      if (hour >= 5 && hour < 7) early = true;
      // La franja del noctámbulo termina a las 4:00 porque es el corte del día
      // de lectura: quien lee a las tres de la mañana sigue dentro de la
      // jornada anterior. Poner otra frontera aquí contradiría la racha.
      if (hour < dayStartHour) night = true;
    }

    // La familia de constancia se apoya en el cálculo de rachas que ya existe
    // en lugar de recorrer los días por segunda vez.
    final longestStreak = StreakCalculator.compute(
      sessions: sessions,
      now: now,
      dailyGoal: dailyGoal,
      dayStartHour: dayStartHour,
    ).longest;

    final finished = books.where((book) => book.isFinished).length;
    final hours = totalSeconds ~/ 3600;

    AchievementProgress at(AchievementKind kind, int value) =>
        AchievementProgress(kind: kind, current: value.clamp(0, kind.target));

    final all = <AchievementProgress>[
      at(AchievementKind.firstStep, any ? 1 : 0),
      at(AchievementKind.streak3, longestStreak),
      at(AchievementKind.streak7, longestStreak),
      at(AchievementKind.streak30, longestStreak),
      at(AchievementKind.hours10, hours),
      at(AchievementKind.hours50, hours),
      at(AchievementKind.hours100, hours),
      at(AchievementKind.marathon, longestSessionMinutes),
      at(AchievementKind.earlyBird, early ? 1 : 0),
      at(AchievementKind.nightOwl, night ? 1 : 0),
      at(AchievementKind.finished1, finished),
      at(AchievementKind.finished5, finished),
      at(AchievementKind.finished20, finished),
    ];

    // Conseguidas arriba y, entre las pendientes, primero la más cercana: así
    // lo que se ve al bajar es lo que está al alcance, no un muro de bloqueos
    // inalcanzables. El desempate por posición en el catálogo no es estético:
    // `List.sort` no garantiza estabilidad en Dart, y sin él el orden de dos
    // insignias empatadas podría cambiar entre ejecuciones.
    all.sort((a, b) {
      if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
      if (!a.unlocked) {
        final byRatio = b.ratio.compareTo(a.ratio);
        if (byRatio != 0) return byRatio;
      }
      return a.kind.index.compareTo(b.kind.index);
    });

    return all;
  }
}
