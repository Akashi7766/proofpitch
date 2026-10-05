import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';

class C {
  static const cream = Color(0xFFFFF4E0);
  static const ink = Color(0xFF111111);
  static const lime = Color(0xFFC6FF3D);
  static const pink = Color(0xFFFF5CA8);
  static const blue = Color(0xFF3D5AFE);
  static const yellow = Color(0xFFFFD23F);
  static const red = Color(0xFFFF4D2E);
  static const white = Colors.white;
}

const border = BorderSide(color: C.ink, width: 2);
const muted = Color(0xFF5C5C5C);

TextStyle display([double size = 28, Color color = C.ink]) =>
    GoogleFonts.archivoBlack(fontSize: size, color: color, height: 1.05, letterSpacing: -0.5);

ThemeData buildTheme() {
  final body = GoogleFonts.spaceGroteskTextTheme(const TextTheme(
    bodyMedium: TextStyle(fontSize: 15, height: 1.45),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45),
  )).apply(bodyColor: C.ink, displayColor: C.ink);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: C.cream,
    colorScheme: ColorScheme.fromSeed(seedColor: C.blue, surface: C.cream, primary: C.ink),
    textTheme: body,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: C.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: display(22),
      iconTheme: const IconThemeData(color: C.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.white,
      labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: C.ink),
      enabledBorder: const OutlineInputBorder(borderSide: border, borderRadius: BorderRadius.zero),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: C.blue, width: 3), borderRadius: BorderRadius.zero),
      border: const OutlineInputBorder(borderSide: border, borderRadius: BorderRadius.zero),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _SpringTransitions(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.ink,
      contentTextStyle: GoogleFonts.spaceGrotesk(color: C.lime, fontWeight: FontWeight.w700),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
    ),
  );
}

/// Pages slide up and overshoot a touch.
class _SpringTransitions extends PageTransitionsBuilder {
  const _SpringTransitions();
  @override
  Widget buildTransitions<T>(route, context, animation, secondary, child) {
    final a = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

/// The core brutal surface: hard offset shadow that collapses when pressed, plus a haptic tick.
class Brutal extends StatefulWidget {
  const Brutal({
    super.key,
    required this.child,
    this.onTap,
    this.color = C.white,
    this.shadow = 4,
    this.padding = const EdgeInsets.all(16),
    this.tilt = 0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double shadow;
  final EdgeInsets padding;

  /// Resting rotation in degrees; straightens on press.
  final double tilt;

  @override
  State<Brutal> createState() => _BrutalState();
}

class _BrutalState extends State<Brutal> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = _down ? 0.0 : widget.shadow;
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedRotation(
        turns: (_down ? 0 : widget.tilt) / 360,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(widget.shadow - s, widget.shadow - s, 0),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.color,
            border: Border.fromBorderSide(border),
            boxShadow: [BoxShadow(color: C.ink, offset: Offset(s, s))],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class BrutalButton extends StatelessWidget {
  const BrutalButton(this.label, {super.key, this.onTap, this.color = C.lime, this.icon, this.big = false});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;
  final bool big;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Brutal(
          onTap: onTap,
          color: color,
          shadow: big ? 6 : 4,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: big ? 18 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, color: C.ink, size: big ? 24 : 20), const SizedBox(width: 8)],
              Flexible(child: Text(label.toUpperCase(), style: display(big ? 20 : 15), textAlign: TextAlign.center)),
            ],
          ),
        ),
      );
}

/// Slightly rotated label, like a sticker slapped on a laptop.
class Sticker extends StatelessWidget {
  const Sticker(this.text, {super.key, this.color = C.yellow, this.angle = -3});
  final String text;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle * pi / 180,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: C.ink, width: 2),
            boxShadow: const [BoxShadow(color: C.ink, offset: Offset(2, 2))],
          ),
          child: Text(text, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, fontSize: 12, color: C.ink)),
        ),
      );
}

