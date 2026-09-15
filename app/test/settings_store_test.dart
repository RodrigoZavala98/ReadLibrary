import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/data/settings_store.dart';
import 'package:lector/domain/reading_settings.dart';

void main() {
  late Directory temp;
  late File file;
  late SettingsStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_ajustes_');
    file = File('${temp.path}${Platform.pathSeparator}reading.json');
    store = SettingsStore(file);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Relee desde disco, sin la caché en memoria del almacén que guardó.
  Future<ReadingSettings> releer() => SettingsStore(file).load();

  test('sin fichero devuelve los ajustes de fábrica', () async {
    expect(await store.load(), ReadingSettings());
  });

  test('lo guardado sobrevive a releer desde disco', () async {
    final elegidos = ReadingSettings(
      theme: ReadingTheme.oscuro,
      font: ReadingFont.openSans,
      fontSize: 23,
      lineHeight: 1.9,
      margin: 40,
      brightness: 0.35,
    );
    await store.save(elegidos);

    expect(await releer(), elegidos);
  });

  test('el brillo del sistema sigue siendo el del sistema al releer', () async {
    // Se guarda omitiendo la clave, no escribiendo un cero: si volviera como
    // cero, reabrir el libro apagaría la pantalla.
    await store.save(ReadingSettings(theme: ReadingTheme.sepia));

    final leidos = await releer();
    expect(leidos.usesSystemBrightness, isTrue);
    expect(leidos.brightness, isNull);
  });

  test('un fichero corrupto no impide leer, vuelve a fábrica', () async {
    await file.writeAsString('{esto no es json');
    expect(await releer(), ReadingSettings());
  });

  test('un JSON que no es un objeto tampoco revienta', () async {
    await file.writeAsString('[1, 2, 3]');
    expect(await releer(), ReadingSettings());
  });

  group('valores desconocidos', () {
    test('un tema que no existe cae al de por defecto', () async {
      // Puede venir de una versión más nueva de la aplicación: alguien la
      // instaló, eligió un tema que aquí no existe y volvió atrás.
      await file.writeAsString('{"version":1,"theme":"neón","font":"literata"}');
      expect((await releer()).theme, ReadingTheme.claro);
    });

    test('una fuente que no existe cae a Literata', () async {
      await file.writeAsString('{"version":1,"font":"ComicSans"}');
      expect((await releer()).font, ReadingFont.literata);
    });

    test('un número guardado como texto se ignora', () async {
      await file.writeAsString('{"version":1,"fontSize":"enorme"}');
      expect((await releer()).fontSize, 19);
    });

    test('un tamaño imposible se recorta al leerlo', () async {
      await file.writeAsString('{"version":1,"fontSize":900}');
      expect((await releer()).fontSize, ReadingSettings.maxFontSize);
    });
  });

  test('guardar dos veces deja lo último, no lo mezcla', () async {
    await store.save(ReadingSettings(fontSize: 21));
    await store.save(ReadingSettings(theme: ReadingTheme.sepia));

    final leidos = await releer();
    expect(leidos.theme, ReadingTheme.sepia);
    expect(leidos.fontSize, 19, reason: 'el segundo guardado manda entero');
  });

  test('los nombres se guardan como texto, no como posición', () async {
    // Si se guardara el índice de la enumeración, añadir un tema en medio
    // cambiaría los ajustes de quien ya tuviera la aplicación instalada.
    await store.save(ReadingSettings(theme: ReadingTheme.altoContraste));
    expect(await file.readAsString(), contains('"altoContraste"'));
  });
}
