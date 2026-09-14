import '../domain/library_book.dart';

/// Acceso a la biblioteca guardada.
///
/// Existe como interfaz —y no como una clase concreta— porque la
/// implementación actual escribe un índice JSON, y eso es una decisión que
/// probablemente haya que revisar. Un índice JSON se reescribe entero en cada
/// guardado: perfecto para los cientos de libros de una biblioteca personal,
/// insuficiente si algún día hay que buscar entre decenas de miles de
/// subrayados. Cuando llegue ese momento, se sustituye la clase de detrás sin
/// tocar nada más.
abstract interface class LibraryRepository {
  /// Todos los libros, del más recientemente abierto al más antiguo.
  Future<List<LibraryBook>> loadAll();

  Future<LibraryBook?> byId(int id);

  /// Inserta o reemplaza. El libro se identifica por su `id`.
  Future<void> save(LibraryBook book);

  /// Quita el libro del índice.
  ///
  /// No borra el fichero del libro en disco: eso es una decisión aparte que
  /// corresponde a quien llame, porque «quitar de la biblioteca» y «borrar el
  /// fichero» son cosas distintas para el usuario.
  Future<void> delete(int id);

  /// Un identificador libre para un libro nuevo.
  Future<int> nextId();
}
