import 'dart:math' as math;

import 'package:flutter/material.dart';

/// OSHU Enterprises brand colours, taken from the shop logo.
abstract final class Brand {
  static const blue = Color(0xFF1E4FE0);
  static const red = Color(0xFFE5251E);
  static const yellow = Color(0xFFFFC400);
  static const navy = Color(0xFF0B1A45);
  static const green = Color(0xFF13945A);

  /// Page background: a soft blue wash instead of plain white.
  static const bgTop = Color(0xFFE4EBFB);
  static const bgBottom = Color(0xFFF1F3FA);

  static const ink = Color(0xFF16203A);
  static const muted = Color(0xFF677089);
  static const line = Color(0xFFD5DCEE);

  /// Header and login: navy into brand blue.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, Color(0xFF15307F), blue],
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.red,
    tertiary: Brand.yellow,
    surface: const Color(0xFFF8FAFF),
  ).copyWith(onSurface: Brand.ink, onSurfaceVariant: Brand.muted);

  final rounded14 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    colorScheme: scheme,
    // Pages are drawn on BrandBackground (see the page transitions below).
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _BrandPageTransitionsBuilder(),
        TargetPlatform.iOS: _BrandPageTransitionsBuilder(),
        TargetPlatform.windows: _BrandPageTransitionsBuilder(),
        TargetPlatform.macOS: _BrandPageTransitionsBuilder(),
        TargetPlatform.linux: _BrandPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _BrandPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1.5,
      shadowColor: Brand.navy.withValues(alpha: 0.18),
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder(Brand.line),
      enabledBorder: inputBorder(Brand.line),
      focusedBorder: inputBorder(Brand.blue, 2),
      errorBorder: inputBorder(Brand.red),
      focusedErrorBorder: inputBorder(Brand.red, 2),
      labelStyle: const TextStyle(color: Brand.muted),
      // Blue only for the field being typed in.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) {
        if (s.contains(WidgetState.error)) {
          return const TextStyle(color: Brand.red);
        }
        return s.contains(WidgetState.focused)
            ? const TextStyle(color: Brand.blue, fontWeight: FontWeight.w600)
            : const TextStyle(color: Brand.muted);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded14,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded14,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Brand.blue, width: 1.4),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.red,
      foregroundColor: Colors.white,
      elevation: 4,
      extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Brand.blue.withValues(alpha: 0.14),
      side: const BorderSide(color: Brand.line),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Brand.ink,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.blue : Colors.white,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Brand.ink,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: Brand.ink,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFF2F5FD),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: Brand.yellow,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Brand.blue,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Brand.ink,
      ),
      subtitleTextStyle: TextStyle(fontSize: 13.5, color: Brand.muted),
    ),
    dividerTheme: const DividerThemeData(color: Color(0x1A0B1A45)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.blue),
  );
}

/// Draws every page on [BrandBackground], then uses the normal Android
/// transition. Each page is opaque, so pages never show through each other.
class _BrandPageTransitionsBuilder extends PageTransitionsBuilder {
  const _BrandPageTransitionsBuilder();

  static const _inner = FadeForwardsPageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _inner.delegatedTransition;

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    BrandBackground(child: child),
  );
}

/// Soft blue page background with a faint gear and speed-line pattern.
/// [dark] is the navy/blue version used for the login screen and headers.
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: dark
            ? Brand.headerGradient
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Brand.bgTop, Brand.bgBottom],
              ),
      ),
      child: CustomPaint(
        painter: _PatternPainter(dark: dark),
        child: child,
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = dark ? Colors.white : Brand.blue;

    // Speed streaks, like the logo's motion lines.
    final streak = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final rnd = math.Random(7);
    for (var y = 40.0; y < size.height; y += 120) {
      for (var i = 0; i < 2; i++) {
        final x = rnd.nextDouble() * size.width;
        final len = 40 + rnd.nextDouble() * 70;
        streak.color = (i.isEven ? ink : Brand.red).withValues(
          alpha: dark ? 0.07 : 0.05,
        );
        canvas.drawLine(
          Offset(x, y + i * 14),
          Offset(x + len, y + i * 14),
          streak,
        );
      }
    }

    // A large gear watermark, partly off the bottom-right corner.
    final r = size.shortestSide * 0.62;
    final gear = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10
      ..color = ink.withValues(alpha: dark ? 0.08 : 0.055);
    canvas.drawPath(
      _gearPath(Offset(size.width * 0.92, size.height * 0.95), r),
      gear,
    );

    // And a small one top-left.
    final small = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.04
      ..color = Brand.red.withValues(alpha: dark ? 0.07 : 0.045);
    canvas.drawPath(
      _gearPath(Offset(size.width * 0.06, size.height * 0.16), r * 0.32),
      small,
    );
  }

  static Path _gearPath(Offset c, double r, {int teeth = 10}) {
    final outer = r, root = r * 0.86;
    final path = Path();
    final step = 2 * math.pi / teeth;
    for (var i = 0; i < teeth; i++) {
      final a = i * step;
      final pts = [
        (a - step * 0.30, root),
        (a - step * 0.18, outer),
        (a + step * 0.18, outer),
        (a + step * 0.30, root),
      ];
      for (final (j, (ang, rad)) in pts.indexed) {
        final p = c + Offset(math.cos(ang) * rad, math.sin(ang) * rad);
        if (i == 0 && j == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    path.close();
    path.addOval(Rect.fromCircle(center: c, radius: r * 0.55));
    return path;
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.dark != dark;
}

/// A gradient panel with the dark pattern, for screen headers.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BrandBackground(
        dark: true,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A white rounded card holding one list row.
class TileCard extends StatelessWidget {
  const TileCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? child
          : InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
    );
  }
}

/// A white card with an optional title, for grouping a screen's content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.trailing,
  });

  final String? title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: Brand.blue),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A big number with a label, for summary cards.
class StatBox extends StatelessWidget {
  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.color = Brand.blue,
    this.icon,
  });

  final String label;
  final String value;
  final String? note;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Brand.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (note != null)
              Text(
                note!,
                style: const TextStyle(fontSize: 12, color: Brand.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gear "O" mark plus the OSHU / ENTERPRISES wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.markSize = 120, this.onDark = false});

  final double markSize;

  /// Light text colours for use on the dark header gradient.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final wordSize = markSize * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/logo_mark.png',
          width: markSize,
          height: markSize,
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'O',
                style: TextStyle(color: Brand.red),
              ),
              TextSpan(
                text: 'SHU',
                style: TextStyle(color: onDark ? Colors.white : Brand.blue),
              ),
            ],
          ),
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