class BrutalChip extends StatelessWidget {
  const BrutalChip(this.label, {super.key, required this.selected, required this.onTap, this.color = C.pink});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Brutal(
        onTap: onTap,
        color: selected ? color : C.white,
        shadow: selected ? 1 : 3,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
      );
}

/// Slams its child in like a rubber stamp. Change [key] to replay.
class Stamp extends StatelessWidget {
  const Stamp({super.key, required this.child, this.angle = -8});
  final Widget child;
  final double angle;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        onEnd: () => HapticFeedback.heavyImpact(),
        builder: (_, t, c) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.rotate(angle: angle * pi / 180, child: Transform.scale(scale: 2.2 - 1.2 * t, child: c)),
        ),
        child: child,
      );
}

class StampLabel extends StatelessWidget {
  const StampLabel(this.text, {super.key, this.color = C.red, this.size = 30});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: color, width: 4)),
        child: Text(text, style: display(size, color)),
      );
}

/// Shakes its child horizontally once whenever [trigger] changes.
class Shake extends StatelessWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final Object trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(trigger),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        builder: (_, t, c) => Transform.translate(offset: Offset(sin(t * pi * 6) * 10 * (1 - t), 0), child: c),
        child: child,
      );
}

/// One-shot confetti burst of chunky brutal rectangles.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  final _bits = List.generate(42, (i) {
    final r = Random(i * 7 + 3);
    return (r.nextDouble() * 2 * pi, 220 + r.nextDouble() * 260, r.nextDouble() * 10, [C.lime, C.pink, C.blue, C.yellow][i % 4]);
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(size: Size.infinite, painter: _Confetti(_c.value, _bits))),
      );
}

class _Confetti extends CustomPainter {
  _Confetti(this.t, this.bits);
  final double t;
  final List<(double, double, double, Color)> bits;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width / 2, size.height * 0.45);
    final e = Curves.easeOutCubic.transform(t);
    final fill = Paint();
    final stroke = Paint()
      ..color = C.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (angle, dist, spin, color) in bits) {
      final p = o + Offset(cos(angle), sin(angle)) * dist * e + Offset(0, 300 * t * t); // gravity
      canvas
        ..save()
        ..translate(p.dx, p.dy)
        ..rotate(spin * t * 4);
      final r = Rect.fromCenter(center: Offset.zero, width: 14, height: 8);
      fill.color = color.withValues(alpha: 1 - t * t);
      stroke.color = C.ink.withValues(alpha: 1 - t * t);
      canvas
        ..drawRect(r, fill)
        ..drawRect(r, stroke)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.t != t;
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.emoji, this.title, this.subtitle, {super.key, this.action});
  final String emoji;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(title, style: display(24), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

const channelColor = {
  Channel.directEmail: C.lime,
  Channel.modernAts: C.yellow,
  Channel.enterpriseAts: Color(0xFFD9D9D9),
  Channel.customPortal: Color(0xFF9AD8FF),
};

/// Small flat label: readable metadata, no rotation.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = C.white, this.textColor = C.ink});
  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, border: Border.all(color: C.ink, width: 1.5)),
        child: Text(text, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 12, color: textColor)),
      );
}

Color matchColor(int? score) => switch (score) {
      null => C.white,
      >= 70 => C.lime,
      >= 40 => C.yellow,
      _ => const Color(0xFFFFD6CC),
    };

class MatchBadge extends StatelessWidget {
  const MatchBadge(this.score, {super.key});
  final int? score;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: matchColor(score),
          border: Border.all(color: C.ink, width: 2),
          boxShadow: const [BoxShadow(color: C.ink, offset: Offset(2, 2))],
        ),
        child: Text(score == null ? '? match' : '$score% match', style: display(12)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: display(18))),
          ?trailing,
        ]),
      );
}

/// A brutal heart that pops when toggled.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.saved, required this.onTap});
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(saved),
            tween: Tween(begin: saved ? 0.4 : 1, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, t, c) => Transform.scale(scale: t, child: c),
            child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved ? C.pink : C.ink, size: 26),
          ),
        ),
      );
}
