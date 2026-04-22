import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:trideta_v2/dashboard.dart';
import 'package:trideta_v2/screens/parent/parent_dashboard_screen.dart';
import 'package:trideta_v2/screens/teacher/teacher_dashboard_screen.dart';
import 'package:trideta_v2/screens/admin/finance_dashboard_screen.dart';
import 'package:trideta_v2/services/auth_service.dart';
import 'package:trideta_v2/services/biometric_service.dart';
import 'package:trideta_v2/screens/auth/school_registration_screen.dart';
import 'package:trideta_v2/screens/shared/setup_wizard.dart';

// 🚨 MODULAR IMPORTS
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/screens/auth/password_recovery_screens.dart';
import 'package:trideta_v2/main.dart'; // 🚨 Added to access appColorNotifier

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with AuthErrorHandler {
  bool _isObscure = true;
  bool _isLoading = false;
  bool _canCheckBiometrics = false;

  final _authService = AuthService();
  final _biometricService = BiometricService();
  final _supabase = Supabase.instance.client;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowThemePopup();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  Future<void> _checkBiometrics() async {
    bool canCheck = await _biometricService.isBiometricAvailable();
    setState(() => _canCheckBiometrics = canCheck);
  }

  // ============================================================================
  // 🚨 LOGIN LOGIC (With Phantom Email Implementation)
  // ============================================================================
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

    // 🚨 PHANTOM EMAIL CONVERSION LOGIC
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
      // Pass the converted loginId to Supabase
      String? error = await _authService.login(loginId, password);

      if (error == null) {
        final storedCreds = await _biometricService.getCredentials();
        final isBiometricEnabledForThisUser =
            (storedCreds != null && storedCreds['email'] == loginId);

        if (_canCheckBiometrics && !isBiometricEnabledForThisUser) {
          if (mounted) {
            // Ask using the clean rawInput so the user doesn't see @trideta.com
            bool? wantsBiometrics = await _showBiometricPromptDialog(rawInput);

            if (wantsBiometrics == true) {
              bool passedChallenge = await _biometricService.authenticate();
              if (passedChallenge) {
                // Safely save the Phantom Email to storage for future auto-logins
                await _biometricService.saveCredentials(loginId, password);
                await _biometricService.setBiometricEnabled(true);
                if (mounted) {
                  showSuccessDialog(
                    "Security Updated",
                    "Quick login with Fingerprint/Face ID is now enabled for this device.",
                  );
                }
              } else {
                if (mounted) {
                  showAuthErrorDialog(
                    "Fingerprint/Face scan failed. Biometric login was not enabled.",
                  );
                }
              }
            } else {
              await _biometricService.deleteCredentials();
            }
          }
        } else if (isBiometricEnabledForThisUser) {
          // Refresh credentials in case password was changed externally
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
          "Would you like to use your fingerprint or face to securely log in to $email on this device next time?",
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
        "No biometrics configured on this device yet. Please login manually with your password first to enable it.",
      );
      return;
    }

    bool authenticated = await _biometricService.authenticate();
    if (authenticated) {
      setState(() => _isLoading = true);
      try {
        String? error = await _authService.login(
          creds['email']!, // This now injects the phantom email smoothly!
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

  // 🚨 THE MAGIC INJECTION: Fetching Color before Routing!
  Future<void> _checkAndNavigate() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw "Session error. Please try logging again.";

      // 🚨 Added schools(brand_color) to your Supabase query
      final profile = await _supabase
          .from('profiles')
          .select('role, schools(brand_color)')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (profile == null) {
        _supabase.auth.signOut();
        showAuthErrorDialog(
          "Your TriDeta profile hasn't been created yet. Please contact your School Administrator.",
        );
        return;
      }

      final String role = (profile['role'] ?? 'parent')
          .toString()
          .toLowerCase();

      // ==========================================
      // 🚨 BRAND COLOR SPLIT LOGIC
      // ==========================================
      if (role == 'parent') {
        appColorNotifier.value = const Color(
          0xFF007ACC,
        ); // Lock to Trideta Blue
      } else if (profile['schools'] != null) {
        final dbColorStr = profile['schools']['brand_color'];
        if (dbColorStr != null && dbColorStr.toString().isNotEmpty) {
          try {
            final Color fetchedColor = Color(int.parse(dbColorStr.toString()));
            appColorNotifier.value = fetchedColor;

            // Backup the color to memory so the BootSplashScreen catches it later
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('app_primary_color', fetchedColor.value);
          } catch (e) {
            debugPrint("Failed to parse color: $e");
          }
        }
      }
      // ==========================================

      if (role == 'admin') {
        bool isConfigured = await _authService.isSchoolConfigured();
        final childrenRes = await _supabase
            .from('students')
            .select('id')
            .eq('parent_email', user.email!)
            .limit(1);
        bool isAlsoParent = childrenRes.isNotEmpty;

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
              "Your email is registered as an Administrator and a Parent. Which dashboard do you want to open?",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: primaryColor.withOpacity(0.1),
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
                backgroundColor: Colors.green.withOpacity(0.1),
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 SPLIT SCREEN LOGIC FOR WEB
    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // DESKTOP: Split Screen
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor.withOpacity(0.8), primaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.school_rounded,
                            size: 100,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "TRIDETA",
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 3.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Next-Generation School Management",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: _buildLoginForm(isDark, primaryColor),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // MOBILE: Centered Column
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: _buildLoginForm(isDark, primaryColor, isMobile: true),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // 🚨 THE EXTRACTED LOGIN FORM (Used by both Mobile and Web)
  Widget _buildLoginForm(
    bool isDark,
    Color primaryColor, {
    bool isMobile = false,
  }) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    Color fieldColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isMobile) ...[
          Icon(Icons.admin_panel_settings, size: 70, color: primaryColor),
          const SizedBox(height: 10),
          Text(
            "TRIDETA",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 40),
        ],
        Text(
          "Welcome Back",
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Login to your account to continue",
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(fontSize: 16, color: hintColor),
        ),
        const SizedBox(height: 40),

        // 🚨 UPDATED TO HANDLE BOTH EMAIL AND PHONE
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.person_outline,
              color: hintColor,
            ), // 🚨 Updated Icon
            labelText: "Email or Phone Number", // 🚨 Updated Label
            labelStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: fieldColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _passwordController,
          obscureText: _isObscure,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.lock_outline, color: hintColor),
            suffixIcon: IconButton(
              icon: Icon(
                _isObscure ? Icons.visibility : Icons.visibility_off,
                color: hintColor,
              ),
              onPressed: () => setState(() => _isObscure = !_isObscure),
            ),
            labelText: "Password",
            labelStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: fieldColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
          ),
        ),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ForgotPasswordScreen(initialEmail: _emailController.text),
              ),
            ),
            child: Text(
              "Forgot Password?",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Text(
                    "SECURE LOGIN",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
          ),
        ),

        if (_canCheckBiometrics) ...[
          const SizedBox(height: 30),
          GestureDetector(
            onTap: _handleBiometricLogin,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fingerprint, size: 40, color: primaryColor),
                ),
                const SizedBox(height: 10),
                Text(
                  "Login with Biometrics",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
