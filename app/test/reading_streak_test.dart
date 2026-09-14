import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/reading_streak.dart';

const goal = Duration(minutes: 15);

ReadingSession sesion(DateTime cuando, [int minutos = 20]) =>
    ReadingSession(startedAt: cuando, duration: Duration(minutes: minutos), bookId: 1);

StreakState calcular(List<ReadingSession> sesiones, DateTime ahora) =>
    StreakCalculator.compute(sessions: sesiones, now: ahora, dailyGoal: goal);

void main() {
  // Domingo por la noche.
  final ahora = DateTime(2026, 3, 15, 21, 0);

  group('casos básicos', () {
    test('sin historial no hay racha', () {
      expect(calcular([], ahora).current, 0);
      expect(calcular([], ahora).longest, 0);
    });

    test('leer hoy cumpliendo la meta arranca la racha en 1', () {
      final s = calcular([sesion(DateTime(2026, 3, 15, 20, 0))], ahora);
      expect(s.current, 1);
      expect(s.goalMetToday, isTrue);
      expect(s.isAtRisk, isFalse);
      expect(s.todayProgress, 1.0);
    });

    test('leer hoy sin llegar a la meta no cuenta como día', () {
      final s = calcular([sesion(DateTime(2026, 3, 15, 20, 0), 5)], ahora);
      expect(s.current, 0);
      expect(s.goalMetToday, isFalse);
      expect(s.todayProgress, closeTo(5 / 15, 0.001));
    });

    test('varias sesiones cortas del mismo día suman hasta la meta', () {
      final s = calcular([
        sesion(DateTime(2026, 3, 15, 9, 0), 6),
        sesion(DateTime(2026, 3, 15, 14, 0), 5),
        sesion(DateTime(2026, 3, 15, 20, 0), 4),
      ], ahora);
      expect(s.current, 1, reason: '6+5+4 = 15 minutos, justo la meta');
      expect(s.goalMetToday, isTrue);
    });
  });

  group('continuidad de la racha', () {
    test('tres días seguidos terminando hoy dan 3', () {
      final s = calcular([
        sesion(DateTime(2026, 3, 13, 22, 0)),
        sesion(DateTime(2026, 3, 14, 22, 0)),
        sesion(DateTime(2026, 3, 15, 20, 0)),
      ], ahora);
      expect(s.current, 3);
      expect(s.isAtRisk, isFalse);
    });

    test('no haber leído aún hoy NO rompe la racha, la pone en riesgo', () {
      final s = calcular([
        sesion(DateTime(2026, 3, 13, 22, 0)),
        sesion(DateTime(2026, 3, 14, 22, 0)),
      ], ahora);
      expect(s.current, 2, reason: 'el día todavía no ha terminado');
      expect(s.goalMetToday, isFalse);
      expect(s.isAtRisk, isTrue);
    });

    test('saltarse un día entero sí rompe la racha', () {
      final s = calcular([
        sesion(DateTime(2026, 3, 12, 22, 0)),
        sesion(DateTime(2026, 3, 13, 22, 0)),
      ], ahora);
      expect(s.current, 0, reason: 'el 14 no se leyó');
      expect(s.isAtRisk, isFalse, reason: 'ya no hay nada que salvar');
    });

    test('un día flojo en medio corta la racha', () {
      final s = calcular([
        sesion(DateTime(2026, 3, 13, 22, 0)),
        sesion(DateTime(2026, 3, 14, 22, 0), 3),
        sesion(DateTime(2026, 3, 15, 20, 0)),
      ], ahora);
      expect(s.current, 1, reason: 'sólo cuenta hoy');
    });
  });

  group('el día de lectura empieza a las 4 de la madrugada', () {
    test('leer a la 1:30 cuenta para el día anterior', () {
      // Lunes 1:30. Para el lector es todavía la noche del domingo.
      final lunesDeMadrugada = DateTime(2026, 3, 16, 1, 30);
      final s = calcular([
        sesion(DateTime(2026, 3, 14, 22, 0)),
        sesion(lunesDeMadrugada),
      ], lunesDeMadrugada);
      expect(s.current, 2, reason: 'sábado y domingo, encadenados');
      expect(s.goalMetToday, isTrue);
    });

    test('leer a las 5:00 ya cuenta para el día nuevo', () {
      final lunesTemprano = DateTime(2026, 3, 16, 5, 0);
      final s = calcular([
        sesion(DateTime(2026, 3, 15, 22, 0)),
        sesion(lunesTemprano),
      ], lunesTemprano);
      expect(s.current, 2, reason: 'domingo y lunes');
    });

    test('a medianoche la racha de ayer sigue intacta', () {
      final medianoche = DateTime(2026, 3, 16, 0, 5);
      final s = calcular([sesion(DateTime(2026, 3, 15, 22, 0))], medianoche);
      expect(s.current, 1);
      expect(s.goalMetToday, isTrue, reason: 'las 00:05 aún son el día 15');
    });
  });

  group('fronteras de calendario', () {
    test('la racha cruza el cambio de mes', () {
      final marzo1 = DateTime(2026, 3, 1, 21, 0);
      final s = calcular([
        sesion(DateTime(2026, 2, 27, 21, 0)),
        sesion(DateTime(2026, 2, 28, 21, 0)),
        sesion(DateTime(2026, 3, 1, 20, 0)),
      ], marzo1);
      expect(s.current, 3, reason: 'febrero de 2026 tiene 28 días');
    });

    test('la racha cruza el cambio de año', () {
      final eneroUno = DateTime(2026, 1, 1, 21, 0);
      final s = calcular([
        sesion(DateTime(2025, 12, 30, 21, 0)),
        sesion(DateTime(2025, 12, 31, 21, 0)),
        sesion(DateTime(2026, 1, 1, 20, 0)),
      ], eneroUno);
      expect(s.current, 3);
    });
  });

  group('racha más larga', () {
    test('se conserva aunque la actual sea menor', () {
      final s = calcular([
        // Una tirada de 4 días en enero.
        sesion(DateTime(2026, 1, 5, 21, 0)),
        sesion(DateTime(2026, 1, 6, 21, 0)),
        sesion(DateTime(2026, 1, 7, 21, 0)),
        sesion(DateTime(2026, 1, 8, 21, 0)),
        // Y hoy, suelto.
        sesion(DateTime(2026, 3, 15, 20, 0)),
      ], ahora);
      expect(s.current, 1);
      expect(s.longest, 4);
    });

    test('con un solo día, la más larga es 1', () {
      final s = calcular([sesion(DateTime(2026, 3, 15, 20, 0))], ahora);
      expect(s.longest, 1);
    });

    test('días sueltos no encadenados dan una máxima de 1', () {
      final s = calcular([
        sesion(DateTime(2026, 1, 5, 21, 0)),
        sesion(DateTime(2026, 2, 5, 21, 0)),
        sesion(DateTime(2026, 3, 5, 21, 0)),
      ], ahora);
      expect(s.longest, 1);
      expect(s.current, 0);
    });
  });

  test('una meta de cero no produce una racha infinita', () {
    final s = StreakCalculator.compute(
      sessions: [sesion(DateTime(2026, 3, 15, 20, 0))],
      now: ahora,
      dailyGoal: Duration.zero,
    );
    expect(s.current, 0);
    expect(s.longest, 0);
    expect(s.goalMetToday, isFalse);
    expect(s.todayProgress, 0);
  });
}
