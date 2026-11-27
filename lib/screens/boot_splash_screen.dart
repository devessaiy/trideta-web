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
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

// ROUTING IMPORTS
import 'package:trideta_v2/screens/auth/onboarding_screen.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';

// Trideta Blue — the splash always uses this, because the school colour is
// still being loaded while the splash is showing.
const Color _kSplashBlue = Color(0xFF007ACC);

class BootSplashScreen extends StatefulWidget {
  const BootSplashScreen({super.key});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  bool _logoPrecached = false;

  @override
  void initState() {
    super.initState();

    // Controls the gentle pulsing of the logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startBootSequence();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⚡ Decode the logo up-front so it never pops in late.
    if (!_logoPrecached) {
      _logoPrecached = true;
      precacheImage(
        const AssetImage('assets/icon/trideta_icon.png'),
        context,
        onError: (e, s) {},
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startBootSequence() async {
    // Wait for BOTH the initialization logic AND a short, smooth display.
    // ⚡ The display time was 1500ms; 700ms is enough to show the brand.
    await Future.wait([
      _initializeAllServices(),
      Future.delayed(const Duration(milliseconds: 700)),
    ]);

    _navigateNext();
  }

  Future<void> _initializeAllServices() async {
    // ⚡ Start reading the saved preferences straight away — it needs nothing
    // else, so it can finish while Firebase and Supabase are starting.
    final prefsFuture = SharedPreferences.getInstance();

    // 1 + 2. FIREBASE and SUPABASE do not depend on each other, so they now
    // start together instead of one after the other.
    await Future.wait([
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).then((_) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }),
      Supabase.initialize(
        url: 'https://tkuupmyrodazfrrembsc.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrdXVwbXlyb2RhemZycmVtYnNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MzE2MTAsImV4cCI6MjA4NjIwNzYxMH0.D46NbF3tu7Eaq2HreH4auh0flNNggubZZdKs9xgZQ4k',
      ),
    ]);

    // 3. SMART NOTIFICATIONS
    // ⚡ These need Firebase AND Supabase, so they start only after both are
    // ready — but they no longer block the theme and colour work below. We
    // still wait for them before leaving the splash, exactly as before.
    final session = Supabase.instance.client.auth.currentSession;
    Future<void> notificationsFuture = Future<void>.value();
    if (!kIsWeb || session != null) {
      // Never let a slow connection hold the app on the splash screen.
      notificationsFuture = NotificationService().initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      // An early error is still delivered at the `await` further down.
      notificationsFuture.ignore();
    }

    // ==========================================
    // 4. LOAD SAVED PREFERENCES & BRAND COLOR
    // ==========================================
    final prefs = await prefsFuture;
    final savedTheme = prefs.getString('saved_theme');

    if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }

    // DATABASE COLOR LOGIC
    Color finalColor = _kSplashBlue; // Default Trideta Blue

    // Use the colour saved on this phone first: no waiting on the internet.
    final int? cachedColorInt = prefs.getInt('app_primary_color');
    final bool useCachedColor = session != null && cachedColorInt != null;
    if (useCachedColor && cachedColorInt != null) {
      finalColor = Color(cachedColorInt);
    }

    if (session != null && !useCachedColor) {
      try {
        final userId = session.user.id;
        final userData = await Supabase.instance.client
            .from('profiles')
            .select('role, schools(brand_color)')
            .eq('id', userId)
            .single()
            .timeout(const Duration(seconds: 5));

        final role = userData['role']?.toString().toLowerCase();

        // If they are an Admin/Teacher, try to use their school's color
        if (role != 'parent' && userData['schools'] != null) {
          String? dbColorStr = userData['schools']['brand_color'];

          if (dbColorStr != null && dbColorStr.isNotEmpty) {
            try {
              dbColorStr = dbColorStr.replaceAll('#', '');
              if (dbColorStr.length == 6) {
                dbColorStr = 'FF$dbColorStr';
              }
              finalColor = Color(int.parse(dbColorStr, radix: 16));
            } catch (e) {
              debugPrint("Failed to parse DB color: $e");
            }
          }
        }
      } catch (e) {
        debugPrint("Offline or failed to fetch color: $e");
        int? savedColor = prefs.getInt('app_primary_color');
        if (savedColor != null) finalColor = Color(savedColor);
      }
    } else {
      int? savedColor = prefs.getInt('app_primary_color');
      if (savedColor != null) finalColor = Color(savedColor);
    }

    appColorNotifier.value = finalColor;

    // Notifications were running in the background of the work above;
    // make sure they have finished (or timed out) before we continue.
    await notificationsFuture;
  }

  void _navigateNext() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    final bool shouldShowOnboarding = kIsWeb ? false : !hasSeenOnboarding;

    if (mounted) {
      Widget nextScreen = shouldShowOnboarding
          ? const OnboardingScreen()
          : (kIsWeb ? const LoginScreen() : const LoginScreen());

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          // ⚡ Was 700ms; a quicker fade feels snappier.
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, _, _) => nextScreen,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to the active theme from the MaterialApp
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: _kSplashBlue,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ─── FAINT STUDY ILLUSTRATION (static, painted once) ─────────
            Positioned(
              right: 0,
              bottom: 96,
              width: math.min(screenWidth * 0.62, 300.0),
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AspectRatio(
                    aspectRatio: 300 / 190,
                    child: CustomPaint(
                      painter: PScenePainter(
                        scene: PScene.corner,
                        line: _kSplashBlue.withValues(alpha: 0.4),
                        tint: _kSplashBlue.withValues(alpha: 0.08),
                        paper: PUi.bg(isDark),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ─── CENTER CONTENT ───────────────────────────────────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // TRUE APP LOGO IN A RINGED CIRCLE (only this part animates)
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _scaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _kSplashBlue.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: _kSplashBlue.withValues(
                                    alpha: isDark ? 0.3 : 0.18,
                                  ),
                                  blurRadius: 26,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/icon/trideta_icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) =>
                                    const Icon(
                                      Icons.school_rounded,
                                      size: 52,
                                      color: _kSplashBlue,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),

                    // App Name
                    Text('Trideta', style: PUi.title(isDark, size: 36)),
                    const SizedBox(height: 10),

                    // Tagline
                    Text(
                      'Powerful and Intuitive School\nManagement Software',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: PUi.muted(isDark),
                        height: 1.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── BOTTOM BRANDING ───────
            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: SkynexAnimatedBranding(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta-Style Animated Skynex Branding Widget
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'from',
          style: TextStyle(
            fontSize: 12,
            color: PUi.muted(isDark),
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _sweepController,
                builder: (context, child) {
                  return ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return SweepGradient(
                        startAngle: 0.0,
                        endAngle: math.pi * 2,
                        colors: const [
                          Color(0xFF007ACC),
                          Color(0xFF66C2FF),
                          Color(0xFF007ACC),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        transform: GradientRotation(
                          _sweepController.value * 2 * math.pi,
                        ),
                      ).createShader(bounds);
                    },
                    child: const Icon(
                      Icons.all_inclusive_rounded,
                      size: 26,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'SKYNEX',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF007ACC),
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
