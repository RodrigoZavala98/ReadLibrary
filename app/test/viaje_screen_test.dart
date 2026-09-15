import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reader_profile.dart';
import 'package:lector/domain/reading_streak.dart';
import 'package:lector/main.dart';
import 'package:lector/shell/home_shell.dart';
import 'package:lector/ui/activity_grid.dart';

void main() {
  late Directory temp;
  late AppServices services;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_viaje_');
    services = AppServices.forDirectory(temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Alterna fotogramas con tiempo real hasta que la carga de disco termina.
  ///
  /// El mismo helper que en Mi Refugio, y por el mismo motivo: `pump` avanza el
  /// reloj simulado pero no deja correr el bucle de eventos de verdad, y
  /// `runAsync` hace lo contrario. `pumpAndSettle` no vale: mientras carga hay
  /// un `CircularProgressIndicator` girando y la prueba no asentaría jamás.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> abrirViaje(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(LectorApp(services: services)),
    );
    await asentar(tester);
    await tester.tap(find.text(HomeSection.viaje.label));
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

  /// Baja hasta que el objetivo entra en pantalla.
  ///
  /// Hace falta porque la pantalla es larga y el `ListView` sólo construye lo
  /// que cabe en el lienzo de pruebas: las insignias, que van al final, no
  /// existen en el árbol hasta que se llega a ellas.
  Future<void> bajarHasta(WidgetTester tester, Finder objetivo) async {
    // Hay que decirle cuál es el scroll: la cuadrícula del calendario y la
    // rejilla de insignias son `Scrollable` también, aunque no scrolleen, y
    // sin esto no sabría con cuál de los tres quedarse.
    await tester.scrollUntilVisible(
      objetivo,
      240,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pump();
  }

  ReadingSession sesion(DateTime cuando, [int minutos = 20]) => ReadingSession(
    startedAt: cuando,
    duration: Duration(minutes: minutos),
    bookId: 1,
  );

  /// El día de lectura vigente, a medianoche.
  ///
  /// Todas las fechas de estas pruebas se derivan de aquí y nunca de
  /// `DateTime.now()` directo. El día de lectura no coincide con el natural
  /// —empieza a las 4:00—, así que entre medianoche y esa hora el día en curso
  /// es todavía el natural anterior. Acoplarse al reloj de la máquina ya rompió
  /// dos veces la integración continua, que corre en UTC.
  DateTime diaDeHoy() => ReadingDay.keyFor(DateTime.now(), dayStartHour: 4);

  /// Una lectura de hoy a una hora que no desbloquea insignias de horario.
  ReadingSession lecturaDeHoy([int minutos = 20]) {
    final hoy = diaDeHoy();
    return sesion(DateTime(hoy.year, hoy.month, hoy.day, 20), minutos);
  }

  /// Una lectura del último día del mes anterior.
  ///
  /// El día 0 de un mes es el último del anterior, así que esto vale igual
  /// ejecutándose un día 1 que un día 31, y también en enero.
  ReadingSession lecturaDelMesPasado([int minutos = 30]) {
    final hoy = diaDeHoy();
    return sesion(DateTime(hoy.year, hoy.month, 0, 12), minutos);
  }

  group('sin historial', () {
    testWidgets('invita a empezar en vez de enseñar un mes en blanco',
        (tester) async {
      await abrirViaje(tester);

      expect(find.textContaining('Tu viaje empieza'), findsOneWidget);
      expect(find.byType(ActivityGrid), findsNothing);
    });

    testWidgets('no enseña trece insignias grises de bienvenida',
        (tester) async {
      await abrirViaje(tester);
      expect(find.text('Insignias'), findsNothing);
    });
  });

  group('resumen y calendario', () {
    testWidgets('una lectura de hoy sale en el total y en el mejor día',
        (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      expect(find.text('Tiempo total'), findsOneWidget);
      expect(find.text('20 min'), findsWidgets);
      expect(
        find.textContaining(
          'Tu mejor día fue el ${hoy.day} de ${monthName(hoy.month)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('el mes en curso se abre por su nombre', (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      expect(find.text('${monthName(hoy.month)} ${hoy.year}'), findsOneWidget);
    });

    testWidgets('los libros terminados se cuentan aparte de los empezados',
        (tester) async {
      await sembrar(
        tester,
        sessions: [lecturaDeHoy()],
        books: [
          LibraryBook(
            id: 1,
            filePath: '${temp.path}/leido.txt',
            format: BookFormat.txt,
            title: 'Terminado',
            addedAt: DateTime(2026, 1, 1),
            progress: 1,
          ),
          LibraryBook(
            id: 2,
            filePath: '${temp.path}/medias.txt',
            format: BookFormat.txt,
            title: 'A medias',
            addedAt: DateTime(2026, 1, 1),
            progress: 0.4,
          ),
        ],
      );
      await abrirViaje(tester);

      expect(find.text('Libros terminados'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('el día 1 cae en la columna de su día de la semana',
        (tester) async {
      // La alineación es lo único de la cuadrícula que no se ve en el dominio:
      // `leadingBlanks` puede estar bien calculado y la pantalla ignorarlo. Se
      // comprueba por geometría, midiendo en qué séptimo del ancho cae el 1.
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      final rejilla = tester.getRect(find.byType(ActivityGrid));
      final uno = tester.getRect(
        find.descendant(
          of: find.byType(ActivityGrid),
          matching: find.text('1'),
        ),
      );

      final columna = ((uno.center.dx - rejilla.left) / (rejilla.width / 7))
          .floor();
      expect(columna, DateTime(hoy.year, hoy.month, 1).weekday - 1);
    });

    testWidgets('un mes sin lecturas lo dice, no deja la tarjeta muda',
        (tester) async {
      // Sólo hay historial del mes pasado: el mes en curso está vacío.
      await sembrar(tester, sessions: [lecturaDelMesPasado()]);
      await abrirViaje(tester);

      expect(find.text('Ningún rato de lectura este mes.'), findsOneWidget);
    });
  });

  group('tocar un día', () {
    testWidgets('escribe cuánto se leyó ese día', (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy(35)]);
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      final casilla = find.descendant(
        of: find.byType(ActivityGrid),
        matching: find.text('${hoy.day}'),
      );
      await tester.ensureVisible(casilla);
      await tester.pump();
      await tester.tap(casilla);
      await tester.pump();

      expect(
        find.text('${weekdayName(hoy)} ${hoy.day} · 35 min'),
        findsOneWidget,
      );
    });

    testWidgets('antes de tocar nada, explica que se puede tocar',
        (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      expect(find.textContaining('Toca un día'), findsOneWidget);
    });

    testWidgets('cada casilla se anuncia con su día y sus minutos',
        (tester) async {
      // El color por sí solo no comunica nada a quien usa lector de pantalla.
      final handle = tester.ensureSemantics();
      await sembrar(tester, sessions: [lecturaDeHoy(35)]);
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      expect(
        find.bySemanticsLabel(
          '${hoy.day} de ${monthName(hoy.month)}, 35 minutos',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('navegación entre meses', () {
    Finder flecha(IconData icono) =>
        find.widgetWithIcon(IconButton, icono);

    testWidgets('no se puede ir al futuro', (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      final siguiente = tester.widget<IconButton>(flecha(Icons.chevron_right));
      expect(siguiente.onPressed, isNull);
    });

    testWidgets('sin historial anterior tampoco se puede retroceder',
        (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      final anterior = tester.widget<IconButton>(flecha(Icons.chevron_left));
      expect(anterior.onPressed, isNull);
    });

    testWidgets('se retrocede hasta el mes de la primera lectura',
        (tester) async {
      await sembrar(
        tester,
        sessions: [lecturaDelMesPasado(), lecturaDeHoy()],
      );
      await abrirViaje(tester);

      await tester.tap(flecha(Icons.chevron_left));
      await tester.pump();

      final hoy = diaDeHoy();
      final pasado = DateTime(hoy.year, hoy.month, 0);
      expect(
        find.text('${monthName(pasado.month)} ${pasado.year}'),
        findsOneWidget,
      );
      expect(find.text('30 min'), findsWidgets, reason: 'la lectura de ese mes');

      // Ya no hay más historial por detrás, pero sí por delante.
      expect(
        tester.widget<IconButton>(flecha(Icons.chevron_left)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(flecha(Icons.chevron_right)).onPressed,
        isNotNull,
      );
    });

    testWidgets('la selección de un mes no se cuela en otro', (tester) async {
      await sembrar(
        tester,
        sessions: [lecturaDelMesPasado(), lecturaDeHoy(35)],
      );
      await abrirViaje(tester);

      final hoy = diaDeHoy();
      final casilla = find.descendant(
        of: find.byType(ActivityGrid),
        matching: find.text('${hoy.day}'),
      );
      await tester.ensureVisible(casilla);
      await tester.pump();
      await tester.tap(casilla);
      await tester.pump();
      expect(find.textContaining('· 35 min'), findsOneWidget);

      // Enseñar la casilla ha bajado la lista: sin volver a subir, el toque
      // sobre la flecha caería fuera de la pantalla y no pasaría nada.
      await tester.ensureVisible(flecha(Icons.chevron_left));
      await tester.pump();
      await tester.tap(flecha(Icons.chevron_left));
      await tester.pump();

      // El día 14 de este mes no es el 14 del anterior: la línea vuelve a su
      // texto de ayuda en lugar de atribuir la lectura al mes equivocado.
      expect(find.textContaining('· 35 min'), findsNothing);
      expect(find.textContaining('Toca un día'), findsOneWidget);
    });
  });

  group('insignias', () {
    testWidgets('la primera lectura desbloquea una y deja el resto a la vista',
        (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      await bajarHasta(tester, find.text('Insignias'));
      expect(find.text('1 de 13 conseguidas'), findsOneWidget);

      await bajarHasta(tester, find.text('Primer paso'));
      expect(find.text('Conseguida'), findsOneWidget);
    });

    testWidgets('las pendientes enseñan cuánto falta', (tester) async {
      await sembrar(tester, sessions: [lecturaDeHoy()]);
      await abrirViaje(tester);

      await bajarHasta(tester, find.text('Tres en raya'));
      expect(find.text('1 / 3 días'), findsOneWidget);
    });

    testWidgets('leer de madrugada desbloquea la del noctámbulo',
        (tester) async {
      final hoy = diaDeHoy();
      // Las 3:00 pertenecen al día de lectura anterior, pero las insignias se
      // miden sobre el historial entero y no sobre el mes visible.
      await sembrar(
        tester,
        sessions: [sesion(DateTime(hoy.year, hoy.month, hoy.day, 3), 20)],
      );
      await abrirViaje(tester);

      await bajarHasta(tester, find.text('Noctámbulo'));
      expect(find.text('2 de 13 conseguidas'), findsOneWidget);
    });
  });
}
