import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:trideta_v2/services/notification_service.dart';
import 'package:trideta_v2/firebase_options.dart';
import 'package:trideta_v2/main.dart'; // 🚨 Imports your notifiers

// 🚨 ADDED ROUTING IMPORTS
import 'package:trideta_v2/screens/auth/onboarding_screen.dart';
import 'package:trideta_v2/screens/public/landing_page_screen.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';

class BootSplashScreen extends StatefulWidget {
  const BootSplashScreen({super.key});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAllServices();
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
              // 🚨 TRANSLATOR: Convert "#HEX" from DB to Flutter Color
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

    // 🚨 THE ROUTING INTELLIGENCE
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    // If Web -> Force false (skip onboarding). If Mobile -> check if they've seen it.
    final bool shouldShowOnboarding = kIsWeb ? false : !hasSeenOnboarding;

    // 🚨 5. NAVIGATE TO THE CORRECT SCREEN (No more nested MyApps!)
    if (mounted) {
      Widget nextScreen = shouldShowOnboarding
          ? const OnboardingScreen()
          : (kIsWeb ? const LandingPageScreen() : const LoginScreen());

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
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
      backgroundColor: const Color(0xFF007ACC), // 🚨 Trideta Blue!
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Trideta Logo
            Image.asset(
              'assets/icon/app_icon.png', // 🚨 Updated to match your pubspec
              width: 180,
            ),
            const SizedBox(height: 50),
            // The Cool Progress Loader
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
