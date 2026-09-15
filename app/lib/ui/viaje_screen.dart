import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/theme/app_theme.dart';
import '../domain/achievement.dart';
import '../domain/activity_calendar.dart';
import '../domain/library_book.dart';
import '../domain/reader_profile.dart';
import '../domain/reading_streak.dart';
import 'activity_grid.dart';
import 'duration_label.dart';

/// Mi Viaje: la pantalla de mirar atrás.
///
/// Mi Refugio responde a «¿por dónde iba?». Esta responde a «¿he sido
/// constante?», que es una pregunta que sólo tiene sentido con el historial
/// entero delante: el calendario del mes, las cifras de ese mes, el total de
/// todo lo leído y las insignias.
///
/// Nada de esto se guarda en ningún sitio: todo se deriva de las sesiones y de
/// la biblioteca cada vez que se abre la pantalla.
class ViajeScreen extends StatefulWidget {
  const ViajeScreen({super.key});

  @override
  State<ViajeScreen> createState() => _ViajeScreenState();
}

class _ViajeScreenState extends State<ViajeScreen> {
  ReaderProfile _profile = const ReaderProfile();
  List<ReadingSession> _sessions = const [];
  List<LibraryBook> _books = const [];
  StreakState _streak = StreakState.empty;

  /// Día de lectura en curso, a medianoche. No es la fecha del calendario: a
  /// las tres de la madrugada seguimos dentro del día anterior.
  DateTime _today = DateTime(2000);

  /// Primer día del mes que se está mirando.
  DateTime _visible = DateTime(2000);

  /// Mes de la primera sesión registrada: el tope de la navegación hacia atrás.
  DateTime? _firstMonth;

