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
import 'package:trideta_v2/screens/auth/login_screen.dart';

class BootSplashScreen extends StatefulWidget {
  const BootSplashScreen({super.key});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

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
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startBootSequence() async {
    // Wait for BOTH the initialization logic AND a smooth 3-second display
    await Future.wait([
      _initializeAllServices(),
      Future.delayed(const Duration(seconds: 3)),
    ]);

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

    // 🚨 DATABASE COLOR LOGIC
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
          : (kIsWeb ? LoginScreen() : const LoginScreen());

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
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          // ─── BACKGROUND DECORATIVE PAINTER ───────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _SplashBackgroundPainter()),
          ),

          // ─── CENTER CONTENT ───────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🚨 TRUE APP LOGO WRAPPED IN A CIRCLE (Pulsing Animation)
                AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF007ACC,
                          ).withValues(alpha: 0.15),
                          blurRadius: 24,
                          spreadRadius: 4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        // Fallback removed to force actual asset usage.
                        // Make sure assets/icon/ is in pubspec.yaml!
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // App Name
                const Text(
                  'Trideta',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
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
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // ─── BOTTOM BRANDING ("from SKYNEX" WITH ANIMATED LOOP) ───────
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: SkynexAnimatedBranding(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW: Meta-Style Animated Skynex Branding Widget
// ─────────────────────────────────────────────────────────────────────────────
class SkynexAnimatedBranding extends StatefulWidget {
  const SkynexAnimatedBranding({super.key});

  @override
  State<SkynexAnimatedBranding> createState() => _SkynexAnimatedBrandingState();
}

class _SkynexAnimatedBrandingState extends State<SkynexAnimatedBranding>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    // Controls the glowing endless loop animation
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'from',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF9098B1),
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Endless Loop (Infinity) Icon
            AnimatedBuilder(
              animation: _sweepController,
              builder: (context, child) {
                return ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return SweepGradient(
                      startAngle: 0.0,
                      endAngle: math.pi * 2,
                      colors: const [
                        Color(0xFF007ACC), // Trideta Blue
                        Color(0xFF66C2FF), // Highlight / Shimmer
                        Color(0xFF007ACC),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      transform: GradientRotation(
                        _sweepController.value * 2 * math.pi,
                      ),
                    ).createShader(bounds);
                  },
                  child: const Icon(
                    Icons.all_inclusive_rounded, // The Endless Loop Shape
                    size: 26,
                    color: Colors.white, // Must be white for ShaderMask to work
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            // Skynex Text
            const Text(
              'SKYNEX',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF007ACC), // Trideta Blue
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scattered geometric doodles — circles, diamonds, chevrons, brackets
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
