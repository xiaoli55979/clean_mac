import 'package:flutter/material.dart';

import 'home_page.dart';

void main() {
  runApp(const CleanMacApp());
}

class CleanMacApp extends StatelessWidget {
  const CleanMacApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0A84FF);
    return MaterialApp(
      title: 'CleanMac',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      home: const HomePage(),
    );
  }
}
