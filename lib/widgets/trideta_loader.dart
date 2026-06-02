import 'package:flutter/material.dart';
import 'dart:math' as math;

class TridetaLoader extends StatefulWidget {
  final double size;
  final Color color;

  const TridetaLoader({
    super.key,
    this.size = 50.0,
    this.color = const Color(0xFF007ACC), // Trideta Blue
  });

  @override
  State<TridetaLoader> createState() => _TridetaLoaderState();
}

class _TridetaLoaderState extends State<TridetaLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Full cycle: cascade fall + brief hold + snap reset
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Books need roughly 2.6× more width than height to match the reference
    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _BookShelfPainter(
              progress: _controller.value,
              color: widget.color,
              size: widget.size,
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Draws the shelf + books and animates a left-to-right domino-fall cascade.
// ─────────────────────────────────────────────────────────────────────────────
class _BookShelfPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double size;

  const _BookShelfPainter({
    required this.progress,
    required this.color,
    required this.size,
  });

  // Smooth ease-in-out curve
  static double _ease(double t) => t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;

  @override
  void paint(Canvas canvas, Size cs) {
    // ── Stroke paint (books & shelf accent) ──────────────────────────────
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size * 0.035)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotFill = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    // ── Shelf geometry ────────────────────────────────────────────────────
    final shelfY = cs.height * 0.84;
    final shelfLeft = cs.width * 0.06;
    final shelfRight = cs.width * 0.94;

    // Dotted shelf line
    final dotR = math.max(1.0, size * 0.018);
    final dotStep = size * 0.09;
    double dx = shelfLeft;
    while (dx <= shelfRight) {
      canvas.drawCircle(Offset(dx, shelfY), dotR, dotFill);
      dx += dotStep;
    }

    // ── Book definitions ──────────────────────────────────────────────────
    // [relative x-centre from left edge, height as fraction of cs.height]
    const int n = 5;
    final bookCentres = [0.16, 0.29, 0.42, 0.55, 0.68]; // x%
    final bookHFrac = [0.62, 0.72, 0.56, 0.66, 0.60]; // height%
    final bookW = cs.width * 0.095;

    // ── Animation timing ─────────────────────────────────────────────────
    // progress 0 → 0.70 : cascade fall (each book gets a 0.14-wide window)
    // progress 0.70 → 0.82 : all fully fallen (brief hold)
    // progress 0.82 → 1.00 : all snap back upright together
    const double cascadeEnd = 0.70;
    const double holdEnd = 0.82;
    const double maxLean = 0.58; // radians ≈ 33°

    for (int i = 0; i < n; i++) {
      final bookCx = cs.width * bookCentres[i];
      final bookH = cs.height * bookHFrac[i];

      double rotation;

      if (progress < holdEnd) {
        // Fall phase: book i starts at progress = i/n * cascadeEnd
        final fallStart = (i / n) * cascadeEnd;
        final fallEnd = fallStart + cascadeEnd / n;

        if (progress <= fallStart) {
          rotation = 0.0;
        } else if (progress <= fallEnd) {
          final t = (progress - fallStart) / (fallEnd - fallStart);
          rotation = _ease(t) * maxLean;
        } else {
          rotation = maxLean;
        }
      } else {
        // Snap-reset phase: all books rise together
        final t = (progress - holdEnd) / (1.0 - holdEnd);
        rotation = maxLean * (1.0 - _ease(t));
      }

      // Draw book pivoting around its bottom-centre on the shelf
      canvas.save();
      canvas.translate(bookCx, shelfY);
      canvas.rotate(rotation);

      final left = -bookW / 2;
      final top = -bookH;
      final right = bookW / 2;

      // ── Book body ──────────────────────────────────────────────────────
      canvas.drawRect(Rect.fromLTRB(left, top, right, 0), stroke);

      // ── Spine top strip (horizontal line) ──────────────────────────────
      final stripH = bookH * 0.14;
      canvas.drawLine(
        Offset(left, top + stripH),
        Offset(right, top + stripH),
        stroke,
      );

      // ── Spine circle detail ────────────────────────────────────────────
      canvas.drawCircle(
        Offset(0, top + stripH * 0.5),
        math.max(1.5, size * 0.028),
        stroke,
      );

      // ── Second thin stripe mid-spine ───────────────────────────────────
      final mid = top + bookH * 0.38;
      canvas.drawLine(Offset(left, mid), Offset(right, mid), stroke);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BookShelfPainter old) =>
      old.progress != progress || old.color != color || old.size != size;
}
