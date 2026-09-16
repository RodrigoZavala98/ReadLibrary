import 'package:flutter/material.dart';

import '../domain/book_format.dart';
import '../domain/library_book.dart';
import 'comic_reader_screen.dart';
import 'reader_screen.dart';

/// Abre un libro con el lector que le corresponde.
///
/// El reparto se hace por [LayoutKind] y no por formato, que es lo que permite
/// que añadir el PDF más adelante no toque ni esta función: un PDF es de página
/// fija igual que un CBZ, así que caerá solo del lado del lector de cómics.
///
/// Existe para que la decisión viva en **un solo sitio**. Antes la biblioteca y
/// Mi Refugio construían `ReaderScreen` cada una por su cuenta, y con dos
/// lectores eso significaría repetir el reparto en dos pantallas y olvidarse de
/// una la próxima vez.
Future<void> openBook(BuildContext context, LibraryBook book) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (book.format.layout) {
        LayoutKind.reflowable => ReaderScreen(book: book),
        LayoutKind.fixed => ComicReaderScreen(book: book),
      },
    ),
  );
}
