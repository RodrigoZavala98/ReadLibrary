import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector/domain/book_format.dart';
import 'package:lector/domain/book_locator.dart';
import 'package:lector/domain/book_source.dart';
import 'package:lector/formats/text_decoding.dart';
import 'package:lector/formats/txt_book_source.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lector_txt_');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<File> escribir(String nombre, String contenido) async {
    final file = File('${temp.path}${Platform.pathSeparator}$nombre');
    await file.writeAsString(contenido);
    return file;
  }

  test('abre un fichero y deduce el título del nombre', () async {
    final file = await escribir(
      'La_sombra_del_viento.txt',
      'Primero.\n\nSegundo.',
    );
    final source = TxtBookSource(file);
    await source.open();

    expect(source.format, BookFormat.txt);
    expect(source.info.title, 'La sombra del viento');
    expect(source.info.totalPages, isNull, reason: 'el texto se re-maqueta');
    await source.dispose();
  });

  test('un fichero que no existe da un error claro, no una excepción cruda',
      () async {
    final source = TxtBookSource(File('${temp.path}/no_existe.txt'));
    await expectLater(source.open(), throwsA(isA<BookOpenException>()));
  });

  test('usar la fuente sin abrirla avisa en lugar de fallar raro', () {
    final source = TxtBookSource(File('${temp.path}/x.txt'));
    expect(() => source.info, throwsStateError);
    expect(() => source.chapters, throwsStateError);
  });

  test('trocea un texto largo en varias partes navegables', () async {
    final contenido =
        List.generate(300, (i) => 'Párrafo $i. ${'palabra ' * 20}')
            .join('\n\n');
    final file = await escribir('largo.txt', contenido);
    final source = TxtBookSource(file, targetChars: 3000);
    await source.open();

    expect(source.chapters.length, greaterThan(3));
    expect(source.chapters.first.title, 'Parte 1');
    expect(source.chapters.first.start, const CharLocator(0));
    await source.dispose();
  });

  test('el progreso va de 0 a 1 de principio a fin', () async {
    final file = await escribir('p.txt', 'a' * 1000);
    final source = TxtBookSource(file);
    await source.open();

    expect(source.progressAt(const CharLocator(0)), 0);
    expect(source.progressAt(const CharLocator(500)), closeTo(0.5, 0.001));
    expect(source.progressAt(const CharLocator(1000)), 1);
    expect(
      source.progressAt(const CharLocator(99999)),
      1,
      reason: 'nunca debe pasar de 1',
    );
    await source.dispose();
  });

  test('una posición guardada devuelve el fragmento que hay que cargar',
      () async {
    final contenido =
        List.generate(300, (i) => 'Párrafo $i. ${'palabra ' * 20}')
            .join('\n\n');
    final file = await escribir('largo.txt', contenido);
    final source = TxtBookSource(file, targetChars: 3000);
    await source.open();

    final tercero = source.chapters[2];
    expect(source.chapterIndexFor(tercero.start), 2);
    await source.dispose();
  });

  group('conversión a HTML', () {
    test('cada párrafo va en su etiqueta', () async {
      final file = await escribir('h.txt', 'Uno.\n\nDos.\n\nTres.');
      final source = TxtBookSource(file);
      await source.open();

      expect(await source.loadChapter(0), '<p>Uno.</p><p>Dos.</p><p>Tres.</p>');
      await source.dispose();
    });

    test('los caracteres de HTML se escapan', () async {
      // Sin escapar, esto desaparecería al interpretarse como una etiqueta.
      final file = await escribir('e.txt', 'Si a < b & b > c, <vamos>');
      final source = TxtBookSource(file);
      await source.open();

      expect(
        await source.loadChapter(0),
        '<p>Si a &lt; b &amp; b &gt; c, &lt;vamos&gt;</p>',
      );
      await source.dispose();
    });

    test('pedir un capítulo inexistente da RangeError', () async {
      final file = await escribir('r.txt', 'Corto.');
      final source = TxtBookSource(file);
      await source.open();

      expect(() => source.loadChapter(99), throwsRangeError);
      expect(() => source.loadChapter(-1), throwsRangeError);
      await source.dispose();
    });
  });

  test('un fichero en Windows-1252 se lee con sus acentos intactos', () async {
    final file = File('${temp.path}${Platform.pathSeparator}cp1252.txt');
    // "El niño leyó" en cp1252: ñ=0xF1, ó=0xF3.
    await file.writeAsBytes([
      0x45, 0x6C, 0x20, 0x6E, 0x69, 0xF1, 0x6F, 0x20, //
      0x6C, 0x65, 0x79, 0xF3,
    ]);

    final source = TxtBookSource(file);
    await source.open();

    expect(source.encoding, TextEncodingUsed.windows1252);
    expect(await source.loadChapter(0), '<p>El niño leyó</p>');
    await source.dispose();
  });
}
