import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../app_services.dart';
import '../domain/book_locator.dart';
import '../domain/library_book.dart';
import '../domain/reading_clock.dart';

/// Lo que toda pantalla de lectura tiene que hacer, sea cual sea el formato.
///
/// Leer una novela y leer un cómic no se parecen en nada por dentro —uno mide
/// texto y lo reparte en páginas, el otro descomprime imágenes— pero por fuera
/// comparten entero el contrato con el resto de la aplicación: cronometrar el
/// tiempo de lectura, guardar la posición una sola vez, salir después de haber
/// guardado y devolver el brillo al sistema.
///
/// Eso está aquí y no duplicado en cada pantalla porque **es justo donde
/// vivieron los cuatro fallos más caros del proyecto**: la sesión que se
/// registraba dos veces, la biblioteca que enseñaba el avance anterior porque
/// se recargaba antes de que terminara el guardado, el `AppScope.of` llamado
/// desde `dispose()` y el `ScrollController` interrogado cuando ya no existía.
/// Escribirlos por segunda vez en una pantalla nueva sería invitarlos a los
/// cuatro a volver.
///
/// Las hijas ponen el formato: de dónde sale la posición y qué hay que pintar.
abstract class ReaderSessionState<W extends StatefulWidget> extends State<W>
    with WidgetsBindingObserver {
  final _clock = ReadingClock();

  /// Evita guardar dos veces.
  ///
  /// Lo normal es persistir al salir, de forma esperada, para que la
  /// biblioteca ya encuentre los datos frescos al recargar. Pero [dispose]
  /// mantiene un guardado de reserva por si la pantalla desaparece sin pasar
  /// por ahí, y sin este testigo la sesión de lectura se registraría dos veces
  /// y el día contaría doble.
  bool _persisted = false;

  /// Los servicios, capturados mientras el widget está vivo.
  ///
  /// No se puede llamar a `AppScope.of(context)` desde [dispose]: por debajo
  /// usa `dependOnInheritedWidgetOfExactType`, y Flutter lo prohíbe sobre un
  /// widget ya desactivado —«Looking up a deactivated widget's ancestor is
  /// unsafe»—. Hacerlo lanzaba una excepción justo en el momento de guardar, y
  /// ni la posición ni la sesión llegaban nunca al disco.
  AppServices? _services;

  bool _loading = false;

  @protected
  AppServices? get services => _services;

  /// El libro que se está leyendo.
  @protected
  LibraryBook get book;

  /// De dónde sale la hora actual. Se puede sustituir en las pruebas para
  /// simular una lectura larga sin esperarla de verdad.
  @protected
  DateTime Function() get now;

  /// Dónde está el lector ahora mismo, o `null` si el libro todavía no se ha
  /// abierto y por tanto no hay ninguna posición que guardar.
  @protected
  BookLocator? currentLocator();

  /// Qué avance, de 0 a 1, le corresponde a [locator].
  @protected
  double progressAt(BookLocator locator);

  /// Abre el libro. Se llama una sola vez, ya con los servicios disponibles.
  ///
  /// No arranca en `initState` sino en cuanto hay servicios: los ajustes de
  /// lectura vienen del `AppScope`, que en `initState` todavía no se puede
  /// consultar —hacerlo lanza «dependOn... called before initState completed»—.
  @protected
  Future<void> load();

  /// Suelta controladores, notificadores y la fuente del libro.
  ///
  /// Lo llama [dispose] en el momento justo: después de haber guardado, que es
  /// cuando la fuente ya no hace falta, y nunca antes, que es cuando todavía
  /// se la necesita para saber la posición.
  @protected
  void releaseResources() {}

  /// El libro tal y como hay que guardarlo. Las hijas lo amplían si su formato
  /// conoce algo más —un cómic sabe cuántas páginas tiene—.
  @protected
  LibraryBook bookToSave(BookLocator locator) => book.copyWith(
    locator: locator,
    progress: progressAt(locator),
    lastOpenedAt: now(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock.start(now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (!_loading) {
      _loading = true;
      unawaited(load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Red de seguridad: si la pantalla se va sin pasar por [leave], se intenta
    // guardar igualmente. Aquí no se puede esperar al resultado, así que es
    // «dispara y olvida» y la biblioteca podría no verlo a tiempo. Por eso la
    // salida normal guarda antes de cerrar, no aquí.
    unawaited(persistAll());
    releaseResources();
    // El brillo vuelve al del sistema sí o sí: dejarlo bajado al salir del
    // libro convertiría un ajuste de lectura en un fallo del teléfono.
    unawaited(restoreBrightness());
    super.dispose();
  }

  /// Guarda posición y sesión. Idempotente.
  @protected
  Future<void> persistAll() async {
    if (_persisted) return;
    _persisted = true;

    final services = _services;
    if (services == null) return;

    final locator = currentLocator();
    if (locator != null) await services.repository.save(bookToSave(locator));

    final session = _clock.toSession(bookId: book.id, now: now());
    // `null` cuando se abrió el libro y se salió enseguida: no ensucia el
    // historial ni regala días de racha.
    if (session != null) await services.sessions.add(session);
  }

  /// Salida ordenada: primero se guarda, después se cierra.
  ///
  /// El orden es lo que arregla que la biblioteca mostrara el avance anterior
  /// hasta cambiar de pestaña y volver: recargaba antes de que el guardado
  /// hubiera terminado.
  @protected
  Future<void> leave() async {
    await persistAll();
    if (mounted) Navigator.of(context).pop();
  }

  /// El cronómetro sigue al ciclo de vida de la aplicación.
  ///
  /// Sin esto, dejar el libro abierto y bloquear el móvil registraría toda la
  /// noche como tiempo de lectura, y la racha dejaría de significar nada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final instant = now();
    switch (state) {
      case AppLifecycleState.resumed:
        _clock.resume(instant);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _clock.pause(instant);
    }
  }

  /// Manda el brillo al sistema, o lo deja como estaba si [wanted] es `null`,
  /// que es lo que significa «no opinamos».
  ///
  /// Todo lo de la pantalla va envuelto en `try`: es una llamada a la
  /// plataforma, y hay fabricantes donde falla. Que no se pueda atenuar la
  /// pantalla no puede impedir leer.
  @protected
  Future<void> applyBrightness(double? wanted) async {
    try {
      if (wanted == null) {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } else {
        await ScreenBrightness.instance.setApplicationScreenBrightness(wanted);
      }
    } on Object {
      // Sin brillo ajustable se lee igual.
    }
  }

  @protected
  Future<void> restoreBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } on Object {
      // Ídem.
    }
  }
}
