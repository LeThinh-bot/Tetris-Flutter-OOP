import 'package:flutter/material.dart';
import 'tetris_page.dart';

void main() {
  runApp(const TetrisApp());
}

// ---------- App ----------
class TetrisApp extends StatelessWidget {
  const TetrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tetris Flutter Full FX',
      // Sử dụng theme tối
      theme: ThemeData.dark(useMaterial3: false), 
      home: const TetrisPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}