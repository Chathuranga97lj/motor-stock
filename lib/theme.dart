import 'dart:math' as math;

import 'package:flutter/material.dart';

/// OSHU Enterprises brand colours, taken from the shop logo.
abstract final class Brand {
  static const blue = Color(0xFF1E4FE0);
  static const red = Color(0xFFE5251E);
  static const yellow = Color(0xFFFFC400);
  static const navy = Color(0xFF0B1A45);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.red,
    tertiary: Brand.yellow,
  );
  return ThemeData(
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.navy,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.red,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme:
        const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// Gear "O" mark plus the OSHU / ENTERPRISES wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.markSize = 120});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final wordSize = markSize * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/logo_mark.png',
            width: markSize, height: markSize),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'O', style: TextStyle(color: Brand.red)),
            const TextSpan(text: 'SHU', style: TextStyle(color: Brand.blue)),
          ]),
          style: TextStyle(
            fontSize: wordSize,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 1,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Transform(
          transform: Matrix4.skewX(-math.pi / 14),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              border: Border(bottom: BorderSide(color: Brand.red, width: 3)),
            ),
            child: Text(
              'ENTERPRISES',
              style: TextStyle(
                color: Brand.yellow,
                fontSize: wordSize * 0.36,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
