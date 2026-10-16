import 'dart:math' as math;

import 'package:flutter/material.dart';

// =============================================================================
// PARENT DASHBOARD — VISUAL KIT
// Presentation helpers only: colors, cards, buttons, illustrations.
// Nothing in here reads data, calls services or navigates.
// =============================================================================

class PUi {
  PUi._();

  // ---- Palette (matches the login screen: soft off-white, ink, blue-grey) ----
  static Color bg(bool d) =>
      d ? const Color(0xFF0F1512) : const Color(0xFFF8FAF8);
  static Color surface(bool d) => d ? const Color(0xFF1A211D) : Colors.white;
  static Color surfaceAlt(bool d) =>
      d ? const Color(0xFF232C27) : const Color(0xFFEFF3F0);
  static Color border(bool d) => d ? Colors.white12 : const Color(0xFFE3EAF2);
  static Color ink(bool d) => d ? Colors.white : const Color(0xFF0B1B14);
  static Color muted(bool d) =>
      d ? const Color(0xFF9AA7B5) : const Color(0xFF5F7396);

  /// A soft wash of [c] used behind icons, chips and highlights.
  static Color tint(Color c, bool d, [double light = 0.1]) =>
      c.withValues(alpha: d ? light + 0.07 : light);

  static List<BoxShadow> softShadow(bool d) => d
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ];

  // ---- Typography ----
  static TextStyle title(bool d, {double size = 28}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.1,
    color: ink(d),
  );

  static TextStyle sectionLabel(bool d) => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.3,
    color: muted(d),
  );

  // ---- Pill buttons ----
  static ButtonStyle filledPill(Color c, {double height = 52}) =>
      FilledButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        minimumSize: Size(0, height),
        shape: const StadiumBorder(),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  static ButtonStyle outlinedPill(Color c, {double height = 52}) =>
      OutlinedButton.styleFrom(
        foregroundColor: c,
        minimumSize: Size(0, height),
        side: BorderSide(color: c, width: 1.2),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );
}

