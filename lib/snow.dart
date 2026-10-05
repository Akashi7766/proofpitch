import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme.dart';

// ───────────────────────── The ❄️ cold-pitch look ─────────────────────────
// Same neo-brutalist bones (2px borders, hard shadows) in ice colours, with snow drifting behind.

class Ice {
  static const top = Color(0xFFE6F5FF);
  static const bottom = Color(0xFFA8D5F2);
  static const ink = Color(0xFF1D4E89); // borders, shadows and headings on ice
  static const frost = Color(0xE6FFFFFF); // cards: white, a little see-through so the snow shows
  static const glow = Color(0xFF7CC4F0);
}

const iceBackground = BoxDecoration(
  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Ice.top, Ice.bottom]),
);

/// Flakes drifting down behind the content. Cheap: one painter, no widgets per flake.
class Snowfall extends StatefulWidget {
  const Snowfall({super.key, this.count = 70});
  final int count;
  @override
  State<Snowfall> createState() => _SnowfallState();
}

class _SnowfallState extends State<Snowfall> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final _flakes = List.generate(widget.count, (i) {
    final r = Random(i * 31 + 7);
    // x, start y, fall speed (screens per minute), size, sway amplitude, sway phase
    return (r.nextDouble(), r.nextDouble(), 4 + r.nextDouble() * 8, 1.6 + r.nextDouble() * 3.4, 6 + r.nextDouble() * 18, r.nextDouble() * pi * 2);
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(size: Size.infinite, painter: _Snow(_c.value, _flakes))),
        ),
      );
}

class _Snow extends CustomPainter {
  _Snow(this.t, this.flakes);
  final double t; // 0..1 over a minute
  final List<(double, double, double, double, double, double)> flakes;

  @override
  void paint(Canvas canvas, Size size) {
    final halo = Paint()..color = Ice.glow.withValues(alpha: 0.35);
    final flake = Paint()..color = Colors.white;
    for (final (x, y0, speed, r, sway, phase) in flakes) {
      final y = ((y0 + t * speed) % 1.08 - 0.04) * size.height;
      final dx = sin(t * 2 * pi * speed / 2 + phase) * sway;
      final p = Offset(x * size.width + dx, y);
      canvas
        ..drawCircle(p, r + 1.2, halo) // a soft blue rim so white flakes show on the pale ice
        ..drawCircle(p, r, flake);
    }
  }

  @override
  bool shouldRepaint(_Snow old) => old.t != t;
}

/// A frosted brutal card.
class IceCard extends StatelessWidget {
  const IceCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.color = Ice.frost});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Ice.ink, width: 2),
            boxShadow: const [BoxShadow(color: Ice.ink, offset: Offset(4, 4))],
          ),
          child: child,
        ),
      );
}

/// 🔥 Jobs | ❄️ Cold pitch: the switch at the top of HUNT.
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.cold, required this.onChanged});
  final bool cold;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget side(String label, bool on, bool isCold) => Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(isCold);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              color: on ? (isCold ? Ice.glow : C.lime) : Colors.transparent,
              child: Text(label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, fontSize: 15, color: cold ? Ice.ink : C.ink)),
            ),
          ),
        );
    final ink = cold ? Ice.ink : C.ink;
    return Container(
      decoration: BoxDecoration(
        color: cold ? Ice.frost : C.white,
        border: Border.all(color: ink, width: 2),
        boxShadow: [BoxShadow(color: ink, offset: const Offset(3, 3))],
      ),
      child: Row(children: [side('🔥 Jobs', !cold, false), Container(width: 2, height: 40, color: ink), side('❄️ Cold pitch', cold, true)]),
    );
  }
}
