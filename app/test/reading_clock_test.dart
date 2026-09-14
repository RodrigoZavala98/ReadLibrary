import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/reading_clock.dart';

void main() {
  final t0 = DateTime(2026, 3, 15, 20, 0);
  DateTime enMinuto(int m) => t0.add(Duration(minutes: m));

  test('sin arrancar no hay nada que contar', () {
    final clock = ReadingClock();
    expect(clock.elapsedAt(t0), Duration.zero);
    expect(clock.startedAt, isNull);
    expect(clock.toSession(bookId: 1, now: t0), isNull);
  });

  test('cuenta el tiempo transcurrido', () {
    final clock = ReadingClock()..start(t0);
    expect(clock.elapsedAt(enMinuto(25)), const Duration(minutes: 25));
    expect(clock.startedAt, t0);
  });

  group('pausas', () {
    test('el tiempo en segundo plano no se cuenta', () {
      final clock = ReadingClock()..start(t0);
      clock.pause(enMinuto(10)); // se va a cenar
      clock.resume(enMinuto(70)); // vuelve una hora después

      expect(
        clock.elapsedAt(enMinuto(75)),
        const Duration(minutes: 15),
        reason: '10 antes de irse y 5 después de volver',
      );
    });

    test('mientras está en pausa el contador no avanza', () {
      final clock = ReadingClock()..start(t0);
      clock.pause(enMinuto(10));

      expect(clock.elapsedAt(enMinuto(60)), const Duration(minutes: 10));
      expect(clock.isRunning, isFalse);
    });

    test('varias pausas se acumulan bien', () {
      final clock = ReadingClock()..start(t0);
      clock.pause(enMinuto(5));
      clock.resume(enMinuto(20));
      clock.pause(enMinuto(25));
      clock.resume(enMinuto(100));

      expect(clock.elapsedAt(enMinuto(110)), const Duration(minutes: 20));
    });

    test('pausar dos veces seguidas no descuadra el total', () {
      final clock = ReadingClock()..start(t0);
      clock.pause(enMinuto(10));
      clock.pause(enMinuto(30));

      expect(clock.elapsedAt(enMinuto(40)), const Duration(minutes: 10));
    });

    test('reanudar sin haber pausado no duplica el tiempo', () {
      final clock = ReadingClock()..start(t0);
      clock.resume(enMinuto(10));

      expect(clock.elapsedAt(enMinuto(20)), const Duration(minutes: 20));
    });
  });

  test('un salto del reloj hacia atrás no resta tiempo leído', () {
    // Cambiar la hora del sistema o el horario de verano pueden provocarlo.
    final clock = ReadingClock()..start(t0);
    clock.pause(t0.subtract(const Duration(hours: 1)));

    expect(clock.elapsedAt(t0), Duration.zero, reason: 'nunca negativo');
  });

  group('conversión a sesión', () {
    test('una lectura de verdad se registra', () {
      final clock = ReadingClock()..start(t0);
      final session = clock.toSession(bookId: 7, now: enMinuto(18));

      expect(session, isNotNull);
      expect(session!.bookId, 7);
      expect(session.startedAt, t0);
      expect(session.duration, const Duration(minutes: 18));
    });

    test('abrir un libro por error y salir no cuenta', () {
      final clock = ReadingClock()..start(t0);
      final session = clock.toSession(
        bookId: 1,
        now: t0.add(const Duration(seconds: 3)),
      );
      expect(session, isNull);
    });

    test('la sesión se imputa al momento en que empezó, no al de cierre', () {
      // Se empieza a leer a las 23:50 y se cierra a las 00:30. La sesión
      // pertenece al día anterior, y de eso se encarga startedAt.
      final nocturno = DateTime(2026, 3, 15, 23, 50);
      final clock = ReadingClock()..start(nocturno);
      final session = clock.toSession(
        bookId: 1,
        now: DateTime(2026, 3, 16, 0, 30),
      );

      expect(session!.startedAt.day, 15);
      expect(session.duration, const Duration(minutes: 40));
    });
  });
}