  DateTime? _selected;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _reload();
  }

  Future<void> _reload() async {
    final services = AppScope.of(context);
    final profile = await services.profile.load();
    final sessions = await services.sessions.loadAll();
    final books = await services.repository.loadAll();

    if (!mounted) return;
    final now = DateTime.now();
    final today = ReadingDay.keyFor(now, dayStartHour: profile.dayStartHour);

    setState(() {
      _profile = profile;
      _sessions = sessions;
      _books = books;
      _streak = StreakCalculator.compute(
        sessions: sessions,
        now: now,
        dailyGoal: _goalOf(profile),
        dayStartHour: profile.dayStartHour,
      );
      _today = today;
      // Se abre por el mes del día de lectura, no por el del calendario: a la
      // una de la madrugada del día 1 todavía estamos cerrando el mes pasado.
      _visible = DateTime(today.year, today.month);
      _firstMonth = _earliestMonth(sessions, profile.dayStartHour);
      _loaded = true;
    });
  }

  static Duration _goalOf(ReaderProfile profile) =>
      Duration(minutes: profile.dailyGoalMinutes);

  static DateTime? _earliestMonth(
    Iterable<ReadingSession> sessions,
    int dayStartHour,
  ) {
    DateTime? earliest;
    for (final session in sessions) {
      final key = ReadingDay.keyFor(
        session.startedAt,
        dayStartHour: dayStartHour,
      );
      if (earliest == null || key.isBefore(earliest)) earliest = key;
    }
    return earliest == null ? null : DateTime(earliest.year, earliest.month);
  }

  /// Se retrocede mientras quede historial por detrás. Sin sesiones no hay nada
  /// que visitar y las dos flechas se apagan.
  bool get _canGoBack => _firstMonth != null && _visible.isAfter(_firstMonth!);

  bool get _canGoForward =>
      _visible.isBefore(DateTime(_today.year, _today.month));

  void _shiftMonth(int months) {
    // La selección no se limpia: guarda día, mes y año, así que no puede
    // confundirse con un día del mes al que se llega, y la línea de abajo
    // vuelve sola a su texto de ayuda. Ponerla a `null` aquí sería código que
    // no se puede observar desde fuera, y por tanto tampoco probar.
    setState(
      () => _visible = DateTime(_visible.year, _visible.month + months),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return ListView(
      // El hueco de abajo deja respirar por encima de la barra de secciones,
      // que flota sobre el contenido en lugar de empujarlo.
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        const _Header(),
        const SizedBox(height: 20),
        if (_sessions.isEmpty)
          const _NothingYet()
        else ...[
          _GlobalSummary(
            sessions: _sessions,
            books: _books,
            streak: _streak,
            dayStartHour: _profile.dayStartHour,
          ),
          const SizedBox(height: 16),
          _MonthCard(
            month: ActivityCalendar.forMonth(
              sessions: _sessions,
              year: _visible.year,
              month: _visible.month,
              goal: _goalOf(_profile),
              dayStartHour: _profile.dayStartHour,
            ),
            today: _today,
            selected: _selected,
            canGoBack: _canGoBack,
            canGoForward: _canGoForward,
            onShift: _shiftMonth,
            onSelect: (day) => setState(() => _selected = day.day),
          ),
          const SizedBox(height: 24),
          _Achievements(
            progress: AchievementCatalog.evaluate(
              sessions: _sessions,
              books: _books,
              now: DateTime.now(),
              dailyGoal: _goalOf(_profile),
              dayStartHour: _profile.dayStartHour,
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mi Viaje',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ChromeTheme.textPrimary,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Tu constancia, mes a mes.',
          style: TextStyle(fontSize: 12, color: ChromeTheme.textMuted),
        ),
      ],
    );
  }
}

/// Lo que se ve antes de haber leído nunca.
///
/// Se prefiere esto a enseñar un calendario en blanco y trece insignias grises:
/// un muro de bloqueos no es una bienvenida, y una cuadrícula vacía no informa
/// de nada que el usuario no sepa ya.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu viaje empieza con el primer rato de lectura',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ChromeTheme.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'En cuanto abras un libro, aquí aparecerán tu calendario de '
            'lectura, tus horas acumuladas y tus insignias.',
            style: TextStyle(height: 1.5, color: ChromeTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _GlobalSummary extends StatelessWidget {
  const _GlobalSummary({
    required this.sessions,
    required this.books,
    required this.streak,
    required this.dayStartHour,
  });

  final List<ReadingSession> sessions;
  final List<LibraryBook> books;
  final StreakState streak;
  final int dayStartHour;

  @override
  Widget build(BuildContext context) {
    var total = Duration.zero;
    final days = <DateTime>{};
    for (final session in sessions) {
      total += session.duration;
      days.add(
        ReadingDay.keyFor(session.startedAt, dayStartHour: dayStartHour),
      );
    }
    final finished = books.where((book) => book.isFinished).length;

    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              _Stat(label: 'Tiempo total', value: formatDuration(total)),
              _Stat(label: 'Días leídos', value: '${days.length}'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(label: 'Libros terminados', value: '$finished'),
              _Stat(
                label: 'Mejor racha',
                value: streak.longest == 1 ? '1 día' : '${streak.longest} días',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.today,
    required this.selected,
    required this.canGoBack,
    required this.canGoForward,
    required this.onShift,
    required this.onSelect,
  });

  final MonthActivity month;
  final DateTime today;
  final DateTime? selected;
  final bool canGoBack;
  final bool canGoForward;
  final ValueChanged<int> onShift;
  final ValueChanged<DayActivity> onSelect;

  bool get _showsToday =>
      today.year == month.year && today.month == month.month;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: canGoBack ? () => onShift(-1) : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Mes anterior',
                color: ChromeTheme.textPrimary,
                disabledColor: ChromeTheme.surfaceHigh,
              ),
              Expanded(
                child: Text(
                  '${monthName(month.month)} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ChromeTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                // Nunca hacia el futuro: un mes que aún no ha ocurrido sólo
                // puede enseñar casillas vacías.
                onPressed: canGoForward ? () => onShift(1) : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Mes siguiente',
                color: ChromeTheme.textPrimary,
                disabledColor: ChromeTheme.surfaceHigh,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ActivityGrid(
            month: month,
            today: _showsToday ? today : null,
            selected: selected,
            onSelect: onSelect,
          ),
          const SizedBox(height: 12),
          const ActivityLegend(),
          const SizedBox(height: 12),
          _SelectedDayLine(month: month, selected: selected),
          const Divider(height: 28, color: ChromeTheme.surfaceHigh),
          if (month.daysWithActivity == 0)
            const Text(
              'Ningún rato de lectura este mes.',
              style: TextStyle(fontSize: 13, color: ChromeTheme.textMuted),
            )
          else
            _MonthStats(month: month),
        ],
      ),
    );
  }
}

/// La línea que dice qué se leyó el día tocado.
///
/// En un móvil no existe el puntero sobre la casilla, así que sin esto la
/// cuadrícula sería puramente decorativa: se vería que un día fue más intenso
/// que otro, pero nunca cuánto.
class _SelectedDayLine extends StatelessWidget {
  const _SelectedDayLine({required this.month, required this.selected});

