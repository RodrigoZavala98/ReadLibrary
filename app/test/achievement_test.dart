import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/achievement.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reading_streak.dart';

const meta = Duration(minutes: 15);

/// Un instante fijo: las insignias se evalúan contra el historial, no contra el
/// reloj de la máquina, y la prueba tiene que valer igual en local que en la
/// integración continua.
final ahora = DateTime(2026, 3, 15, 20);

ReadingSession sesion(DateTime cuando, int minutos) => ReadingSession(
  startedAt: cuando,
  duration: Duration(minutes: minutos),
  bookId: 1,
);

LibraryBook libro(int id, {double progress = 0}) => LibraryBook(
  id: id,
  filePath: '/libros/$id.txt',
  format: BookFormat.txt,
  title: 'Libro $id',
  addedAt: DateTime(2026, 1, 1),
  progress: progress,
);

List<AchievementProgress> evaluar({
  List<ReadingSession> sesiones = const [],
  List<LibraryBook> libros = const [],
}) => AchievementCatalog.evaluate(
  sessions: sesiones,
  books: libros,
  now: ahora,
  dailyGoal: meta,
);

AchievementProgress de(
  List<AchievementProgress> todas,
  AchievementKind cual,
) => todas.firstWhere((p) => p.kind == cual);

/// Días consecutivos cumpliendo la meta, terminando en [ultimo].
List<ReadingSession> racha(int dias, {DateTime? ultimo}) {
  final fin = ultimo ?? DateTime(2026, 3, 10, 20);
  return [
    for (var i = 0; i < dias; i++)
      sesion(DateTime(fin.year, fin.month, fin.day - i, 20), 20),
  ];
}

