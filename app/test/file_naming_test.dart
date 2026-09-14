import 'package:flutter_test/flutter_test.dart';
import 'package:lector/formats/file_naming.dart';

void main() {
  group('título a partir del nombre', () {
    test('quita la extensión y los guiones bajos', () {
      expect(titleFromFileName('El_nombre_del_viento.epub'),
          'El nombre del viento');
    });

    test('funciona con rutas de Windows y de Unix', () {
      expect(titleFromFileName(r'C:\libros\Dune.txt'), 'Dune');
      expect(titleFromFileName('/datos/libros/Dune.txt'), 'Dune');
    });

    test('un nombre con puntos conserva todo menos la extensión', () {
      expect(titleFromFileName('El.Señor.de.los.Anillos.epub'),
          'El.Señor.de.los.Anillos');
    });

    test('sin extensión devuelve el nombre entero', () {
      expect(titleFromFileName('LEEME'), 'LEEME');
    });

    test('colapsa los espacios repetidos', () {
      expect(titleFromFileName('dune   —   herbert.txt'), 'dune — herbert');
    });
  });

  group('saneado para escribir en disco', () {
    test('elimina cualquier intento de salir de la carpeta', () {
      expect(safeFileName('../../datos.db'), 'datos.db');
      expect(safeFileName(r'..\..\windows\system32\x.txt'), 'x.txt');
      expect(safeFileName('/etc/passwd'), 'passwd');
    });

    test('sustituye los caracteres prohibidos en Windows', () {
      expect(safeFileName('cap:1?.txt'), 'cap_1_.txt');
      expect(safeFileName('a<b>c|d.txt'), 'a_b_c_d.txt');
    });

    test('un nombre formado solo por puntos no se queda vacío', () {
      expect(safeFileName('...'), 'libro');
      expect(safeFileName(''), 'libro');
    });

    test('recorta los nombres larguísimos conservando la extensión', () {
      final largo = '${'a' * 200}.epub';
      final safe = safeFileName(largo);
      expect(safe.length, lessThanOrEqualTo(80));
      expect(safe, endsWith('.epub'));
    });

    test('deja en paz un nombre normal', () {
      expect(safeFileName('Dune - Frank Herbert.epub'),
          'Dune - Frank Herbert.epub');
    });

    test('conserva acentos y eñes', () {
      expect(safeFileName('El niño.txt'), 'El niño.txt');
    });
  });
}