  final MonthActivity month;
  final DateTime? selected;

  @override
  Widget build(BuildContext context) {
    final chosen = selected;
    final day = chosen == null
        ? null
        : month.days.where((d) => d.day == chosen).firstOrNull;

    if (day == null) {
      return const Text(
        'Toca un día para ver cuánto leíste.',
        style: TextStyle(fontSize: 12, color: ChromeTheme.textMuted),
      );
    }

    return Text(
      '${weekdayName(day.day)} ${day.day.day} · '
      '${day.hasActivity ? formatDuration(day.read) : 'sin lectura'}',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ChromeTheme.accentSoft,
      ),
    );
  }
}

class _MonthStats extends StatelessWidget {
  const _MonthStats({required this.month});

  final MonthActivity month;

  @override
  Widget build(BuildContext context) {
    final best = month.bestDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Stat(label: 'Este mes', value: formatDuration(month.total)),
            _Stat(label: 'Días leídos', value: '${month.daysWithActivity}'),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(label: 'Meta cumplida', value: '${month.daysGoalMet} días'),
            _Stat(
              label: 'Media por día',
              value: formatDuration(month.averagePerActiveDay),
            ),
          ],
        ),
        if (best != null) ...[
          const SizedBox(height: 16),
          Text(
            'Tu mejor día fue el ${best.day.day} de '
            '${monthName(month.month)}, con ${formatDuration(best.read)}.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: ChromeTheme.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _Achievements extends StatelessWidget {
  const _Achievements({required this.progress});

  final List<AchievementProgress> progress;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.where((p) => p.unlocked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Insignias',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ChromeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$unlocked de ${progress.length} conseguidas',
          style: const TextStyle(fontSize: 12, color: ChromeTheme.textMuted),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final p in progress) _AchievementTile(progress: p)],
        ),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.progress});

  final AchievementProgress progress;

  /// El icono se decide aquí y no en el dominio: `IconData` es de Flutter, y
  /// `domain/` no conoce Flutter.
  static IconData _iconFor(AchievementKind kind) => switch (kind) {
    AchievementKind.firstStep => Icons.flag_outlined,
    AchievementKind.streak3 => Icons.local_fire_department_outlined,
    AchievementKind.streak7 => Icons.local_fire_department,
    AchievementKind.streak30 => Icons.whatshot,
    AchievementKind.hours10 => Icons.hourglass_bottom,
    AchievementKind.hours50 => Icons.hourglass_full,
    AchievementKind.hours100 => Icons.schedule,
    AchievementKind.marathon => Icons.self_improvement,
    AchievementKind.earlyBird => Icons.wb_twilight,
    AchievementKind.nightOwl => Icons.nightlight_round,
    AchievementKind.finished1 => Icons.bookmark_added_outlined,
    AchievementKind.finished5 => Icons.auto_stories,
    AchievementKind.finished20 => Icons.library_books,
  };

  @override
  Widget build(BuildContext context) {
    final done = progress.unlocked;
    final tint = done ? ChromeTheme.accentSoft : ChromeTheme.textMuted;

    return Semantics(
      label: done
          ? '${progress.kind.title}, conseguida'
          : '${progress.kind.title}, pendiente. ${progress.kind.description}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ChromeTheme.surface,
          borderRadius: BorderRadius.circular(16),
          // Las conseguidas llevan borde ámbar; las pendientes no se esconden,
          // se enseñan apagadas: una insignia bloqueada de la que no sabes que
          // existe no motiva a nadie.
          border: done
              ? Border.all(color: ChromeTheme.accent, width: 1.5)
              : Border.all(color: ChromeTheme.surfaceHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(progress.kind), size: 22, color: tint),
            const SizedBox(height: 8),
            Text(
              progress.kind.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: done ? ChromeTheme.textPrimary : ChromeTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                progress.kind.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: ChromeTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (done)
              const Text(
                'Conseguida',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ChromeTheme.accentSoft,
                ),
              )
            else if (progress.kind.isCountable) ...[
              Text(
                progress.countLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: ChromeTheme.textMuted,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 3,
                  backgroundColor: ChromeTheme.surfaceHigh,
                  valueColor: const AlwaysStoppedAnimation(ChromeTheme.accent),
                ),
              ),
            ] else
              const Text(
                'Pendiente',
                style: TextStyle(fontSize: 11, color: ChromeTheme.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una cifra con su rótulo. Ocupa media fila.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ChromeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: ChromeTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ChromeTheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}
