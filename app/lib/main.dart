import 'package:flutter/material.dart';

import 'app_services.dart';
import 'core/theme/app_theme.dart';
import 'shell/home_shell.dart';

Future<void> main() async {
  // Obligatorio antes de tocar path_provider: los canales con la parte nativa
  // no existen hasta que el enlace con el motor está inicializado.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LectorApp(services: await AppServices.create()));
}

class LectorApp extends StatelessWidget {
  const LectorApp({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'Lector',
        debugShowCheckedModeBanner: false,
        theme: ChromeTheme.build(),
        home: const HomeShell(),
      ),
    );
  }
}
