import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- AUTH & SERVICES ---
import 'package:trideta_v2/services/auth_service.dart';
import 'package:trideta_v2/services/biometric_service.dart';
import 'package:trideta_v2/services/session_guard.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/services/app_activity_logger.dart'; // 🚨 INJECTED LOGGER

// --- SCREENS ---
import 'package:trideta_v2/dashboard.dart';
import 'package:trideta_v2/screens/parent/parent_dashboard_screen.dart';
import 'package:trideta_v2/screens/teacher/teacher_dashboard_screen.dart';
import 'package:trideta_v2/screens/admin/finance_dashboard_screen.dart';
import 'package:trideta_v2/screens/super_admin/trideta_owner_dashboard.dart';
import 'package:trideta_v2/screens/shared/setup_wizard.dart';
import 'package:trideta_v2/main.dart';

// 🚨 IMPORTED REGISTRATION & RECOVERY SCREENS
import 'package:trideta_v2/screens/auth/school_registration_screen.dart';
import 'package:trideta_v2/screens/auth/password_recovery_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with AuthErrorHandler {
  bool _isLoading = false;
  bool _canCheckBiometrics = false;
  int _currentStep = 0; // 0 = Email Step, 1 = Password Step
  bool _obscurePassword = true;

  // 🚨 SESSION RESUME: true while we silently check an existing persisted
  // session and route straight to the right dashboard, skipping the form.
  bool _isResumingSession = false;

  final _authService = AuthService();
  final _biometricService = BiometricService();
  final _supabase = Supabase.instance.client;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();

    final existingSession = _supabase.auth.currentSession;

    if (existingSession != null) {
      // A session already exists - skip the form and silently resume,
      // reusing the exact same routing/suspension/termination checks
      // that a fresh login already goes through.
      _isResumingSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Fast path: open the right dashboard straight from what was saved
        // on this phone, then re-check the account in the background.
        final opened = await _tryFastResume();
        if (!opened) await _checkAndNavigate();
        // Still here means navigation didn't happen (suspended, terminated,
        // or an error) - fall back to the normal login form instead of
        // leaving the user stuck on a spinner.
        if (mounted) setState(() => _isResumingSession = false);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowThemePopup();
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================================
  // 🎨 UI STATE & THEME LOGIC
  // ============================================================================
  void _proceedToPassword() {
    if (_emailController.text.trim().isEmpty) {
      showAuthErrorDialog("Please enter your Email or Phone Number.");
      return;
    }
    setState(() => _currentStep = 1);
  }

  // ============================================================================
  // ⚡ FAST RESUME: no waiting on the internet when a session already exists
  // ============================================================================
  Future<bool> _tryFastResume() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final snap = await SessionSnapshot.load(user.id);
      if (snap == null || !mounted) return false;

      final role = (snap['role'] ?? '').toString();
      if (role == 'admin' && snap['isConfigured'] != true) {
        return false; // unfinished school setup: use the normal checks
      }

      if (role == 'parent') {
        appColorNotifier.value = const Color(0xFF007ACC);
      } else if (snap['isOwner'] != true) {
        String? c = snap['brandColor']?.toString();
        if (c != null && c.isNotEmpty) {
          try {
            c = c.replaceAll('#', '');
            if (c.length == 6) c = 'FF$c';
            appColorNotifier.value = Color(int.parse(c, radix: 16));
          } catch (_) {}
        }
      }

      final Widget? target;
      if (snap['isOwner'] == true || role == 'owner') {
        target = const TridetaOwnerDashboard();
      } else if (role == 'admin') {
        if (snap['isAlsoParent'] == true) {
          _showRoleSelectionDialog(true);
          SessionGuard.revalidate();
          return true;
        }
        target = const DashboardScreen(userRole: "Admin");
      } else if (role == 'parent') {
        target = const ParentDashboardScreen();
      } else if (role == 'teacher') {
        target = TeacherDashboardScreen(userRole: role);
      } else if (role == 'bursar' || role == 'finance') {
        target = FinanceDashboardScreen(userRole: role);
      } else {
        target = null;
      }
      if (target == null) return false;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => target!),
      );
      SessionGuard.revalidate(); // checks suspension / termination quietly
      return true;
    } catch (e) {
      debugPrint('Fast resume skipped: $e');
      return false;
    }
  }

  Future<void> _checkAndShowThemePopup() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasChosenTheme = prefs.getBool('has_chosen_theme') ?? false;

    if (!hasChosenTheme && mounted) {
      _showThemeSelectionPopup(prefs);
    }
  }

  void _showThemeSelectionPopup(SharedPreferences prefs) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Choose Appearance",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(
              ctx,
              prefs,
              Icons.brightness_auto,
              "System Default",
              ThemeMode.system,
              isDark,
              primaryColor,
            ),
            const Divider(),
            _buildThemeOption(
              ctx,
              prefs,
              Icons.light_mode,
              "Light Mode",
              ThemeMode.light,
              isDark,
              primaryColor,
            ),
            const Divider(),
            _buildThemeOption(
              ctx,
              prefs,
              Icons.dark_mode,
              "Dark Mode",
              ThemeMode.dark,
              isDark,
              primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext ctx,
    SharedPreferences prefs,
    IconData icon,
    String title,
    ThemeMode mode,
    bool isDark,
    Color primary,
  ) {
    return ListTile(
      leading: Icon(icon, color: primary, size: 28),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        themeNotifier.value = mode;
        prefs.setBool('has_chosen_theme', true);
        Navigator.pop(ctx);
      },
    );
  }

  // ============================================================================
  // 🔐 AUTHENTICATION LOGIC
  // ============================================================================
  Future<void> _checkBiometrics() async {
    bool canCheck = await _biometricService.isBiometricAvailable();
    setState(() => _canCheckBiometrics = canCheck);
  }

  Future<void> _loginWithGoogle() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: primaryColor),
            const SizedBox(width: 10),
            Text(
              "Coming Soon",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        content: Text(
          "Google Sign-In integration is currently in progress. Please use your Login ID and password to sign in for now.",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Got it",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    final rawInput = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (rawInput.isEmpty || password.isEmpty) {
      showAuthErrorDialog(
        "Please enter both your Login ID and password to log in.",
      );
      return;
    }

    setState(() => _isLoading = true);

    String loginId = rawInput;
    final isPhoneLogin = !rawInput.contains('@');

    if (isPhoneLogin) {
      String formattedPhone = rawInput.replaceAll(' ', '');
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '+234${formattedPhone.substring(1)}';
      } else if (!formattedPhone.startsWith('+')) {
        formattedPhone = '+234$formattedPhone';
      }
      loginId = '$formattedPhone@trideta.com';
    }

    try {
      String? error = await _authService.login(loginId, password);

      if (error == null) {
        final storedCreds = await _biometricService.getCredentials();
        final isBiometricEnabledForThisUser =
            (storedCreds != null && storedCreds['email'] == loginId);

        if (_canCheckBiometrics && !isBiometricEnabledForThisUser) {
          if (mounted) {
            bool? wantsBiometrics = await _showBiometricPromptDialog(rawInput);
            if (wantsBiometrics == true) {
              bool passedChallenge = await _biometricService.authenticate();
              if (passedChallenge) {
                await _biometricService.saveCredentials(loginId, password);
                await _biometricService.setBiometricEnabled(true);
              } else {
                if (mounted) {
                  showAuthErrorDialog(
                    "Biometric scan failed. Auto-login was not enabled.",
                  );
                }
              }
            } else {
              await _biometricService.deleteCredentials();
            }
          }
        } else if (isBiometricEnabledForThisUser) {
          await _biometricService.saveCredentials(loginId, password);
          await _biometricService.setBiometricEnabled(true);
        }
        await _checkAndNavigate();
      } else {
        setState(() => _isLoading = false);
        showAuthErrorDialog(error);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      showAuthErrorDialog(e.toString());
    }
  }

  Future<bool?> _showBiometricPromptDialog(String email) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Icon(Icons.fingerprint, color: primaryColor, size: 50),
            const SizedBox(height: 10),
            Text(
              "Enable Quick Login?",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        content: Text(
          "Would you like to securely log in to $email on this device next time?",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Not Now",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Enable",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBiometricLogin() async {
    final creds = await _biometricService.getCredentials();

    if (creds == null) {
      showAuthErrorDialog(
        "No biometrics configured on this device yet. Please login manually first.",
      );
      return;
    }

    bool authenticated = await _biometricService.authenticate();
    if (authenticated) {
      setState(() => _isLoading = true);
      try {
        String? error = await _authService.login(
          creds['email']!,
          creds['password']!,
        );
        if (error == null) {
          await _checkAndNavigate();
        } else {
          setState(() => _isLoading = false);
          if (error.toLowerCase().contains("invalid login credentials")) {
            await _biometricService.deleteCredentials();
            showAuthErrorDialog(
              "Your password was changed recently. Please login manually to re-authorize your fingerprint.",
            );
          } else {
            showAuthErrorDialog("Auto-login failed: $error");
          }
        }
      } catch (e) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(e.toString());
      }
    }
  }

  // ============================================================================
  // 🧭 ROUTING LOGIC
  // ============================================================================
  Future<void> _checkAndNavigate() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw "Session error. Please try logging again.";

      final superAdminCheck = await _supabase
          .from('super_admins')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (superAdminCheck != null) {
        await SessionSnapshot.save(user.id, role: 'owner', isOwner: true);
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TridetaOwnerDashboard()),
        );
        return;
      }

      Map<String, dynamic>? profile = await _supabase
          .from('profiles')
          .select(
            'role, is_suspended, schools(brand_color, subscription_status)',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        bool profileCreated = false;
        final childrenRes = await _supabase
            .from('students')
            .select('school_id, parent_name')
            .eq('parent_email', user.email!)
            .limit(1);

        if (childrenRes.isNotEmpty) {
          await _supabase.from('profiles').insert({
            'id': user.id,
            'role': 'parent',
            'email': user.email,
            'full_name': childrenRes.first['parent_name'] ?? 'Parent',
            'school_id': childrenRes.first['school_id'],
          });
          profileCreated = true;
        } else {
          final teacherRes = await _supabase
              .from('teachers')
              .select('school_id, name')
              .eq('email', user.email!)
              .limit(1);
          if (teacherRes.isNotEmpty) {
            await _supabase.from('profiles').insert({
              'id': user.id,
              'role': 'teacher',
              'email': user.email,
              'full_name': teacherRes.first['name'] ?? 'Teacher',
              'school_id': teacherRes.first['school_id'],
            });
            profileCreated = true;
          }
        }
        if (profileCreated) {
          profile = await _supabase
              .from('profiles')
              .select(
                'role, is_suspended, schools(brand_color, subscription_status)',
              )
              .eq('id', user.id)
              .maybeSingle();
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (profile == null) {
        _supabase.auth.signOut();
        showAuthErrorDialog(
          "Your TriDeta profile hasn't been created yet. Please contact your School Administrator.",
        );
        return;
      }

      if (profile['is_suspended'] == true) {
        await _supabase.auth.signOut();
        if (mounted) {
          showAuthErrorDialog(
            "Access Denied. Your account has been suspended for violating community guidelines. Please contact support.",
          );
        }
        return;
      }

      if (profile['schools'] != null) {
        final subStatus = profile['schools']['subscription_status'];
        if (subStatus == 'terminated') {
          await _supabase.auth.signOut();
          if (mounted) {
            showAuthErrorDialog(
              "Access Denied. Your school's Trideta subscription has been terminated. Please contact your school administrator.",
            );
          }
          return;
        }
      }

      final String role = (profile['role'] ?? 'parent')
          .toString()
          .toLowerCase();

      // 🚨 INJECTED LOGGER LOGIC
      if (profile['school_id'] != null) {
        AppActivityLogger.log(
          schoolId: profile['school_id'].toString(),
          module: 'auth',
          action: 'login',
        );
      }

      if (role == 'parent') {
        appColorNotifier.value = const Color(0xFF007ACC);
      } else if (profile['schools'] != null) {
        String? dbColorStr = profile['schools']['brand_color'];
        if (dbColorStr != null && dbColorStr.isNotEmpty) {
          try {
            dbColorStr = dbColorStr.replaceAll('#', '');
            if (dbColorStr.length == 6) dbColorStr = 'FF$dbColorStr';
            final Color fetchedColor = Color(int.parse(dbColorStr, radix: 16));
            appColorNotifier.value = fetchedColor;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('app_primary_color', fetchedColor.toARGB32());
          } catch (e) {
            debugPrint("Failed to parse DB color: $e");
          }
        }
      }

      final String? brandStr = profile['schools']?['brand_color']?.toString();
      final String? subStr = profile['schools']?['subscription_status']
          ?.toString();
      if (role != 'admin') {
        await SessionSnapshot.save(
          user.id,
          role: role,
          brandColor: brandStr,
          subStatus: subStr,
        );
      }

      if (role == 'admin') {
        bool isConfigured = await _authService.isSchoolConfigured();
        final childrenRes = await _supabase
            .from('students')
            .select('id')
            .eq('parent_email', user.email!)
            .limit(1);
        bool isAlsoParent = childrenRes.isNotEmpty;
        await SessionSnapshot.save(
          user.id,
          role: role,
          isConfigured: isConfigured,
          isAlsoParent: isAlsoParent,
          brandColor: brandStr,
          subStatus: subStr,
        );

        if (isAlsoParent) {
          if (mounted) _showRoleSelectionDialog(isConfigured);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => isConfigured
                  ? const DashboardScreen(userRole: "Admin")
                  : const SetupWizardScreen(),
            ),
          );
        }
      } else if (role == 'parent') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
        );
      } else if (role == 'teacher') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherDashboardScreen(userRole: role),
          ),
        );
      } else if (role == 'bursar' || role == 'finance') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FinanceDashboardScreen(userRole: role),
          ),
        );
      } else {
        showAuthErrorDialog(
          "Unrecognized account type: '$role'. Please contact support.",
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(e.toString());
      }
    }
  }

  void _showRoleSelectionDialog(bool isConfigured) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Choose Dashboard",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your email is registered as an Administrator and a Parent.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: primaryColor.withValues(alpha: 0.1),
                child: Icon(Icons.admin_panel_settings, color: primaryColor),
              ),
              title: const Text(
                "Admin Dashboard",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "Manage school, staff, and settings",
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isConfigured
                        ? const DashboardScreen(userRole: "Admin")
                        : const SetupWizardScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                child: const Icon(Icons.family_restroom, color: Colors.green),
              ),
              title: const Text(
                "Parent Portal",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "View your children's records and fees",
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ParentDashboardScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // 🖼️ NEW UI BUILDER — presentation only. No authentication/routing logic
  // lives below this line; every button calls the original handlers above.
  // ============================================================================
  static const Color _brandGreen = Color(0xFF0B6B3A);
  static const Color _brandGreenLight = Color(0xFF4CC38A);
  static const double _desktopBreakpoint = 900;

  // Welcome (landing) view vs login form. Starts on the welcome view only when
  // there is no existing session, so the session-resume path is unaffected.
  late bool _showWelcome = _supabase.auth.currentSession == null;

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF0F1512) : const Color(0xFFF8FAF8);
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 SESSION RESUME: a valid session already exists, so skip the login
    // form entirely while _checkAndNavigate() (triggered in initState) routes
    // to the right dashboard.
    if (_isResumingSession) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    return PopScope(
      // System back from the login form returns to the welcome view.
      canPop: _showWelcome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _showWelcome = true);
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(
            key: ValueKey<bool>(_showWelcome),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= _desktopBreakpoint) {
                  return _buildDesktop(isDark);
                }
                return _buildMobile(constraints, isDark);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📱 MOBILE + TABLET (content is capped at 480px wide and centred on tablets)
  // ---------------------------------------------------------------------------
  Widget _buildMobile(BoxConstraints c, bool isDark) {
    if (_showWelcome) return _buildWelcomeMobile(c, isDark);
    final w = c.maxWidth;
    final compactHeight = c.maxHeight < 700;
    final tint = isDark
        ? _brandGreen.withValues(alpha: 0.18)
        : const Color(0xFFE3F0E8);
    final decorW = math.min(w * 0.62, 280.0);
    final heroW = compactHeight ? 210.0 : 290.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Soft corner circle (top-left)
        Positioned(
          top: -110,
          left: -110,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        // Books / pencils / plant decoration (bottom-right), behind the form
        Positioned(
          right: 0,
          bottom: 36,
          width: decorW,
          child: IgnorePointer(
            child: AspectRatio(
              aspectRatio: 300 / 190,
              child: CustomPaint(
                painter: _StudyScenePainter(
                  scene: _Scene.corner,
                  line: (isDark ? _brandGreenLight : _brandGreen).withValues(
                    alpha: 0.45,
                  ),
                  tint: tint,
                  paper: isDark
                      ? const Color(0xFF0F1512)
                      : const Color(0xFFF8FAF8),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: w < 380 ? 20.0 : 28.0,
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: heroW,
                        child: AspectRatio(
                          aspectRatio: 300 / 190,
                          child: CustomPaint(
                            painter: _StudyScenePainter(
                              scene: _Scene.hero,
                              line: isDark ? _brandGreenLight : _brandGreen,
                              tint: tint,
                              paper: isDark
                                  ? const Color(0xFF0F1512)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildForm(isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 🖥️ DESKTOP (>= 900px): illustration panel + form column
  // ---------------------------------------------------------------------------
  Widget _buildDesktop(bool isDark) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildDesktopPanel(isDark)),
        Expanded(
          flex: 5,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _showWelcome
                    ? _buildDesktopWelcome(isDark)
                    : _buildForm(isDark),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPanel(bool isDark) {
    final tint = isDark
        ? _brandGreen.withValues(alpha: 0.2)
        : const Color(0xFFD9ECE0);
    final ink = isDark ? Colors.white : const Color(0xFF0B1B14);
    final muted = isDark ? Colors.grey[400]! : const Color(0xFF5F7396);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF13211A), Color(0xFF0F1512)]
              : const [Color(0xFFE6F2EB), Color(0xFFF6FAF7)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            left: -120,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -130,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.45),
              ),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, pc) {
                final illoW = math.min(pc.maxWidth * 0.72, 480.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: illoW,
                          child: AspectRatio(
                            aspectRatio: 300 / 190,
                            child: CustomPaint(
                              painter: _StudyScenePainter(
                                scene: _Scene.globe,
                                line: isDark ? _brandGreenLight : _brandGreen,
                                tint: tint,
                                paper: isDark
                                    ? const Color(0xFF13211A)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "Manage your school\nwith ease",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: illoW > 380 ? 40 : 32,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -1,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Everything your school needs,\nin one place.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 👋 WELCOME VIEW ("Manage your school with ease")
  // ---------------------------------------------------------------------------
  void _continueAsGuest() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: primaryColor),
            const SizedBox(width: 10),
            Text(
              "Coming Soon",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        content: Text(
          "Guest access is currently in progress. Please log in or register with your email to continue for now.",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Got it",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeMobile(BoxConstraints c, bool isDark) {
    final w = c.maxWidth;
    final compactHeight = c.maxHeight < 700;
    final tint = isDark
        ? _brandGreen.withValues(alpha: 0.18)
        : const Color(0xFFE3F0E8);
    final ink = isDark ? Colors.white : const Color(0xFF0B1B14);
    final muted = isDark ? Colors.grey[400]! : const Color(0xFF5F7396);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -110,
          left: -110,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -130,
          right: -130,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: w < 380 ? 20.0 : 28.0,
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: compactHeight ? 240 : 320,
                        child: AspectRatio(
                          aspectRatio: 300 / 190,
                          child: CustomPaint(
                            painter: _StudyScenePainter(
                              scene: _Scene.globe,
                              line: isDark ? _brandGreenLight : _brandGreen,
                              tint: tint,
                              paper: isDark
                                  ? const Color(0xFF0F1512)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compactHeight ? 20 : 40),
                    Text(
                      "Manage your school\nwith ease",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -1,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "Everything your school needs,\nin one place.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, height: 1.4, color: muted),
                    ),
                    const SizedBox(height: 32),
                    _buildWelcomeActions(isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Desktop: the left panel already carries the headline and illustration,
  // so the right column only shows a short title plus the same actions.
  Widget _buildDesktopWelcome(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF0B1B14);
    final muted = isDark ? Colors.grey[400]! : const Color(0xFF5F7396);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Get started",
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.1,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Choose how you'd like to continue.",
          style: TextStyle(fontSize: 17, color: muted),
        ),
        const SizedBox(height: 32),
        _buildWelcomeActions(isDark),
      ],
    );
  }

  Widget _buildWelcomeActions(bool isDark) {
    final muted = isDark ? Colors.grey[400]! : const Color(0xFF5F7396);
    final accent = isDark ? _brandGreenLight : _brandGreen;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 🚨 GOOGLE → existing "Coming Soon" dialog
        SizedBox(
          height: 58,
          child: ElevatedButton(
            onPressed: _loginWithGoogle,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandGreen,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(painter: _GoogleLogoPainter()),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    "Continue with Google",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // REGISTER WITH EMAIL → same screen as the old "Sign up" link
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SchoolRegistrationScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: isDark ? Colors.transparent : Colors.white,
              side: BorderSide(color: accent, width: 1.2),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline_rounded, color: accent, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    "Register with email",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // 🚨 GUEST → "Coming Soon" dialog
        TextButton.icon(
          onPressed: _continueAsGuest,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          icon: Icon(Icons.person_outline_rounded, color: accent),
          label: Text(
            "Continue as Guest",
            style: TextStyle(
              color: accent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 18),

        // ALREADY HAVE AN ACCOUNT? → show the login form
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Already have an account? ",
                style: TextStyle(color: muted, fontSize: 14),
              ),
              GestureDetector(
                onTap: () => setState(() => _showWelcome = false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "Log in",
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: TextDecoration.underline,
                      decorationColor: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 🔐 THE FORM (shared by mobile, tablet and desktop — single set of
  // controllers and handlers, no duplicated logic)
  // ---------------------------------------------------------------------------
  Widget _buildForm(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF0B1B14);
    final muted = isDark ? Colors.grey[400]! : const Color(0xFF5F7396);
    final accent = isDark ? _brandGreenLight : _brandGreen;
    final borderColor = isDark ? Colors.white24 : const Color(0xFFD3E0EF);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Welcome back",
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.1,
            color: ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Sign in to continue to your school.",
          style: TextStyle(fontSize: 17, color: muted),
        ),
        const SizedBox(height: 32),

        // LOGIN ID (email or phone — same controller as before)
        _buildPillField(
          isDark: isDark,
          controller: _emailController,
          hint: "Email or phone number",
          icon: Icons.mail_outline_rounded,
          action: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 16),

        // PASSWORD
        _buildPillField(
          isDark: isDark,
          controller: _passwordController,
          hint: "Password",
          icon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          action: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: muted,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 8),

        // 🚨 PASSWORD RECOVERY (same navigation as before)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(
                    initialEmail: _emailController.text.trim(),
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              minimumSize: const Size(50, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              "Forgot password?",
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // LOG IN BUTTON
        SizedBox(
          height: 58,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandGreen,
              disabledBackgroundColor: _brandGreen.withValues(alpha: 0.6),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    "Log in",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 24),

        // OR CONTINUE WITH
        Row(
          children: [
            Expanded(child: Divider(color: borderColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "or continue with",
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
            Expanded(child: Divider(color: borderColor)),
          ],
        ),
        const SizedBox(height: 20),

        // 🚨 GOOGLE (same handler as before)
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: _loginWithGoogle,
            style: OutlinedButton.styleFrom(
              backgroundColor: isDark ? Colors.transparent : Colors.white,
              side: BorderSide(color: accent, width: 1.2),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(painter: _GoogleLogoPainter()),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    "Continue with Google",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 🚨 BIOMETRICS (only shown when available, same handler as before)
        if (_canCheckBiometrics) ...[
          const SizedBox(height: 20),
          Center(
            child: InkWell(
              onTap: _handleBiometricLogin,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fingerprint_rounded, size: 44, color: accent),
                    const SizedBox(height: 4),
                    Text(
                      "Login with biometrics",
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),

        _buildSignUpText(isDark, accent),
      ],
    );
  }

  // Pill-shaped text field used for both Login ID and Password
  Widget _buildPillField({
    required bool isDark,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
  }) {
    final muted = isDark ? Colors.white54 : const Color(0xFF5F7396);
    final borderColor = isDark ? Colors.white24 : const Color(0xFFD3E0EF);
    final accent = isDark ? _brandGreenLight : _brandGreen;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(32),
      borderSide: BorderSide(color: color, width: width),
    );

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: action,
      style: TextStyle(
        fontSize: 16,
        color: isDark ? Colors.white : const Color(0xFF0B1B14),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: muted, fontSize: 16),
        filled: true,
        fillColor: isDark ? const Color(0xFF1A211D) : Colors.white,
        prefixIcon: Icon(icon, color: muted),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        border: border(borderColor, 1),
        enabledBorder: border(borderColor, 1),
        focusedBorder: border(accent, 1.8),
      ),
      onFieldSubmitted: onSubmitted,
    );
  }

  // Clickable "Create account" row (same navigation as the old Sign Up link)
  Widget _buildSignUpText(bool isDark, Color accent) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "New to Trideta? ",
            style: TextStyle(
              color: isDark ? Colors.grey[400] : const Color(0xFF5F7396),
              fontSize: 14,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SchoolRegistrationScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                "Create account",
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 🎨 DECORATIVE PAINTERS (pure drawing — no assets or packages required)
// =============================================================================
enum _Scene { hero, globe, corner }

class _StudyScenePainter extends CustomPainter {
  final _Scene scene;
  final Color line;
  final Color tint;
  final Color paper;

  const _StudyScenePainter({
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

    // Cloud-like soft background shape
    if (scene != _Scene.corner) {
      canvas.drawCircle(const Offset(105, 112), 58, tintPaint);
      canvas.drawCircle(const Offset(175, 98), 54, tintPaint);
      canvas.drawCircle(const Offset(232, 128), 44, tintPaint);
      canvas.drawRect(const Rect.fromLTWH(48, 118, 224, 57), tintPaint);
    }

    // Ground line
    canvas.drawLine(const Offset(4, 175), const Offset(296, 175), stroke);

    if (scene == _Scene.corner) {
      book(const Rect.fromLTWH(6, 163, 116, 12));
      book(const Rect.fromLTWH(26, 151, 104, 12));
      book(const Rect.fromLTWH(16, 139, 110, 12));
      cupWithPencils(150);
      plantInVase(240, 175);
      canvas.restore();
      return;
    }

    // Stack of books + graduation cap
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

    // Standing books and pencil cup
    rrect(const Rect.fromLTWH(152, 108, 13, 67), 2);
    rrect(const Rect.fromLTWH(167, 118, 11, 57), 2);
    cupWithPencils(184);

    if (scene == _Scene.hero) {
      plantInVase(252, 175);
    } else {
      // Globe
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
  bool shouldRepaint(covariant _StudyScenePainter old) =>
      old.scene != scene ||
      old.line != line ||
      old.tint != tint ||
      old.paper != paper;
}

// Multi-colour Google "G" drawn with arcs (no image asset needed)
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.36;
    final sw = size.width * 0.2;
    final rect = Rect.fromCircle(center: c, radius: r);

    Paint p(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..color = color;

    canvas.drawArc(rect, -2.35, 1.55, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 2.4, 1.54, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 0.85, 1.55, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 0.0, 0.85, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(
      c,
      Offset(c.dx + r + sw / 2, c.dy),
      p(const Color(0xFF4285F4)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
