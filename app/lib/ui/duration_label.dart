/// Cómo se escribe una duración en la interfaz.
///
/// Está aparte porque aparece en media docena de sitios de Mi Viaje —el total
/// del mes, la media por día, el mejor día, el resumen global— y en todos tiene
/// que leerse igual.
///
/// Nunca se muestran segundos: en un contador de lectura no aportan nada y
/// convierten una cifra que se lee de un vistazo en una que hay que descifrar.
String formatDuration(Duration value) {
  final minutes = value.inMinutes;
  if (minutes < 60) return '$minutes min';

  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}
