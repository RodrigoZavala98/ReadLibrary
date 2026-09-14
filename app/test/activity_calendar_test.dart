import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/activity_calendar.dart';
import 'package:lector/domain/reading_streak.dart';

const meta = Duration(minutes: 15);

ReadingSession sesion(DateTime cuando, int minutos) =>
    ReadingSession(startedAt: cuando, duration: Duration(minutes: minutos), bookId: 1);

MonthActivity mes(List<ReadingSession> sesiones, int year, int month) =>
    ActivityCalendar.forMonth(
      sessions: sesiones,
      year: year,
      month: month,
      goal: meta,
    );

void main() {
  group('forma de la cuadrícula', () {
    test('cada mes tiene el número de días que le toca', () {
      expect(mes([], 2026, 1).days.length, 31);
      expect(mes([], 2026, 4).days.length, 30);
      expect(mes([], 2026, 2).days.length, 28);
    });

    test('febrero de un año bisiesto tiene 29', () {
      expect(mes([], 2028, 2).days.length, 29);
    });

    test('los huecos iniciales alinean el día 1 con su columna', () {
      // El 1 de marzo de 2026 cae en domingo: con la semana empezando en
      // lunes, quedan seis casillas vacías por delante.
      expect(mes([], 2026, 3).leadingBlanks, 6);
    });

    test('un mes que empieza en lunes no tiene huecos', () {
      // 1 de junio de 2026, lunes.
      expect(mes([], 2026, 6).leadingBlanks, 0);
    });

    test('un mes vacío no tiene actividad alguna', () {
      final m = mes([], 2026, 3);
      expect(m.total, Duration.zero);
      expect(m.daysWithActivity, 0);
      expect(m.bestDay, isNull);
      expect(m.averagePerActiveDay, Duration.zero);
      expect(m.days.every((d) => d.level == ActivityLevel.none), isTrue);
    });
  });

  group('niveles de intensidad medidos contra la meta', () {
    test('cada tramo cae en su nivel', () {
      final m = mes([
        sesion(DateTime(2026, 3, 2, 20), 7), // por debajo de la meta
        sesion(DateTime(2026, 3, 3, 20), 15), // justo la meta
        sesion(DateTime(2026, 3, 4, 20), 35), // más del doble
        sesion(DateTime(2026, 3, 5, 20), 90), // seis veces
      ], 2026, 3);

      expect(m.days[1].level, ActivityLevel.partial);
      expect(m.days[2].level, ActivityLevel.met);
      expect(m.days[3].level, ActivityLevel.strong);
      expect(m.days[4].level, ActivityLevel.intense);
    });

    test('sólo cuentan como meta cumplida los niveles altos', () {
      expect(ActivityLevel.none.goalMet, isFalse);
      expect(ActivityLevel.partial.goalMet, isFalse);
      expect(ActivityLevel.met.goalMet, isTrue);
      expect(ActivityLevel.intense.goalMet, isTrue);
    });

    test('varias sesiones del mismo día se suman antes de decidir el nivel', () {
      final m = mes([
        sesion(DateTime(2026, 3, 10, 9), 8),
        sesion(DateTime(2026, 3, 10, 22), 9),
      ], 2026, 3);
      expect(m.days[9].read, const Duration(minutes: 17));
      expect(m.days[9].level, ActivityLevel.met);
    });
  });

  group('el corte de las 4 de la madrugada también aplica al calendario', () {
    test('leer a la 1:00 del día 5 pinta la casilla del día 4', () {
      final m = mes([sesion(DateTime(2026, 3, 5, 1, 0), 30)], 2026, 3);
      expect(m.days[3].hasActivity, isTrue, reason: 'día 4');
      expect(m.days[4].hasActivity, isFalse, reason: 'día 5');
    });

    test('leer a la 1:00 del día 1 pertenece al mes anterior', () {
      final m = mes([sesion(DateTime(2026, 3, 1, 1, 0), 30)], 2026, 3);
      expect(m.daysWithActivity, 0, reason: 'esa lectura es del 28 de febrero');

      final febrero = mes([sesion(DateTime(2026, 3, 1, 1, 0), 30)], 2026, 2);
      expect(febrero.days.last.hasActivity, isTrue);
    });
  });

  group('métricas del mes', () {
    final sesiones = [
      sesion(DateTime(2026, 3, 2, 20), 10),
      sesion(DateTime(2026, 3, 3, 20), 20),
      sesion(DateTime(2026, 3, 4, 20), 60),
    ];

    test('suma el tiempo total', () {
      expect(mes(sesiones, 2026, 3).total, const Duration(minutes: 90));
    });

    test('distingue días leídos de días con la meta cumplida', () {
      final m = mes(sesiones, 2026, 3);
      expect(m.daysWithActivity, 3);
      expect(m.daysGoalMet, 2, reason: 'los 10 minutos no llegan a la meta');
    });

    test('la media se calcula sobre los días leídos, no sobre los 31', () {
      expect(
        mes(sesiones, 2026, 3).averagePerActiveDay,
        const Duration(minutes: 30),
      );
    });

    test('encuentra el mejor día', () {
      final mejor = mes(sesiones, 2026, 3).bestDay;
      expect(mejor, isNotNull);
      expect(mejor!.day.day, 4);
      expect(mejor.read, const Duration(minutes: 60));
    });

    test('las sesiones de otros meses se ignoran', () {
      final m = mes([
        sesion(DateTime(2026, 2, 20, 20), 60),
        sesion(DateTime(2026, 4, 2, 20), 60),
        sesion(DateTime(2026, 3, 15, 20), 25),
      ], 2026, 3);
      expect(m.total, const Duration(minutes: 25));
      expect(m.daysWithActivity, 1);
    });
  });
}
