import 'dart:convert';
import 'dart:io';

import '../domain/reading_streak.dart';

/// Historial de sesiones de lectura.
///
/// Es un fichero JSON que se acumula sin borrar nada, porque la racha más larga
/// se calcula sobre todo el historial y no tendría sentido perderla. Un lector
/// intenso genera unas cuatro sesiones al día: en cinco años son unas 7.000
/// entradas, algo más de medio megabyte. Se carga entero en memoria al arrancar
/// y tarda milisegundos, así que el techo queda lejos — pero está ahí, y si
/// alguna vez molesta, la salida es guardar totales por día en lugar de
/// sesiones sueltas.
class SessionStore {
  SessionStore(this.file);

  final File file;

  File get _tempFile => File('${file.path}.tmp');

  List<ReadingSession>? _cache;

  Future<List<ReadingSession>> loadAll() async {
    return _cache ??= await _readFromDisk();
  }

  /// Añade una sesión al historial.
  Future<void> add(ReadingSession session) async {
    final sessions = await loadAll();
    sessions.add(session);
    await _flush(sessions);
  }

  Future<List<ReadingSession>> _readFromDisk() async {
    if (!await file.exists()) return [];

    final Object? parsed;
    try {
      parsed = jsonDecode(await file.readAsString());
    } on Object {
      // Igual que con la biblioteca: un historial ilegible no debe impedir
      // leer. Se pierde la racha, que es reconstruible leyendo; no los libros.
      return [];
    }
    if (parsed is! Map || parsed['sessions'] is! List) return [];

    final sessions = <ReadingSession>[];
    for (final raw in parsed['sessions'] as List) {
      if (raw is! Map) continue;
      final started = DateTime.tryParse('${raw['startedAt']}');
      final seconds = raw['seconds'];
      final bookId = raw['bookId'];
      if (started == null || seconds is! int || bookId is! int) continue;
      if (seconds <= 0) continue;

      sessions.add(
        ReadingSession(
          startedAt: started.toLocal(),
          duration: Duration(seconds: seconds),
          bookId: bookId,
        ),
      );
    }
    return sessions;
  }

  Future<void> _flush(List<ReadingSession> sessions) async {
    _cache = sessions;
    await file.parent.create(recursive: true);

    final payload = jsonEncode({
      'version': 1,
      'sessions': [
        for (final s in sessions)
          {
            'startedAt': s.startedAt.toUtc().toIso8601String(),
            'seconds': s.duration.inSeconds,
            'bookId': s.bookId,
          },
      ],
    });

    // El historial se reescribe entero en cada sesión nueva, así que vale la
    // misma precaución que en la biblioteca: se escribe aparte y se renombra
    // encima, para que un corte a mitad no deje el fichero truncado.
    await _tempFile.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await _tempFile.rename(file.path);
  }
}