// -----------------------------------------------------------------------------
// Soft corner circles behind a page (same idea as the login screen)
// -----------------------------------------------------------------------------
class PBackdrop extends StatelessWidget {
  final Color accent;
  final Widget child;
  const PBackdrop({super.key, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    final tint = accent.withValues(alpha: d ? 0.14 : 0.09);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(top: -120, left: -120, child: _SoftCircle(280, tint)),
        Positioned(bottom: -150, right: -150, child: _SoftCircle(320, tint)),
        child,
      ],
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _SoftCircle(this.size, this.color);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Rounded surface card (optionally tappable)
// -----------------------------------------------------------------------------
class PCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final bool shadow;

  const PCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: color ?? PUi.surface(d),
        borderRadius: br,
        border: Border.all(
          color: borderColor ?? PUi.border(d),
          width: borderWidth,
        ),
        boxShadow: shadow ? PUi.softShadow(d) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Round icon on a tinted background
// -----------------------------------------------------------------------------
class PIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const PIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PUi.tint(color, d, 0.12),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

// -----------------------------------------------------------------------------
// Small rounded label
// -----------------------------------------------------------------------------
class PPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  const PPill({
    super.key,
    required this.text,
    required this.color,
    this.filled = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : PUi.tint(color, d, 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Avatar with a coloured ring (photo or initial)
// -----------------------------------------------------------------------------
class PAvatar extends StatelessWidget {
  final String initial;
  final String imageUrl;
  final double radius;
  final Color ringColor;
  final Color? backgroundColor;
  final Color? initialColor;

  const PAvatar({
    super.key,
    required this.initial,
    required this.imageUrl,
    required this.radius,
    required this.ringColor,
    this.backgroundColor,
    this.initialColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? ringColor.withValues(alpha: 0.15),
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty
            ? Text(
                initial,
                style: TextStyle(
                  color: initialColor ?? ringColor,
                  fontWeight: FontWeight.w800,
                  fontSize: radius * 0.8,
                ),
              )
            : null,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Empty state with the study illustration
// -----------------------------------------------------------------------------
class PEmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final Color accent;
  final double illustrationWidth;

  const PEmptyState({
    super.key,
    required this.title,
    required this.accent,
    this.message,
    this.illustrationWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    final d = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: illustrationWidth,
            child: AspectRatio(
              aspectRatio: 300 / 190,
              child: CustomPaint(
                painter: PScenePainter(
                  scene: PScene.hero,
                  line: accent,
                  tint: accent.withValues(alpha: d ? 0.16 : 0.10),
                  paper: PUi.bg(d),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PUi.ink(d),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: PUi.muted(d)),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// ILLUSTRATIONS — pure drawing, no assets
// =============================================================================
enum PScene { hero, globe, corner }

class PScenePainter extends CustomPainter {
  final PScene scene;
  final Color line;
  final Color tint;
  final Color paper;

  const PScenePainter({
    required this.scene,
    required this.line,
    required this.tint,
    required this.paper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 190);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = line.withValues(alpha: 0.5);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = paper;
    final tintPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = tint;
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = line;

    void shape(Path p) {
      canvas.drawPath(p, fill);
      canvas.drawPath(p, stroke);
    }

    void rrect(Rect r, double rad) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(rad));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }

    void book(Rect r) {
      rrect(r, 3);
      for (final t in [0.35, 0.65]) {
        final y = r.top + r.height * t;
        canvas.drawLine(
          Offset(r.left + r.width * 0.55, y),
          Offset(r.right - 5, y),
          thin,
        );
      }
    }

    void pencil(Offset base, Offset tip) {
      final d = tip - base;
      final n = Offset(-d.dy, d.dx) / d.distance * 2.8;
      final mid = base + d * 0.78;
      shape(
        Path()
          ..moveTo(base.dx + n.dx, base.dy + n.dy)
          ..lineTo(mid.dx + n.dx, mid.dy + n.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(mid.dx - n.dx, mid.dy - n.dy)
          ..lineTo(base.dx - n.dx, base.dy - n.dy)
          ..close(),
      );
    }

    void cupWithPencils(double x) {
      pencil(Offset(x + 10, 134), Offset(x + 6, 90));
      pencil(Offset(x + 18, 134), Offset(x + 23, 84));
      pencil(Offset(x + 26, 134), Offset(x + 36, 98));
      rrect(Rect.fromLTWH(x, 128, 36, 47), 5);
      canvas.drawLine(Offset(x + 3, 138), Offset(x + 33, 138), thin);
    }

    void leaf(Offset b, double a, double len) {
      final dir = Offset(math.cos(a), math.sin(a));
      final nr = Offset(-dir.dy, dir.dx);
      final tip = b + dir * len;
      final m = b + dir * (len * 0.5);
      final c1 = m + nr * (len * 0.4);
      final c2 = m - nr * (len * 0.4);
      shape(
        Path()
          ..moveTo(b.dx, b.dy)
          ..quadraticBezierTo(c1.dx, c1.dy, tip.dx, tip.dy)
          ..quadraticBezierTo(c2.dx, c2.dy, b.dx, b.dy),
      );
    }

    void plantInVase(double cx, double baseY) {
      canvas.drawPath(
        Path()
          ..moveTo(cx, baseY - 50)
          ..quadraticBezierTo(cx + 3, baseY - 78, cx - 2, baseY - 106),
        stroke,
      );
      leaf(Offset(cx, baseY - 62), -0.7, 20);
      leaf(Offset(cx, baseY - 72), -2.4, 20);
      leaf(Offset(cx + 1, baseY - 84), -0.6, 20);
      leaf(Offset(cx, baseY - 94), -2.5, 18);
      leaf(Offset(cx - 2, baseY - 105), -1.6, 20);
      shape(
        Path()
          ..moveTo(cx - 6, baseY - 50)
          ..lineTo(cx - 6, baseY - 38)
          ..quadraticBezierTo(cx - 24, baseY - 26, cx - 18, baseY - 10)
          ..quadraticBezierTo(cx - 16, baseY, cx, baseY)
          ..quadraticBezierTo(cx + 16, baseY, cx + 18, baseY - 10)
          ..quadraticBezierTo(cx + 24, baseY - 26, cx + 6, baseY - 38)
          ..lineTo(cx + 6, baseY - 50)
          ..close(),
      );
    }

    void sparkles() {
      const ticks = [
        [150.0, 30.0, 150.0, 41.0],
        [172.0, 38.0, 166.0, 47.0],
        [128.0, 38.0, 134.0, 47.0],
        [100.0, 52.0, 108.0, 57.0],
      ];
      for (final t in ticks) {
        canvas.drawLine(Offset(t[0], t[1]), Offset(t[2], t[3]), stroke);
      }
    }

    if (scene != PScene.corner) {
      canvas.drawCircle(const Offset(105, 112), 58, tintPaint);
      canvas.drawCircle(const Offset(175, 98), 54, tintPaint);
      canvas.drawCircle(const Offset(232, 128), 44, tintPaint);
      canvas.drawRect(const Rect.fromLTWH(48, 118, 224, 57), tintPaint);
    }

    canvas.drawLine(const Offset(4, 175), const Offset(296, 175), stroke);

    if (scene == PScene.corner) {
      book(const Rect.fromLTWH(6, 163, 116, 12));
      book(const Rect.fromLTWH(26, 151, 104, 12));
      book(const Rect.fromLTWH(16, 139, 110, 12));
      cupWithPencils(150);
      plantInVase(240, 175);
      canvas.restore();
      return;
    }

    book(const Rect.fromLTWH(10, 160, 140, 15));
    book(const Rect.fromLTWH(22, 144, 116, 16));
    book(const Rect.fromLTWH(16, 128, 128, 16));

    shape(
      Path()
        ..moveTo(52, 108)
        ..lineTo(52, 122)
        ..quadraticBezierTo(80, 134, 108, 122)
        ..lineTo(108, 108),
    );
    shape(
      Path()
        ..moveTo(80, 80)
        ..lineTo(132, 98)
        ..lineTo(80, 116)
        ..lineTo(28, 98)
        ..close(),
    );
    canvas.drawLine(const Offset(34, 100), const Offset(34, 119), stroke);
    canvas.drawCircle(const Offset(34, 122), 2.6, solid);

    rrect(const Rect.fromLTWH(152, 108, 13, 67), 2);
    rrect(const Rect.fromLTWH(167, 118, 11, 57), 2);
    cupWithPencils(184);

    if (scene == PScene.hero) {
      plantInVase(252, 175);
    } else {
      const c = Offset(252, 92);
      const r = 34.0;
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c - const Offset(10, 8), 9, tintPaint);
      canvas.drawCircle(c + const Offset(12, 10), 10, tintPaint);
      canvas.drawCircle(c, r, stroke);
      canvas.drawOval(Rect.fromCenter(center: c, width: 34, height: 68), thin);
      canvas.drawLine(c - const Offset(r, 0), c + const Offset(r, 0), thin);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 5),
        0.2,
        2.8,
        false,
        stroke,
      );
      canvas.drawLine(const Offset(252, 126), const Offset(252, 168), stroke);
      final baseRect = Rect.fromCenter(
        center: const Offset(252, 171),
        width: 44,
        height: 8,
      );
      canvas.drawOval(baseRect, fill);
      canvas.drawOval(baseRect, stroke);
    }

    sparkles();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PScenePainter old) =>
      old.scene != scene ||
      old.line != line ||
      old.tint != tint ||
      old.paper != paper;
}
