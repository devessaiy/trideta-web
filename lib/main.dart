import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// 🚨 UPDATED: Using bulletproof absolute imports
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/screens/auth/onboarding_screen.dart';
import 'package:trideta_v2/screens/public/landing_page_screen.dart';
import 'package:trideta_v2/screens/boot_splash_screen.dart'; // 🚨 Imports your new loader!

// 🚨 FIREBASE IMPORTS
import 'package:firebase_messaging/firebase_messaging.dart';

// 1. GLOBAL KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 2. THE "HALL PASS" (Security Bypass Flag)
bool isInteractingWithSystem = false;

// 3. THEMING NOTIFIERS (Moved up here so the splash screen can update them)
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<Color> appColorNotifier = ValueNotifier(
  const Color(0xFF007ACC),
);

// 🚨 BACKGROUND NOTIFICATION HANDLER
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() {
  // We don't initialize Supabase or Firebase here anymore!
  // We start the app IMMEDIATELY to show the animated loader.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BootSplashScreen(),
    ),
  );
}

class MyApp extends StatefulWidget {
  final bool showOnboarding;
  const MyApp({super.key, required this.showOnboarding});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached && !isInteractingWithSystem) {
      debugPrint("--- APP CLOSED: LOCKING SCREEN ---");

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return ValueListenableBuilder<Color>(
          valueListenable: appColorNotifier,
          builder: (context, currentPrimaryColor, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'TriDeta School',
              themeMode: currentMode,
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: currentPrimaryColor,
                scaffoldBackgroundColor: Colors.grey[50],
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: currentPrimaryColor,
                  brightness: Brightness.light,
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: currentPrimaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  centerTitle: true,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentPrimaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: currentPrimaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primaryColor: currentPrimaryColor,
                scaffoldBackgroundColor: const Color(0xFF121212),
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: currentPrimaryColor,
                  brightness: Brightness.dark,
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: currentPrimaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  centerTitle: true,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentPrimaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: currentPrimaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              // 🚨 THE PERFECT TRAFFIC COP LOGIC
              home: widget.showOnboarding
                  ? const OnboardingScreen()
                  : (kIsWeb ? const LandingPageScreen() : const LoginScreen()),
            );
          },
        );
      },
    );
  }
}
