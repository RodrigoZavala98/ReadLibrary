import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector/app_services.dart';
import 'package:lector/core/theme/app_theme.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/library_book.dart';
import 'package:lector/domain/reading_settings.dart';
import 'package:lector/ui/reader_screen.dart';

import 'epub_fixture.dart';

/// Regresión de un fallo real: al salir del lector no se guardaba nada.
///
/// La causa era que `dispose()` llamaba a `AppScope.of(context)`, y Flutter
/// prohíbe buscar un antecesor heredado desde un widget ya desactivado. La
/// excepción saltaba justo en el momento de persistir, así que ni la posición
/// ni la sesión llegaban al disco: el libro seguía marcado «sin empezar» y la
/// racha no avanzaba por muchos minutos que se leyera.
void main() {
  late Directory temp;
  late AppServices services;
  late DateTime ahora;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_persist_');
    services = AppServices.forDirectory(temp);
    ahora = DateTime(2026, 3, 15, 20, 0);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Alterna fotogramas con tiempo real hasta que todo se estabiliza.
  ///
  /// Los `pump` llevan duración a propósito: sin ella el reloj simulado no
  /// avanza y las animaciones de transición entre rutas no llegan a terminar,
  /// dejando el Navigator a medias.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<LibraryBook> prepararLibro(
    WidgetTester tester, {
    int parrafos = 400,
    BookLocator? locator,
  }) async {
    final file = File('${temp.path}${Platform.pathSeparator}dune.txt');
    final book = LibraryBook(
      id: 1,
      filePath: file.path,
      format: BookFormat.txt,
      title: 'Dune',
      addedAt: DateTime(2026, 3, 1),
      locator: locator,
    );

    await tester.runAsync(() async {
      await file.writeAsString(
        List.generate(
          parrafos,
          (i) => 'Párrafo $i. ${'palabra ' * 20}',
        ).join('\n\n'),
      );
      await services.repository.save(book);
    });
    return book;
  }

  /// Monta el lector solo, con un reloj que controlamos.
  Future<void> abrirLector(WidgetTester tester, LibraryBook book) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: ChromeTheme.build(),
            home: ReaderScreen(book: book, now: () => ahora),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Saca u oculta los controles tocando el centro de la pantalla.
  ///
  /// Se toca el centro por coordenadas y no un widget concreto porque el
  /// interior del lector depende del modo: en paginado hay páginas y en
  /// continuo un `ListView`. El gesto del usuario es el mismo en los dos.
  Future<void> tocarCentro(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(ReaderScreen)));
    await tester.pump();
  }

  /// Cierra el lector sustituyendo el árbol, que provoca su dispose().
  Future<void> cerrarLector(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(const MaterialApp(home: SizedBox())),
    );
    await asentar(tester);
  }

  testWidgets('salir y desmontar guarda una sola sesión, no dos',
      (tester) async {
    // La salida ordenada guarda antes de cerrar, y dispose() mantiene además
    // un guardado de reserva. Sin el testigo que los coordina, la sesión se
    // registraría dos veces y el tiempo del día saldría al doble.
    final book = await prepararLibro(tester);

    await tester.runAsync(
      () => tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: ChromeTheme.build(),
            home: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(book: book, now: () => ahora),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);

    await tester.tap(find.text('abrir'));
    await asentar(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);

    ahora = ahora.add(const Duration(minutes: 9));

    // Salida por el botón de la barra, que dispara la salida ordenada y, tras
    // ella, el desmontaje de la ruta. Los controles están ocultos hasta tocar
    // el centro de la pantalla.
    await tocarCentro(tester);

    // El toque va dentro de `runAsync` a propósito. La salida encadena varias
    // escrituras en disco, y cada una necesita una ventana de tiempo real para
    // completarse; disparándola desde la zona de reloj simulado se queda a
    // medias y la sesión nunca llega a guardarse. En el dispositivo real no
    // existe esa zona y la cadena corre entera.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Volver a la biblioteca'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await asentar(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, hasLength(1));
    expect(sesiones!.single.duration, const Duration(minutes: 9));
  });

  testWidgets('el libro se abre y muestra su texto', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    expect(find.textContaining('Párrafo 0.'), findsOneWidget);
  });

  testWidgets('al salir se registra la sesión de lectura', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    // Nueve minutos de lectura, como en el informe del fallo.
    ahora = ahora.add(const Duration(minutes: 9));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, hasLength(1));
    expect(sesiones!.single.duration, const Duration(minutes: 9));
    expect(sesiones.single.bookId, 1);
  });

  testWidgets('al salir se marca el libro como empezado', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    ahora = ahora.add(const Duration(minutes: 9));
    await cerrarLector(tester);

    final guardado = await tester.runAsync(() => services.repository.byId(1));
    expect(guardado, isNotNull);
    expect(
      guardado!.lastOpenedAt,
      isNotNull,
      reason: 'sin esto la biblioteca lo seguiría llamando «sin empezar»',
    );
    expect(guardado.isStarted, isTrue);
  });

  testWidgets('abrir y salir enseguida no registra sesión', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    ahora = ahora.add(const Duration(seconds: 3));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(sesiones, isEmpty, reason: 'no debe regalar racha por un despiste');
  });

  testWidgets('el tiempo en segundo plano no se contabiliza', (tester) async {
    final book = await prepararLibro(tester);
    await abrirLector(tester, book);

    // Lee seis minutos, bloquea el móvil, y lo recupera dos horas después.
    ahora = ahora.add(const Duration(minutes: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    ahora = ahora.add(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ahora = ahora.add(const Duration(minutes: 4));
    await cerrarLector(tester);

    final sesiones = await tester.runAsync(services.sessions.loadAll);
    expect(
      sesiones!.single.duration,
      const Duration(minutes: 10),
      reason: 'las dos horas con la pantalla apagada no son lectura',
    );
  });

  /// Segundo fallo del mismo sitio: la barra se quedaba clavada en 0 %.
  ///
  /// `_currentLocator()` interrogaba al ScrollController desde `dispose()`,
  /// pero para entonces el ListView ya está desmontado y su posición
  /// desacoplada, así que siempre devolvía el inicio del fragmento.
  group('progreso de lectura', () {
    // Este grupo mide el avance por lo que se ha desplazado el texto, así que
    // va en modo continuo. En paginado el avance sale de la página, y eso se
    // prueba en `reader_pagination_test.dart`.
    setUp(() => services.settings.save(
          ReadingSettings(mode: ReadingMode.continuo),
        ));

    Future<double> progresoTras(WidgetTester tester) async {
      final guardado = await tester.runAsync(() => services.repository.byId(1));
      return guardado!.progress;
    }

    testWidgets('un texto que cabe en pantalla se marca como leído entero',
        (tester) async {
      // Un solo párrafo: cabe de sobra en la pantalla de prueba y no genera
      // desplazamiento alguno.
      final book = await prepararLibro(tester, parrafos: 1);
      await abrirLector(tester, book);

      ahora = ahora.add(const Duration(minutes: 9));
      await cerrarLector(tester);

      expect(
        await progresoTras(tester),
        1.0,
        reason: 'si no hay nada que desplazar, se ha visto todo',
      );
    });

    testWidgets('desplazarse hasta el final del fragmento cuenta como avance',
        (tester) async {
      final book = await prepararLibro(tester);
      await abrirLector(tester, book);

      await tester.drag(find.byType(ListView), const Offset(0, -30000));
      await tester.pump();

      ahora = ahora.add(const Duration(minutes: 9));
      await cerrarLector(tester);

      expect(
        await progresoTras(tester),
        greaterThan(0.15),
        reason: 'el fragmento leído es una parte apreciable del libro',
      );
    });

    testWidgets('leer sin moverse deja el progreso donde estaba, no lo inventa',
        (tester) async {
      final book = await prepararLibro(tester);
      await abrirLector(tester, book);

      ahora = ahora.add(const Duration(minutes: 9));
      await cerrarLector(tester);

      expect(
        await progresoTras(tester),
        0.0,
        reason: 'en la primera pantalla de un libro largo aún no hay avance',
      );
    });

    testWidgets('retomar un libro no lo devuelve al principio del fragmento',
        (tester) async {
      // Guardada una posición a mitad del primer fragmento.
      const guardada = CharLocator(10000);
      final book = await prepararLibro(tester, locator: guardada);
      await abrirLector(tester, book);

      // Se sale sin tocar nada: la posición debe sobrevivir casi intacta.
      ahora = ahora.add(const Duration(minutes: 1));
      await cerrarLector(tester);

      final despues = await tester.runAsync(() => services.repository.byId(1));
      final locator = despues!.locator;
      expect(locator, isA<CharLocator>());
      expect(
        (locator! as CharLocator).charOffset,
        closeTo(10000, 1500),
        reason: 'antes aterrizaba en 0 y había que buscar por dónde ibas',
      );
    });
  });
  /// El mismo circuito, con el formato que de verdad importa.
  ///
  /// Un EPUB no tiene desplazamientos en caracteres ni fragmentos: tiene
  /// documentos dentro de un ZIP. Que estas pruebas pasen sin tocar la pantalla
  /// de lectura es lo que demuestra que ya no sabe de formatos.
  group('EPUB', () {
    Future<LibraryBook> prepararEpub(
      WidgetTester tester, {
      Map<String, Object>? entries,
      BookLocator? locator,
    }) async {
      final file = File('${temp.path}${Platform.pathSeparator}libro.epub');
      final book = LibraryBook(
        id: 1,
        filePath: file.path,
        format: BookFormat.epub,
        title: 'El libro',
        addedAt: DateTime(2026, 3, 1),
        locator: locator,
      );

      await tester.runAsync(() async {
        await file.writeAsBytes(zipOf(entries ?? sampleEpub2()));
        await services.repository.save(book);
      });
      return book;
    }

    testWidgets('se abre y enseña el texto del primer capítulo',
        (tester) async {
      await abrirLector(tester, await prepararEpub(tester));
      expect(find.textContaining('Primera página'), findsOneWidget);
    });

    testWidgets('los controles enseñan el título real del capítulo',
        (tester) async {
      await abrirLector(tester, await prepararEpub(tester));

      await tocarCentro(tester);

      expect(find.text('El principio'), findsOneWidget);
      expect(find.textContaining('Capítulo 1 de 2'), findsOneWidget);
    });

    testWidgets('pasar de capítulo y salir guarda dónde se estaba',
        (tester) async {
      await abrirLector(tester, await prepararEpub(tester));

      await tocarCentro(tester);
      await tester.tap(find.byTooltip('Capítulo siguiente'));
      await asentar(tester);
      expect(find.textContaining('Última página'), findsOneWidget);

      ahora = ahora.add(const Duration(minutes: 9));
      await cerrarLector(tester);

      final guardado = await tester.runAsync(() => services.repository.byId(1));
      expect(guardado!.locator, isA<EpubLocator>());
      expect((guardado.locator! as EpubLocator).spineIndex, 1);
      expect(guardado.progress, greaterThan(0));
    });

    testWidgets('retomar el libro vuelve al capítulo donde se dejó',
        (tester) async {
      await abrirLector(
        tester,
        await prepararEpub(tester, locator: const EpubLocator(1, 0)),
      );

      expect(find.textContaining('Última página'), findsOneWidget);
      expect(find.textContaining('Primera página'), findsNothing);
    });

    testWidgets('salir mientras el libro se abre no deja el fichero abierto',
        (tester) async {
      // Regresión. Abrir el EPUB pasa por varios turnos asíncronos —ajustes,
      // ZIP, índice—, y si la pantalla se va en medio, `dispose()` no encuentra
      // todavía ninguna fuente que cerrar. El descriptor se quedaba abierto
      // para toda la vida de la aplicación.
      //
      // Se comprueba borrando el fichero, que es lo que Windows prohíbe
      // mientras algo lo tiene abierto. En Linux —donde corre la integración
      // continua— borrar un fichero abierto sí funciona, así que allí esta
      // prueba no muerde: es de las que sólo caza el equipo de desarrollo.
      final book = await prepararEpub(tester);

      await tester.runAsync(
        () => tester.pumpWidget(
          AppScope(
            services: services,
            child: MaterialApp(
              home: ReaderScreen(book: book, now: () => ahora),
            ),
          ),
        ),
      );
      // Un solo fotograma: lo justo para que arranque la carga y no para que
      // termine.
      await tester.pump();
      await cerrarLector(tester);

      await tester.runAsync(() async {
        await File(book.filePath).delete();
      });
      expect(File(book.filePath).existsSync(), isFalse);
    });

    testWidgets('un EPUB con DRM lo explica en lugar de fallar en silencio',
        (tester) async {
      final drm = {
        ...sampleEpub2(),
        'META-INF/encryption.xml':
            '<?xml version="1.0"?>'
            '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">'
            '<CipherData><CipherReference URI="OEBPS/c1.xhtml"/></CipherData>'
            '</EncryptedData></encryption>',
      };
      await abrirLector(tester, await prepararEpub(tester, entries: drm));

      // El mensaje es el del dominio, sin el nombre de la clase de Dart
      // delante, que es lo que saldría al enseñar el `toString` de la
      // excepción.
      expect(find.textContaining('DRM'), findsOneWidget);
      expect(find.textContaining('BookOpenException'), findsNothing);
    });
  });
}
