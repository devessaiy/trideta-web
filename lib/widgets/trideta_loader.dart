import 'package:flutter/material.dart';
import 'dart:math' as math;

class TridetaLoader extends StatefulWidget {
  final double size;
  final Color color;

  const TridetaLoader({
    super.key,
    this.size = 50.0,
    this.color = const Color(0xFF007ACC),
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wide aspect ratio to fit the full wordmark
    return SizedBox(
      width: widget.size * 4.2,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _CalligraphicWordPainter(
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
// Letter definition for sequential stroke animation
// ─────────────────────────────────────────────────────────────────────────────
class _Letter {
  final Path path;
  final double offsetX;
  final double start; // animation window start (0..1)
  final double end; // animation window end   (0..1)

  const _Letter({
    required this.path,
    required this.offsetX,
    required this.start,
    required this.end,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Draws "Trideta" with a handwriting reveal, hold, and fade cycle.
// ─────────────────────────────────────────────────────────────────────────────
class _CalligraphicWordPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double size;

  _CalligraphicWordPainter({
    required this.progress,
    required this.color,
    required this.size,
  });

  // Total width of the word in local path units
  static const double _wordWidth = 75.0;

  // Pre-built calligraphic paths for each letter
  static final List<_Letter> _letters = _buildLetters();

  static List<_Letter> _buildLetters() {
    // ── T : flourished top bar + S-curve stem ─────────────────────────
    final t = Path()
      ..moveTo(0.5, -9.0)
      ..quadraticBezierTo(5.5, -10.5, 10.5, -8.5)
      ..moveTo(5.5, -10.0)
      ..quadraticBezierTo(6.5, -3.0, 5.5, 2.0);

    // ── r : shoulder arch to baseline tail ────────────────────────────
    final r = Path()
      ..moveTo(0.0, 1.0)
      ..quadraticBezierTo(2.5, -8.0, 5.0, -3.0)
      ..quadraticBezierTo(6.5, 0.5, 7.5, 2.0);

    // ── i : dot + short stem ─────────────────────────────────────────
    final i = Path()
      ..moveTo(2.0, -10.0)
      ..lineTo(2.0, -8.5)
      ..moveTo(2.0, -7.0)
      ..quadraticBezierTo(2.5, -2.0, 2.0, 2.0);

    // ── d : ascender + bowl loop ─────────────────────────────────────
    final d = Path()
      ..moveTo(5.0, -10.0)
      ..quadraticBezierTo(6.0, -3.0, 5.0, 2.0)
      ..moveTo(5.0, -2.0)
      ..quadraticBezierTo(2.0, 3.0, 6.0, 3.5)
      ..quadraticBezierTo(9.0, 2.5, 7.5, -5.0)
      ..quadraticBezierTo(6.5, -8.0, 5.0, -2.0);

    // ── e : single continuous loop ───────────────────────────────────
    final e = Path()
      ..moveTo(1.0, 1.0)
      ..quadraticBezierTo(4.0, -8.0, 8.0, -3.0)
      ..quadraticBezierTo(10.0, 0.5, 7.0, 4.0)
      ..quadraticBezierTo(4.0, 5.5, 1.0, 1.0);

    // ── t : short cross + curved stem ─────────────────────────────────
    final t2 = Path()
      ..moveTo(1.0, -5.5)
      ..lineTo(6.0, -6.5)
      ..moveTo(3.5, -8.5)
      ..quadraticBezierTo(4.5, -2.0, 3.5, 2.5);

    // ── a : single-story bowl + right leg ─────────────────────────────
    final a = Path()
      ..moveTo(1.0, 2.0)
      ..quadraticBezierTo(4.5, -8.0, 8.5, -2.0)
      ..quadraticBezierTo(10.5, 1.5, 7.0, 4.5)
      ..quadraticBezierTo(4.0, 5.5, 1.0, 2.0)
      ..moveTo(7.0, -2.0)
      ..lineTo(9.0, 2.5);

    return [
      _Letter(path: t, offsetX: 0, start: 0.00, end: 0.11),
      _Letter(path: r, offsetX: 12.5, start: 0.11, end: 0.22),
      _Letter(path: i, offsetX: 21.0, start: 0.22, end: 0.30),
      _Letter(path: d, offsetX: 26.5, start: 0.30, end: 0.42),
      _Letter(path: e, offsetX: 38.0, start: 0.42, end: 0.53),
      _Letter(path: t2, offsetX: 49.0, start: 0.53, end: 0.63),
      _Letter(path: a, offsetX: 58.5, start: 0.63, end: 0.75),
    ];
  }

  static double _easeOut(double t) => 1 - (1 - t) * (1 - t);

  @override
  void paint(Canvas canvas, Size cs) {
    final scale = cs.width / _wordWidth;
    final baselineY = cs.height * 0.58;
    final centerX = cs.width / 2;
    final centerY = cs.height / 2;

    // ── Phase timing ───────────────────────────────────────────────────
    const double writeEnd = 0.75; // last letter finishes
    const double holdEnd = 0.86; // hold + breathe
    const double fadeEnd = 0.96; // fade out complete

    // Global opacity for fade-out phase
    double opacity = 1.0;
    if (progress > holdEnd && progress <= fadeEnd) {
      opacity = 1.0 - _easeOut((progress - holdEnd) / (fadeEnd - holdEnd));
    } else if (progress > fadeEnd) {
      opacity = 0.0;
    }
    if (opacity <= 0) return;

    // ── Soft "brush" glow behind the strokes ───────────────────────────
    final glow = Paint()
      ..color = color.withValues(alpha: opacity * 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(4.0, size * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Main calligraphic stroke ───────────────────────────────────────
    final stroke = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, size * 0.075)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Optional whole-word breathe during hold ───────────────────────
    double wordScale = 1.0;
    if (progress >= writeEnd && progress <= holdEnd) {
      final t = (progress - writeEnd) / (holdEnd - writeEnd);
      wordScale = 1.0 + 0.015 * math.sin(t * math.pi * 2);
    }

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.scale(wordScale);
    canvas.translate(-centerX, -centerY);

    // ── Draw each letter sequentially ──────────────────────────────────
    for (final letter in _letters) {
      double localProgress;
      if (progress <= letter.start) {
        localProgress = 0.0;
      } else if (progress >= letter.end) {
        localProgress = 1.0;
      } else {
        localProgress = _easeOut(
          (progress - letter.start) / (letter.end - letter.start),
        );
      }
      if (localProgress <= 0) continue;

      canvas.save();
      canvas.translate(letter.offsetX * scale, baselineY);
      canvas.scale(scale);

      // Glow then stroke for soft brush depth
      _drawPathProgress(canvas, letter.path, localProgress, glow);
      _drawPathProgress(canvas, letter.path, localProgress, stroke);

      canvas.restore();
    }

    // ── Pulsing cursor dot at the end of the final stroke ─────────────
    if (progress >= writeEnd && progress <= holdEnd) {
      final holdT = (progress - writeEnd) / (holdEnd - writeEnd);
      final pulse = 0.5 + 0.5 * math.sin(holdT * math.pi * 4);

      final dotPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.45 * pulse)
        ..style = PaintingStyle.fill;

      // Tip of the 'a' leg in canvas space
      final tipX = (58.5 + 9.0) * scale;
      final tipY = baselineY + 2.5 * scale;
      final radius = math.max(2.0, size * 0.035) * (0.9 + 0.15 * pulse);

      canvas.drawCircle(Offset(tipX, tipY), radius, dotPaint);
    }

    canvas.restore();
  }

  // ── Reveals a path up to a given progress (0..1) ─────────────────────
  void _drawPathProgress(
    Canvas canvas,
    Path path,
    double progress,
    Paint paint,
  ) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final totalLength = metrics.fold(0.0, (sum, m) => sum + m.length);
    final targetLength = totalLength * progress;

    double drawn = 0;
    for (final metric in metrics) {
      if (drawn >= targetLength) break;
      final remaining = targetLength - drawn;
      final extractLen = math.min(metric.length, remaining);
      if (extractLen > 0) {
        canvas.drawPath(metric.extractPath(0, extractLen), paint);
      }
      drawn += metric.length;
    }
  }

  @override
  bool shouldRepaint(_CalligraphicWordPainter old) =>
      old.progress != progress || old.color != color || old.size != size;
}