void main() {
  test('sin historial no hay ninguna insignia conseguida', () {
    final todas = evaluar();
    expect(todas.length, AchievementKind.values.length);
    expect(todas.every((p) => !p.unlocked), isTrue);
  });

  group('arranque', () {
    test('la primera sesión desbloquea el primer paso', () {
      expect(de(evaluar(sesiones: [sesion(ahora, 3)]), AchievementKind.firstStep).unlocked, isTrue);
    });

    test('una sesión cortísima también cuenta: haber empezado es el logro', () {
      // No se le exige la meta diaria a propósito. Esta insignia premia abrir
      // un libro por primera vez, no leer bien.
      expect(de(evaluar(sesiones: [sesion(ahora, 1)]), AchievementKind.firstStep).unlocked, isTrue);
    });
  });

  group('constancia', () {
    test('tres días seguidos desbloquean la de tres y no la de siete', () {
      final todas = evaluar(sesiones: racha(3));
      expect(de(todas, AchievementKind.streak3).unlocked, isTrue);
      expect(de(todas, AchievementKind.streak7).unlocked, isFalse);
      expect(de(todas, AchievementKind.streak7).countLabel, '3 / 7 días');
    });

    test('dos días no bastan para la de tres', () {
      expect(de(evaluar(sesiones: racha(2)), AchievementKind.streak3).unlocked, isFalse);
    });

    test('la racha rota no cuenta como seguida', () {
      final sesiones = [
        sesion(DateTime(2026, 3, 1, 20), 20),
        sesion(DateTime(2026, 3, 2, 20), 20),
        // falta el 3
        sesion(DateTime(2026, 3, 4, 20), 20),
      ];
      expect(de(evaluar(sesiones: sesiones), AchievementKind.streak3).unlocked, isFalse);
    });

    test('un día por debajo de la meta parte la racha', () {
      final sesiones = [
        sesion(DateTime(2026, 3, 1, 20), 20),
        sesion(DateTime(2026, 3, 2, 20), 5),
        sesion(DateTime(2026, 3, 3, 20), 20),
      ];
      expect(de(evaluar(sesiones: sesiones), AchievementKind.streak3).unlocked, isFalse);
    });

    test('la cuenta se topa a la meta de cada insignia', () {
      // Con treinta días encadenados, la insignia de tres no dice «30 / 3».
      final todas = evaluar(sesiones: racha(30));
      expect(de(todas, AchievementKind.streak3).current, 3);
      expect(de(todas, AchievementKind.streak30).unlocked, isTrue);
    });
  });

  group('tiempo acumulado', () {
    test('diez horas justas desbloquean la insignia', () {
      final sesiones = [
        for (var i = 0; i < 10; i++) sesion(DateTime(2026, 2, i + 1, 20), 60),
      ];
      expect(de(evaluar(sesiones: sesiones), AchievementKind.hours10).unlocked, isTrue);
    });

    test('un minuto por debajo todavía no', () {
      final sesiones = [
        for (var i = 0; i < 9; i++) sesion(DateTime(2026, 2, i + 1, 20), 60),
        sesion(DateTime(2026, 2, 10, 20), 59),
      ];
      final todas = evaluar(sesiones: sesiones);
      expect(de(todas, AchievementKind.hours10).unlocked, isFalse);
      expect(de(todas, AchievementKind.hours10).countLabel, '9 / 10 h');
    });

    test('las horas suman aunque los ratos sean cortos', () {
      final sesiones = [
        for (var i = 0; i < 60; i++) sesion(DateTime(2026, 2, 1, 8, i * 10), 10),
      ];
      expect(de(evaluar(sesiones: sesiones), AchievementKind.hours10).unlocked, isTrue);
    });
  });

  group('de una sentada', () {
    test('una hora seguida desbloquea el maratón', () {
      expect(de(evaluar(sesiones: [sesion(ahora, 60)]), AchievementKind.marathon).unlocked, isTrue);
    });

    test('cincuenta y nueve minutos no', () {
      expect(de(evaluar(sesiones: [sesion(ahora, 59)]), AchievementKind.marathon).unlocked, isFalse);
    });

    test('dos ratos de media hora el mismo día no son una sentada', () {
      // Es justo lo que la insignia premia: no levantar la vista. Sumar dos
      // sesiones sueltas la convertiría en otra insignia de tiempo acumulado.
      final sesiones = [
        sesion(DateTime(2026, 3, 10, 9), 30),
        sesion(DateTime(2026, 3, 10, 22), 30),
      ];
      expect(de(evaluar(sesiones: sesiones), AchievementKind.marathon).unlocked, isFalse);
    });
  });

  group('horario', () {
    test('a las cinco de la mañana es madrugar', () {
      final todas = evaluar(sesiones: [sesion(DateTime(2026, 3, 10, 5, 0), 20)]);
      expect(de(todas, AchievementKind.earlyBird).unlocked, isTrue);
      expect(de(todas, AchievementKind.nightOwl).unlocked, isFalse);
    });

    test('a las siete ya no', () {
      expect(
        de(evaluar(sesiones: [sesion(DateTime(2026, 3, 10, 7, 0), 20)]), AchievementKind.earlyBird).unlocked,
        isFalse,
      );
    });

    test('a las tres de la madrugada es trasnochar', () {
      final todas = evaluar(sesiones: [sesion(DateTime(2026, 3, 10, 3, 0), 20)]);
      expect(de(todas, AchievementKind.nightOwl).unlocked, isTrue);
      expect(de(todas, AchievementKind.earlyBird).unlocked, isFalse);
    });

    test('la frontera del noctámbulo es el corte del día de lectura', () {
      // Las 4:00 no son noche: a esa hora empieza el día de lectura, y usar
      // otra frontera aquí contradiría a la racha y al calendario.
      expect(
        de(evaluar(sesiones: [sesion(DateTime(2026, 3, 10, 3, 59), 20)]), AchievementKind.nightOwl).unlocked,
        isTrue,
      );
      expect(
        de(evaluar(sesiones: [sesion(DateTime(2026, 3, 10, 4, 0), 20)]), AchievementKind.nightOwl).unlocked,
        isFalse,
      );
    });
  });

  group('libros terminados', () {
    test('un libro al 99 % ya cuenta como terminado', () {
      final todas = evaluar(libros: [libro(1, progress: 0.99)]);
      expect(de(todas, AchievementKind.finished1).unlocked, isTrue);
    });

    test('un libro a medias no cuenta', () {
      expect(de(evaluar(libros: [libro(1, progress: 0.5)]), AchievementKind.finished1).unlocked, isFalse);
    });

    test('cinco terminados desbloquean la de cinco, no la de veinte', () {
      final libros = [for (var i = 1; i <= 5; i++) libro(i, progress: 1)];
      final todas = evaluar(libros: libros);
      expect(de(todas, AchievementKind.finished5).unlocked, isTrue);
      expect(de(todas, AchievementKind.finished20).unlocked, isFalse);
      expect(de(todas, AchievementKind.finished20).countLabel, '5 / 20 libros');
    });
  });

  group('orden de la rejilla', () {
    test('las conseguidas van delante y después la más cercana', () {
      final todas = evaluar(sesiones: [sesion(ahora, 20)]);

      expect(todas.first.kind, AchievementKind.firstStep, reason: 'la única conseguida');
      // Empatan a un tercio la racha de tres (1 de 3 días) y el maratón (20 de
      // 60 minutos); desempata el orden del catálogo, que es estable.
      expect(todas[1].kind, AchievementKind.streak3);
      expect(todas[2].kind, AchievementKind.marathon);
      expect(todas.last.unlocked, isFalse);
    });

    test('el orden no depende del azar entre ejecuciones', () {
      final sesiones = [sesion(ahora, 20)];
      final primera = evaluar(sesiones: sesiones).map((p) => p.kind).toList();
      final segunda = evaluar(sesiones: sesiones).map((p) => p.kind).toList();
      expect(primera, segunda);
    });
  });

  group('insignias de sí o no', () {
    test('no enseñan cuenta', () {
      expect(de(evaluar(), AchievementKind.earlyBird).countLabel, isEmpty);
      expect(de(evaluar(), AchievementKind.streak3).countLabel, isNotEmpty);
    });
  });
}
