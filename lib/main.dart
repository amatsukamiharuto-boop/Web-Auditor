import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';

void main() {
  runApp(const WebAuditorApp());
}

class WebAuditorApp extends StatelessWidget {
  const WebAuditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1565C0);

    return MaterialApp(
      title: 'Web Auditor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
