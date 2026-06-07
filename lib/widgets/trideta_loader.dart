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
    // A smooth 1.8-second cycle for the rotating/pulsing effect
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 Changed to a perfect square to match standard circular loaders
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _CoolCircularPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Draws a sleek, dual-orbiting circular loader with a pulsing core
// ─────────────────────────────────────────────────────────────────────────────
class _CoolCircularPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CoolCircularPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Dynamic stroke width based on the size provided
    final strokeWidth = math.max(2.0, radius * 0.12);

    // ── Paints ─────────────────────────────────────────────────────────
    final paintOuter = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintInner = Paint()
      ..color = color
          .withValues(alpha: 0.5) // Softer inner ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8
      ..strokeCap = StrokeCap.round;

    final paintCore = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // ── Math & Angles ──────────────────────────────────────────────────
    // Convert 0.0 -> 1.0 progress into a full 360 degree (2pi) rotation
    final t = progress * 2 * math.pi;

    // Outer Ring: Spins clockwise, breathing sweep angle
    final outerStart = t;
    final outerSweep = math.pi * 0.6 + math.sin(t) * math.pi * 0.4;
    final outerRadius = radius - strokeWidth;

    // Inner Ring: Spins counter-clockwise (faster), breathing sweep angle
    final innerStart = -t * 1.5;
    final innerSweep = math.pi * 0.5 + math.cos(t) * math.pi * 0.3;
    final innerRadius = radius - (strokeWidth * 3.5);

    // Core: Pulses in size
    final pulseScale = 0.7 + 0.3 * math.sin(t * 2);
    final coreRadius = (radius * 0.15) * pulseScale;

    // ── Drawing ────────────────────────────────────────────────────────

    // 1. Draw Outer Ring (Two opposing arcs for a balanced look)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      outerStart,
      outerSweep,
      false,
      paintOuter,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      outerStart + math.pi, // Offset by 180 degrees
      outerSweep,
      false,
      paintOuter,
    );

    // 2. Draw Inner Ring
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerStart,
      innerSweep,
      false,
      paintInner,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      innerStart + math.pi,
      innerSweep,
      false,
      paintInner,
    );

    // 3. Draw Pulsing Core
    canvas.drawCircle(center, coreRadius, paintCore);
  }

  @override
  bool shouldRepaint(covariant _CoolCircularPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
