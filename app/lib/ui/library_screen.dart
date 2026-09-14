import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../core/theme/app_theme.dart';
import '../data/book_importer.dart';
import '../domain/book_format.dart';
import '../domain/library_book.dart';
import 'reader_screen.dart';

/// La biblioteca: lo que hay, y el botón para añadir más.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<LibraryBook>? _books;
  bool _importing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_books == null) _reload();
  }

  Future<void> _reload() async {
    final books = await AppScope.of(context).repository.loadAll();
    if (mounted) setState(() => _books = books);
  }

  Future<void> _pickAndImport() async {
    if (_importing) return;
    setState(() => _importing = true);
    final importer = AppScope.of(context).importer;

    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Elige un libro',
        type: FileType.custom,
        // Se ofrecen también los formatos aún no soportados: es mejor que el
        // usuario los vea y reciba una explicación a que parezcan invisibles.
        allowedExtensions: [
          for (final format in BookFormat.values) ...format.extensions,
        ],
      );
      final path = picked?.path;
      if (path == null) return;

      final result = await importer.import(File(path));
      if (!mounted) return;

      switch (result) {
        case ImportedOk(:final book):
          await _reload();
          _say('«${book.title}» añadido a tu biblioteca.');
        case AlreadyInLibrary(:final existing):
          _say('«${existing.title}» ya estaba en tu biblioteca.');
        case UnsupportedFormat(:final reason):
          _say(reason);
        case UnknownFormat(:final fileName):
          _say('No reconozco «$fileName» como un libro.');
        case ImportFailed(:final message):
          _say(message);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _open(LibraryBook book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderScreen(book: book)),
    );
    // Al volver, el progreso puede haber cambiado.
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;

    return Stack(
      children: [
        if (books == null)
          const Center(child: CircularProgressIndicator())
        else if (books.isEmpty)
          _EmptyLibrary(onAdd: _pickAndImport)
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _BookTile(
              book: books[i],
              onTap: () => _open(books[i]),
            ),
          ),
        if (books != null && books.isNotEmpty)
          Positioned(
            right: 20,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: _importing ? null : _pickAndImport,
              backgroundColor: ChromeTheme.accent,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: ChromeTheme.textMuted,
            ),
            const SizedBox(height: 20),
            const Text(
              'Tu biblioteca está vacía',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ChromeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Añade un EPUB, un PDF, un cómic en CBZ\no un fichero de texto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ChromeTheme.textMuted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Añadir un libro'),
              style: FilledButton.styleFrom(
                backgroundColor: ChromeTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ChromeTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverPlaceholder(title: book.title),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ChromeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author ?? book.format.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: ChromeTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (book.isStarted)
                      _Progress(value: book.progress)
                    else
                      const Text(
                        'Sin empezar',
                        style: TextStyle(
                          fontSize: 12,
                          color: ChromeTheme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: ChromeTheme.surfaceHigh,
            valueColor: const AlwaysStoppedAnimation(ChromeTheme.accent),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${(value * 100).round()} %',
          style: const TextStyle(fontSize: 11, color: ChromeTheme.textMuted),
        ),
      ],
    );
  }
}

/// Hasta que se extraigan las portadas reales, una tarjeta con la inicial.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return Container(
      width: 46,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [ChromeTheme.surfaceHigh, ChromeTheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: ChromeTheme.surfaceHigh),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: ChromeTheme.accentSoft,
        ),
      ),
    );
  }
}
