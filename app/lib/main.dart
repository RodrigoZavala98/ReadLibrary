import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'shell/home_shell.dart';

void main() {
  runApp(const LectorApp());
}

class LectorApp extends StatelessWidget {
  const LectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lector',
      debugShowCheckedModeBanner: false,
      theme: ChromeTheme.build(),
      home: const HomeShell(),
    );
  }
}
