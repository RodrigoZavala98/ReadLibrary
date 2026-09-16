import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/theme/app_theme.dart';
import '../domain/library_book.dart';
import '../domain/reader_profile.dart';
import '../domain/reading_streak.dart';
import 'profile_sheet.dart';
import 'open_book.dart';
import 'streak_ring.dart';

/// Mi Refugio: la pantalla de volver.
///
/// Responde a dos preguntas y nada más: «¿sigo en racha?» y «¿por dónde iba?».
/// Todo lo demás —estadísticas, logros, calendario— vive en Mi Viaje. Si esta
/// pantalla crece, deja de ser un refugio.
class RefugioScreen extends StatefulWidget {
  const RefugioScreen({super.key});

  @override
  State<RefugioScreen> createState() => _RefugioScreenState();
}

class _RefugioScreenState extends State<RefugioScreen> {
  ReaderProfile _profile = const ReaderProfile();
  StreakState _streak = StreakState.empty;
  LibraryBook? _continueWith;
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
    setState(() {
      _profile = profile;
      _streak = StreakCalculator.compute(
        sessions: sessions,
        now: DateTime.now(),
        dailyGoal: Duration(minutes: profile.dailyGoalMinutes),
        dayStartHour: profile.dayStartHour,
      );
      // El primero de la lista es el último abierto; si no se ha abierto
      // ninguno todavía, no se ofrece «continuar».
      _continueWith = books.where((b) => b.lastOpenedAt != null).firstOrNull;
      _loaded = true;
    });
  }

  Future<void> _openProfile() async {
    final updated = await showProfileSheet(context, _profile);
    if (updated == null || !mounted) return;
    await AppScope.of(context).profile.save(updated);
    await _reload();
  }

  Future<void> _continue() async {
    final book = _continueWith;
    if (book == null) return;
    await openBook(context, book);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        _Header(profile: _profile, onTap: _openProfile),
        const SizedBox(height: 24),
        _StreakCard(streak: _streak, goalMinutes: _profile.dailyGoalMinutes),
        const SizedBox(height: 16),
        if (_continueWith case final book?)
          _ContinueCard(book: book, onTap: _continue)
        else
          const _NothingStarted(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onTap});

  final ReaderProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bienvenido de vuelta',
                style: TextStyle(fontSize: 12, color: ChromeTheme.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                profile.greeting(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ChromeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        _Avatar(profile: profile, onTap: onTap),
      ],
    );
  }
}

/// El avatar es la puerta a los ajustes. No hay pestaña de perfil: un nombre y
/// tres opciones no justifican un destino de navegación propio.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.onTap});

  final ReaderProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayName?.trim() ?? '';
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Semantics(
      button: true,
      label: 'Ajustes de tu perfil',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: ChromeTheme.accentGradient,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak, required this.goalMinutes});

  final StreakState streak;
  final int goalMinutes;

  String get _message {
    if (streak.goalMetToday) {
      return streak.current == 1
          ? 'Meta cumplida. Empieza la racha.'
          : 'Meta cumplida. Van ${streak.current} días seguidos.';
    }
    if (streak.isAtRisk) {
      return streak.current == 1
          ? 'Lee hoy para no perder tu racha.'
          : 'Lee hoy y mantendrás ${streak.current} días de racha.';
    }
    return 'Lee $goalMinutes minutos hoy y arrancas una racha.';
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          StreakRing(
            days: streak.current,
            todayProgress: streak.todayProgress,
            atRisk: streak.isAtRisk,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _message,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: ChromeTheme.textPrimary,
                  ),
                ),
                if (streak.longest > streak.current) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tu mejor racha: ${streak.longest} días',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ChromeTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Card(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTINUAR LEYENDO',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: ChromeTheme.accentSoft,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ChromeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: book.progress,
              minHeight: 5,
              backgroundColor: ChromeTheme.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(ChromeTheme.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(book.progress * 100).round()} % leído',
            style: const TextStyle(fontSize: 11, color: ChromeTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NothingStarted extends StatelessWidget {
  const _NothingStarted();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      child: Text(
        'Todavía no has empezado ningún libro.\n'
        'Añade uno desde Mi Biblioteca.',
        style: TextStyle(color: ChromeTheme.textMuted, height: 1.5),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ChromeTheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}
