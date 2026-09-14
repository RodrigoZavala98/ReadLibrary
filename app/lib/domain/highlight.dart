import 'book_locator.dart';

/// Una frase guardada de un libro.
///
/// Es contenido de primera clase, no un adorno: hay lectores para los que los
/// subrayados son el verdadero producto de haber leído. Por eso «Mis Notas» es
/// una sección propia y no una pestaña escondida dentro del perfil.
class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.text,
    required this.createdAt,
    required this.locator,
    this.note,
    this.color = HighlightColor.amber,
    this.chapterTitle,
  });

  final int id;
  final int bookId;

  /// El texto tal cual se subrayó.
  ///
  /// Se guarda una copia literal en lugar de sólo la posición. Es duplicar
  /// datos a propósito: si el usuario reemplaza el fichero del libro por otra
  /// edición, el localizador dejará de apuntar al sitio correcto, pero la
  /// frase seguirá ahí. Perder una cita guardada es de las cosas que peor
  /// sientan en un lector.
  final String text;

  /// Comentario propio del usuario sobre la frase.
  final String? note;

  final HighlightColor color;
  final DateTime createdAt;

  /// Dónde estaba en el libro, para poder volver a ese punto.
  final BookLocator locator;

  /// Capítulo en que se subrayó, si el formato lo sabe. Sirve para agrupar en
  /// la lista sin tener que abrir el libro.
  final String? chapterTitle;

  bool get hasNote => note != null && note!.trim().isNotEmpty;

  /// Versión recortada para listas, sin cortar palabras por la mitad.
  String preview({int maxChars = 120}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxChars) return clean;
    final cut = clean.lastIndexOf(' ', maxChars);
    return '${clean.substring(0, cut > 0 ? cut : maxChars)}…';
  }

  Highlight copyWith({String? note, HighlightColor? color}) {
    return Highlight(
      id: id,
      bookId: bookId,
      text: text,
      createdAt: createdAt,
      locator: locator,
      note: note ?? this.note,
      color: color ?? this.color,
      chapterTitle: chapterTitle,
    );
  }
}

/// Colores de subrayado.
///
/// Cuatro y no más: con una paleta larga el usuario se inventa un sistema de
/// clasificación que luego no recuerda, y los colores dejan de significar nada.
enum HighlightColor { amber, rose, teal, violet }
