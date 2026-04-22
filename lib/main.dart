import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🚨 IMPORTED WEB CHECKER
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚨 UPDATED: Using bulletproof absolute imports
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/screens/auth/onboarding_screen.dart';
import 'package:trideta_v2/screens/admin/profile_menu_screen.dart';
import 'package:trideta_v2/screens/public/landing_page_screen.dart';

// 🚨 FIREBASE & NOTIFICATIONS IMPORTS
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:trideta_v2/services/notification_service.dart';
import 'firebase_options.dart';

// 1. GLOBAL KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 2. THE "HALL PASS" (Security Bypass Flag)
bool isInteractingWithSystem = false;

// 🚨 BACKGROUND NOTIFICATION HANDLER
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚨 INITIALIZE FIREBASE
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // INITIALIZE SUPABASE
  await Supabase.initialize(
    url: 'https://tkuupmyrodazfrrembsc.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrdXVwbXlyb2RhemZycmVtYnNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MzE2MTAsImV4cCI6MjA4NjIwNzYxMH0.D46NbF3tu7Eaq2HreH4auh0flNNggubZZdKs9xgZQ4k',
  );

  // 🚨 SMART NOTIFICATION WAKE-UP
  // On mobile: Ask immediately.
  // On Web: ONLY ask if they are actively logged in to avoid scaring public visitors!
  final session = Supabase.instance.client.auth.currentSession;
  if (!kIsWeb || session != null) {
    await NotificationService().initialize();
  }

  // 🚨 LOAD SAVED PREFERENCES
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('saved_theme');
  int? colorValue = prefs.getInt('app_primary_color');

  if (colorValue != null) {
    appColorNotifier.value = Color(colorValue);
  }

  final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

  // 🚨 WEB CHECK: If it is Web, NEVER show onboarding!
  final bool shouldShowOnboarding = kIsWeb ? false : !hasSeenOnboarding;

  if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.system;
  }

  runApp(MyApp(showOnboarding: shouldShowOnboarding));
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
              home: widget.showOnboarding
                  ? const OnboardingScreen()
                  : const LandingPageScreen(),
            );
          },
        );
      },
    );
  }
}
