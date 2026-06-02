import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:trideta_v2/services/notification_service.dart';
import 'package:trideta_v2/firebase_options.dart';
import 'package:trideta_v2/main.dart'; // Imports notifiers

// ROUTING IMPORTS
import 'package:trideta_v2/screens/auth/onboarding_screen.dart';
import 'package:trideta_v2/screens/public/landing_page_screen.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';

class BootSplashScreen extends StatefulWidget {
  const BootSplashScreen({super.key});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Controls the smooth 5-second loading bar
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    // Controls the pulsing background/logo effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startBootSequence();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startBootSequence() async {
    _progressController.forward(); // Start filling the progress bar

    // Wait for BOTH the initialization logic AND the 5-sec timer concurrently
    await Future.wait([
      _initializeAllServices(),
      Future.delayed(const Duration(seconds: 5)),
    ]);

    // Ensure it reaches 100% smoothly if the background init somehow took longer
    if (!_progressController.isCompleted) {
      await _progressController.forward();
    }

    _navigateNext();
  }

  Future<void> _initializeAllServices() async {
    // 1. FIREBASE INIT
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. SUPABASE INIT
    await Supabase.initialize(
      url: 'https://tkuupmyrodazfrrembsc.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrdXVwbXlyb2RhemZycmVtYnNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MzE2MTAsImV4cCI6MjA4NjIwNzYxMH0.D46NbF3tu7Eaq2HreH4auh0flNNggubZZdKs9xgZQ4k',
    );

    // 3. SMART NOTIFICATIONS
    final session = Supabase.instance.client.auth.currentSession;
    if (!kIsWeb || session != null) {
      await NotificationService().initialize();
    }

    // ==========================================
    // 4. LOAD SAVED PREFERENCES & BRAND COLOR
    // ==========================================
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('saved_theme');

    if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }

    // 🚨 NEW DATABASE COLOR LOGIC
    Color finalColor = const Color(0xFF007ACC); // Default Trideta Blue

    if (session != null) {
      try {
        final userId = session.user.id;
        final userData = await Supabase.instance.client
            .from('profiles')
            .select('role, schools(brand_color)')
            .eq('id', userId)
            .single();

        final role = userData['role']?.toString().toLowerCase();

        // If they are an Admin/Teacher, try to use their school's color
        if (role != 'parent' && userData['schools'] != null) {
          String? dbColorStr = userData['schools']['brand_color'];

          if (dbColorStr != null && dbColorStr.isNotEmpty) {
            try {
              // TRANSLATOR: Convert "#HEX" from DB to Flutter Color
              dbColorStr = dbColorStr.replaceAll('#', '');
              if (dbColorStr.length == 6) {
                dbColorStr = 'FF$dbColorStr'; // Add 100% opacity prefix
              }
              finalColor = Color(int.parse(dbColorStr, radix: 16));
            } catch (e) {
              debugPrint("Failed to parse DB color: $e");
            }
          }
        }
      } catch (e) {
        debugPrint("Offline or failed to fetch color: $e");
        // Fallback to local memory if they have no internet
        int? savedColor = prefs.getInt('app_primary_color');
        if (savedColor != null) finalColor = Color(savedColor);
      }
    } else {
      // Not logged in yet
      int? savedColor = prefs.getInt('app_primary_color');
      if (savedColor != null) finalColor = Color(savedColor);
    }

    appColorNotifier.value = finalColor; // 👈 Injects the color globally!
    // ==========================================
  }

  void _navigateNext() async {
    final prefs = await SharedPreferences.getInstance();
    // THE ROUTING INTELLIGENCE
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    // If Web -> Force false (skip onboarding). If Mobile -> check if they've seen it.
    final bool shouldShowOnboarding = kIsWeb ? false : !hasSeenOnboarding;

    // NAVIGATE TO THE CORRECT SCREEN
    if (mounted) {
      Widget nextScreen = shouldShowOnboarding
          ? const OnboardingScreen()
          : (kIsWeb ? const LandingPageScreen() : const LoginScreen());

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, _, _) => nextScreen,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          // ─── BACKGROUND DECORATIVE PAINTER ───────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _SplashBackgroundPainter()),
          ),

          // ─── TOP-RIGHT BLOB ────────────────────────────────────
          Positioned(
            top: -size.width * 0.15,
            right: -size.width * 0.15,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.03);
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: size.width * 0.72,
                height: size.width * 0.72,
                decoration: const BoxDecoration(
                  color: Color(0xFF007ACC), // Trideta Blue
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          // ─── BOTTOM-LEFT BLOB ──────────────────────────────────
          Positioned(
            bottom: -size.width * 0.18,
            left: -size.width * 0.18,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                // Opposite phase from the top blob for a breathing effect
                final scale = 1.0 + ((1.0 - _pulseController.value) * 0.03);
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: size.width * 0.85,
                height: size.width * 0.85,
                decoration: const BoxDecoration(
                  color: Color(0xFF007ACC), // Trideta Blue
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          // ─── CENTER CONTENT ───────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🚨 Pulsing School Icon (Replaced Image.asset)
                AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.school_rounded,
                    size: 80,
                    color: Color(0xFF007ACC), // Tinted Trideta Blue
                  ),
                ),
                const SizedBox(height: 16),

                // App Name
                const Text(
                  'Trideta',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Tagline
                const Text(
                  'Powerful and Intuitive School\nManagement Software',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9098B1),
                    height: 1.6,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // ─── BOTTOM PROGRESS BAR ──────────────────────────────────────
          Positioned(
            bottom: 48,
            left: 60,
            right: 60,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progressController.value,
                        backgroundColor: const Color(0xFFE8EAF0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF007ACC), // Trideta Blue loader
                        ),
                        minHeight: 4,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    final pct = (_progressController.value * 100).toInt();
                    return Text(
                      'Initializing Core Systems... $pct%',
                      style: const TextStyle(
                        color: Color(0xFFB0B8CC),
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scattered geometric doodles — circles, diamonds, chevrons, brackets
// Mirrors the decorative motifs in the reference design
// ─────────────────────────────────────────────────────────────────────────────
class _SplashBackgroundPainter extends CustomPainter {
  static const _accentColor = Color(0xFFCDD0E3); // soft blue-grey
  static const _strokeW = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeW;

    // Precomputed relative positions [x%, y%, size%, rotation°]
    final circles = [
      [0.12, 0.18, 0.04],
      [0.78, 0.35, 0.03],
      [0.55, 0.72, 0.035],
    ];
    final diamonds = [
      [0.25, 0.65, 0.025, 0.0],
      [0.85, 0.15, 0.02, 0.3],
      [0.82, 0.85, 0.03, -0.2],
    ];
    final chevrons = [
      [0.15, 0.45, 0.03, 0.5],
      [0.70, 0.60, 0.035, -0.4],
      [0.35, 0.82, 0.025, 1.2],
    ];
    final brackets = [
      [0.45, 0.12, 0.04, 0.8],
      [0.10, 0.80, 0.03, -0.5],
      [0.90, 0.50, 0.045, 0.2],
    ];

    // Helper dimension
    final minDim = math.min(size.width, size.height);

    for (var c in circles) {
      _drawCircle(canvas, paint, _pos(size, c), minDim * c[2]);
    }
    for (var d in diamonds) {
      _drawDiamond(canvas, paint, _pos(size, d), minDim * d[2], d[3]);
    }
    for (var cv in chevrons) {
      _drawChevron(canvas, paint, _pos(size, cv), minDim * cv[2], cv[3]);
    }
    for (var b in brackets) {
      _drawArcBracket(canvas, paint, _pos(size, b), minDim * b[2], b[3]);
    }
  }

  Offset _pos(Size size, List<double> cfg) {
    return Offset(size.width * cfg[0], size.height * cfg[1]);
  }

  void _drawCircle(Canvas canvas, Paint paint, Offset center, double radius) {
    canvas.drawCircle(center, radius, paint);
  }

  void _drawDiamond(
    Canvas canvas,
    Paint paint,
    Offset center,
    double r,
    double rotation,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(0, -r)
      ..lineTo(r, 0)
      ..lineTo(0, r)
      ..lineTo(-r, 0)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawChevron(
    Canvas canvas,
    Paint paint,
    Offset center,
    double r,
    double rotation,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(-r, -r * 0.5)
      ..lineTo(0, r * 0.5)
      ..lineTo(r, -r * 0.5);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawArcBracket(
    Canvas canvas,
    Paint paint,
    Offset center,
    double radius,
    double rotation,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      -math.pi / 3,
      math.pi * (2 / 3),
      false,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
