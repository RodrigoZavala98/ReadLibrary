import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'data/book_importer.dart';
import 'data/json_library_repository.dart';
import 'data/library_repository.dart';
import 'data/profile_store.dart';
import 'data/session_store.dart';

/// Las dependencias de la aplicación, construidas una vez al arrancar.
///
/// Se pasan explícitamente en lugar de usar variables globales para que las
/// pruebas puedan montar la aplicación entera sobre un directorio temporal.
class AppServices {
  const AppServices({
    required this.repository,
    required this.importer,
    required this.sessions,
    required this.profile,
  });

  final LibraryRepository repository;
  final BookImporter importer;
  final SessionStore sessions;
  final ProfileStore profile;

  /// Monta los servicios sobre el almacenamiento privado de la aplicación.
  ///
  /// `getApplicationDocumentsDirectory` devuelve una ruta interna que solo esta
  /// aplicación puede leer, y que sobrevive a los reinicios sin depender de
  /// ningún permiso — al contrario que el almacenamiento externo.
  static Future<AppServices> create() async {
    final docs = await getApplicationDocumentsDirectory();
    return forDirectory(docs);
  }

  /// Igual, pero sobre un directorio concreto. Lo usan las pruebas.
  static AppServices forDirectory(Directory root) {
    final sep = Platform.pathSeparator;
    final repository = JsonLibraryRepository(
      File('${root.path}${sep}library.json'),
    );
    return AppServices(
      repository: repository,
      importer: BookImporter(
        repository: repository,
        libraryDir: Directory('${root.path}${sep}books'),
      ),
      sessions: SessionStore(File('${root.path}${sep}sessions.json')),
      profile: ProfileStore(File('${root.path}${sep}profile.json')),
    );
  }
}

/// Pone los servicios al alcance de cualquier pantalla.
class AppScope extends InheritedWidget {
  const AppScope({required this.services, required super.child, super.key});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'Falta un AppScope por encima de este widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.services != services;
}
