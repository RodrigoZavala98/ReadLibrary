import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reader_profile.dart';
import 'package:lector/domain/reading_streak.dart';
import 'package:lector/main.dart';
import 'package:lector/shell/home_shell.dart';

void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_refugio_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Monta la app y abre Mi Refugio.
  ///
  /// `runAsync` es imprescindible porque el cuerpo de `testWidgets` corre con
  /// reloj simulado y aquí hay lecturas reales de disco.
  /// Alterna fotogramas con tiempo real hasta que la carga de disco termina.
  ///
  /// Hace falta porque `pump` avanza el reloj simulado pero no deja correr el
  /// bucle de eventos de verdad, y `runAsync` hace lo contrario. Un solo plazo
  /// fijo no basta: Mi Refugio encadena tres lecturas —perfil, sesiones y
  /// biblioteca— y cada una necesita su propio turno.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> abrirRefugio(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(LectorApp(services: services)),
    );
    await asentar(tester);
    await tester.tap(find.text(HomeSection.refugio.label));
    await asentar(tester);
  }

  Future<void> sembrar(
    WidgetTester tester, {
    ReaderProfile? profile,
    List<ReadingSession> sessions = const [],
    List<LibraryBook> books = const [],
  }) {
    return tester.runAsync(() async {
      if (profile != null) await services.profile.save(profile);
      for (final s in sessions) {
        await services.sessions.add(s);
      }
      for (final b in books) {
        await services.repository.save(b);
      }
    });
  }

  ReadingSession sesion(DateTime cuando, [int minutos = 20]) => ReadingSession(
    startedAt: cuando,
    duration: Duration(minutes: minutos),
    bookId: 1,
  );

  /// Hoy a las ocho de la tarde, para caer siempre dentro del día de lectura.
  DateTime hoyPorLaTarde({int diasAtras = 0}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - diasAtras, 20);
  }

  testWidgets('sin nombre saluda de forma impersonal', (tester) async {
    await abrirRefugio(tester);
    expect(find.text('Tu biblioteca'), findsOneWidget);
  });

  testWidgets('con nombre saluda por el nombre', (tester) async {
    await sembrar(tester, profile: const ReaderProfile(displayName: 'Rodrigo'));
    await abrirRefugio(tester);

    expect(find.text('La biblioteca de Rodrigo'), findsOneWidget);
  });

  testWidgets('sin haber leído nunca, invita a empezar', (tester) async {
    await abrirRefugio(tester);

    expect(find.text('0'), findsOneWidget, reason: 'cero días en el anillo');
    expect(
      find.textContaining('arrancas una racha'),
      findsOneWidget,
    );
  });

  testWidgets('leer hoy cumpliendo la meta muestra la racha', (tester) async {
    await sembrar(tester, sessions: [sesion(hoyPorLaTarde())]);
    await abrirRefugio(tester);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('día'), findsOneWidget, reason: 'singular con un día');
    expect(find.textContaining('Meta cumplida'), findsOneWidget);
  });

  testWidgets('varios días encadenados se cuentan y van en plural',
      (tester) async {
    await sembrar(
      tester,
      sessions: [
        sesion(hoyPorLaTarde(diasAtras: 2)),
        sesion(hoyPorLaTarde(diasAtras: 1)),
        sesion(hoyPorLaTarde()),
      ],
    );
    await abrirRefugio(tester);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('días'), findsOneWidget);
    expect(find.textContaining('3 días seguidos'), findsOneWidget);
  });

  testWidgets('con la racha en riesgo avisa sin dar por perdido el día',
      (tester) async {
    // Se leyó ayer y anteayer, hoy todavía no.
    await sembrar(
      tester,
      sessions: [
        sesion(hoyPorLaTarde(diasAtras: 2)),
        sesion(hoyPorLaTarde(diasAtras: 1)),
      ],
    );
    await abrirRefugio(tester);

    expect(find.text('2'), findsOneWidget, reason: 'la racha sigue viva');
    expect(find.textContaining('Lee hoy'), findsOneWidget);
  });

  testWidgets('una lectura corta no cumple la meta pero se nota en el anillo',
      (tester) async {
    await sembrar(tester, sessions: [sesion(hoyPorLaTarde(), 5)]);
    await abrirRefugio(tester);

    expect(find.text('0'), findsOneWidget, reason: '5 min no llegan a 15');
    expect(find.textContaining('arrancas una racha'), findsOneWidget);
  });

  testWidgets('la meta del perfil cambia lo que cuenta como día cumplido',
      (tester) async {
    await sembrar(
      tester,
      profile: const ReaderProfile(dailyGoalMinutes: 5),
      sessions: [sesion(hoyPorLaTarde(), 6)],
    );
    await abrirRefugio(tester);

    expect(find.text('1'), findsOneWidget, reason: '6 min superan la meta de 5');
  });

  group('continuar leyendo', () {
    testWidgets('sin libros empezados no ofrece continuar', (tester) async {
      await abrirRefugio(tester);
      expect(find.textContaining('Todavía no has empezado'), findsOneWidget);
    });

    testWidgets('ofrece el último libro abierto con su progreso',
        (tester) async {
      await sembrar(
        tester,
        books: [
          LibraryBook(
            id: 1,
            filePath: '${temp.path}/viejo.txt',
            format: BookFormat.txt,
            title: 'El viejo',
            addedAt: DateTime(2026, 1, 1),
            lastOpenedAt: DateTime(2026, 3, 1),
            progress: 0.2,
          ),
          LibraryBook(
            id: 2,
            filePath: '${temp.path}/reciente.txt',
            format: BookFormat.txt,
            title: 'El reciente',
            addedAt: DateTime(2026, 1, 1),
            lastOpenedAt: DateTime(2026, 3, 14),
            progress: 0.65,
          ),
        ],
      );
      await abrirRefugio(tester);

      expect(find.text('El reciente'), findsOneWidget);
      expect(find.text('65 % leído'), findsOneWidget);
      expect(find.text('El viejo'), findsNothing);
    });

    testWidgets('un libro añadido pero nunca abierto no cuenta', (tester) async {
      await sembrar(
        tester,
        books: [
          LibraryBook(
            id: 1,
            filePath: '${temp.path}/nuevo.txt',
            format: BookFormat.txt,
            title: 'Sin abrir',
            addedAt: DateTime(2026, 3, 1),
          ),
        ],
      );
      await abrirRefugio(tester);

      expect(find.textContaining('Todavía no has empezado'), findsOneWidget);
      expect(find.text('Sin abrir'), findsNothing);
    });
  });
}
