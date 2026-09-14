import 'reading_streak.dart';

/// Cronómetro de una sesión de lectura.
///
/// Cuenta **tiempo delante del libro**, no tiempo con el libro abierto. La
/// diferencia importa: si alguien abre una novela, deja el móvil en la mesa y
/// se va a cenar, el contador debe pararse. Si no, la aplicación registraría
/// tres horas de lectura, daría la meta diaria por cumplida y la racha se
/// convertiría en una mentira.
///
/// Quien lo usa llama a [pause] y [resume] siguiendo el ciclo de vida de la
/// aplicación: al pasar a segundo plano o apagarse la pantalla, se para.
///
/// El tiempo se recibe como parámetro en lugar de leerse de `DateTime.now()`
/// para poder probar la clase sin esperar a que pase el rato de verdad.
class ReadingClock {
  DateTime? _startedAt;
  DateTime? _runningSince;
  Duration _accumulated = Duration.zero;

  /// Cuándo empezó la sesión. Determina a qué día de lectura se imputa.
  DateTime? get startedAt => _startedAt;

  bool get isRunning => _runningSince != null;

  void start(DateTime now) {
    _startedAt = now;
    _runningSince = now;
    _accumulated = Duration.zero;
  }

  void pause(DateTime now) {
    final since = _runningSince;
    if (since == null) return;
    _accumulated += _span(since, now);
    _runningSince = null;
  }

  void resume(DateTime now) {
    if (_startedAt == null || _runningSince != null) return;
    _runningSince = now;
  }

  Duration elapsedAt(DateTime now) {
    final since = _runningSince;
    if (since == null) return _accumulated;
    return _accumulated + _span(since, now);
  }

  /// Duración de un tramo, protegida contra saltos del reloj.
  ///
  /// Cambiar la hora del sistema, o cruzar un cambio de horario de verano,
  /// puede hacer que [to] quede antes que [from]. Un tramo negativo restaría
  /// tiempo leído y podría dejar la sesión en cero.
  static Duration _span(DateTime from, DateTime to) {
    final span = to.difference(from);
    return span.isNegative ? Duration.zero : span;
  }

  /// Convierte lo acumulado en una sesión guardable.
  ///
  /// Devuelve `null` si no hay nada que valga la pena registrar: abrir un libro
  /// por error y salir no debería contar para la racha ni ensuciar las
  /// estadísticas.
  ReadingSession? toSession({
    required int bookId,
    required DateTime now,
    Duration minimum = const Duration(seconds: 20),
  }) {
    final started = _startedAt;
    if (started == null) return null;

    final elapsed = elapsedAt(now);
    if (elapsed < minimum) return null;

    return ReadingSession(
      startedAt: started,
      duration: elapsed,
      bookId: bookId,
    );
  }
}
