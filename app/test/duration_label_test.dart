import 'package:flutter_test/flutter_test.dart';
import 'package:lector/ui/duration_label.dart';

void main() {
  test('sin nada leído', () {
    expect(formatDuration(Duration.zero), '0 min');
  });

  test('por debajo de la hora sólo se enseñan minutos', () {
    expect(formatDuration(const Duration(minutes: 45)), '45 min');
  });

  test('los segundos no se enseñan nunca', () {
    // 90 segundos es un minuto y medio: se redondea hacia abajo en lugar de
    // sacar un «1 min 30 s» que nadie necesita leer en una estadística.
    expect(formatDuration(const Duration(seconds: 90)), '1 min');
    expect(formatDuration(const Duration(seconds: 59)), '0 min');
  });

  test('una hora justa no arrastra «0 min»', () {
    expect(formatDuration(const Duration(hours: 3)), '3 h');
  });

  test('horas con minutos', () {
    expect(formatDuration(const Duration(hours: 6, minutes: 20)), '6 h 20 min');
  });

  test('a partir de 24 horas se siguen contando horas', () {
    // No hay unidad «días» a propósito: «2 d 3 h» obliga a hacer cuentas para
    // comparar con la cifra del mes pasado.
    expect(formatDuration(const Duration(hours: 51, minutes: 5)), '51 h 5 min');
  });
}
