import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:trideta_v2/services/notification_service.dart';
import 'package:trideta_v2/firebase_options.dart';
import 'package:trideta_v2/main.dart'; // 🚨 Imports MyApp and your notifiers

ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

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
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. SUPABASE INIT
    await Supabase.initialize(
      url: 'https://tkuupmyrodazfrrembsc.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrdXVwbXlyb2RhemZycmVtYnNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MzE2MTAsImV4cCI6MjA4NjIwNzYxMH0.D46NbF3tu7Eaq2HreH4auh0flNNggubZZdKs9xgZQ4k',
    );

    // 3. SMART NOTIFICATIONS
    final session = Supabase.instance.client.auth.currentSession;
    if (!kIsWeb || session != null) {
      await NotificationService().initialize();
    }

    // 4. LOAD SAVED PREFERENCES
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('saved_theme');
    int? colorValue = prefs.getInt('app_primary_color');

    if (colorValue != null) {
      appColorNotifier.value = Color(colorValue);
    }

    if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }

    // 🚨 THE ROUTING INTELLIGENCE
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    
    // If Web -> Force false (skip onboarding). If Mobile -> check if they've seen it.
    final bool shouldShowOnboarding = kIsWeb ? false : !hasSeenOnboarding;

    // 5. NAVIGATE TO MAIN APP ONCE LOADED
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => MyApp(showOnboarding: shouldShowOnboarding),
          transitionsBuilder: (_, animation, __, child) => 
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