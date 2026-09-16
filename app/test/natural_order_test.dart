import 'package:flutter_test/flutter_test.dart';
import 'package:lector/formats/natural_order.dart';

void main() {
  /// Ordena como lo haría el lector de cómics.
  List<String> ordenar(List<String> nombres) =>
      [...nombres]..sort(compareNatural);

  test('el diez va después del dos, no entre el uno y el dos', () {
    // Éste es el fallo que justifica todo el fichero: con el orden alfabético
    // de toda la vida, «pagina10» cae entre «pagina1» y «pagina2» y el cómic
    // se lee barajado.
    expect(
      ordenar(['pagina10.jpg', 'pagina2.jpg', 'pagina1.jpg']),
      ['pagina1.jpg', 'pagina2.jpg', 'pagina10.jpg'],
    );
  });

  test('cien páginas quedan en su sitio', () {
    final nombres = [for (var i = 1; i <= 100; i++) 'p$i.jpg']..shuffle();
    expect(ordenar(nombres), [for (var i = 1; i <= 100; i++) 'p$i.jpg']);
  });

  test('los ceros a la izquierda no cambian el valor', () {
    expect(ordenar(['p007.jpg', 'p8.jpg', 'p06.jpg']), [
      'p06.jpg',
      'p007.jpg',
      'p8.jpg',
    ]);
  });

  test('dos escrituras del mismo número quedan en orden estable', () {
    // Valen lo mismo, así que desempata el texto. Sin desempate quedarían en
    // el orden en que los devolviera el ZIP, que no es igual en toda máquina.
    expect(ordenar(['p7.jpg', 'p07.jpg']), ['p07.jpg', 'p7.jpg']);
  });

  test('los números se comparan en cada tramo, no sólo en el primero', () {
    expect(
      ordenar([
        'cap2/pagina10.jpg',
        'cap10/pagina1.jpg',
        'cap2/pagina9.jpg',
      ]),
      ['cap2/pagina9.jpg', 'cap2/pagina10.jpg', 'cap10/pagina1.jpg'],
    );
  });

  test('un número va antes que una letra en la misma posición', () {
    expect(ordenar(['portada.jpg', '2.jpg']), ['2.jpg', 'portada.jpg']);
  });

  test('sin dígitos se comporta como el orden alfabético', () {
    expect(ordenar(['beta.jpg', 'alfa.jpg']), ['alfa.jpg', 'beta.jpg']);
  });

  test('las mayúsculas no separan páginas que van juntas', () {
    // Con el orden alfabético crudo, todas las mayúsculas van antes que
    // cualquier minúscula, así que «Pagina2» se iría al principio del cómic.
    expect(ordenar(['pagina1.jpg', 'Pagina2.jpg', 'pagina3.jpg']), [
      'pagina1.jpg',
      'Pagina2.jpg',
      'pagina3.jpg',
    ]);
  });

  test('un nombre que es prefijo de otro va primero', () {
    expect(ordenar(['pagina1b.jpg', 'pagina1.jpg']), [
      'pagina1.jpg',
      'pagina1b.jpg',
    ]);
  });

  test('una tira de dígitos enorme no desborda', () {
    // Hay quien numera pegando la fecha y un identificador. Con int.parse esto
    // lanzaría en mitad de la apertura del libro.
    final enorme = '9' * 40;
    final mayor = '${'9' * 39}8';
    expect(ordenar(['p$enorme.jpg', 'p$mayor.jpg']), [
      'p$mayor.jpg',
      'p$enorme.jpg',
    ]);
  });
}
