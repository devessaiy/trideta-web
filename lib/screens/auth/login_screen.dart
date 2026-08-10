import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- AUTH & SERVICES ---
import 'package:trideta_v2/services/auth_service.dart';
import 'package:trideta_v2/services/biometric_service.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';

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

// --- MODULAR UI IMPORTS ---
import 'package:trideta_v2/screens/auth/components/login_branding_panel.dart';

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
  // 🖼️ NEW UI BUILDER
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9);
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: LoginBrandingPanel(primaryColor: primaryColor),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SingleChildScrollView(
                        child: _buildMainFormContent(isDark, primaryColor),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 24.0,
                  ),
                  child: _buildMainFormContent(isDark, primaryColor),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildMainFormContent(bool isDark, Color primaryColor) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- THE MODERN CARD ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back Button (Only visible on Password Step)
              AnimatedOpacity(
                opacity: _currentStep == 1 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _currentStep == 1
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => setState(() => _currentStep = 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_back,
                                size: 18,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Back",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(
                        height: 24,
                      ), // Placeholder to keep height consistent
              ),
              const SizedBox(height: 16),

              // HEADER: Building Icon & Welcome Text
              Icon(
                Icons.account_balance_rounded,
                size: 54,
                color: primaryColor,
              ),
              const SizedBox(height: 24),
              Text(
                "Welcome Back",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Sign in to your school account",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 40),

              // ANIMATED FORM STEPS
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _currentStep == 0
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: _buildEmailStepUI(isDark, primaryColor),
                secondChild: _buildPasswordStepUI(isDark, primaryColor),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // --- BOTTOM TRUST BANNER ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              "Secure • Reliable • Trusted",
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper widget to handle the clickable Sign Up text block
  Widget _buildSignUpText(bool isDark, Color primaryColor) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(
            "Don't have an account? ",
            style: TextStyle(
              color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
              fontSize: 13,
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
            child: Text(
              "Sign up here!",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 1: EMAIL ENTRY UI ---
  Widget _buildEmailStepUI(bool isDark, Color primaryColor) {
    Color borderColor = isDark ? Colors.white24 : const Color(0xFFE5E7EB);
    Color labelColor = isDark ? Colors.white : const Color(0xFF111827);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Login ID",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: "Enter your email or username",
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
            prefixIcon: Icon(
              Icons.person_outline,
              color: isDark ? Colors.white54 : Colors.grey[500],
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
          ),
          onFieldSubmitted: (_) => _proceedToPassword(),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _proceedToPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Next",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Divider(color: borderColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "or",
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(child: Divider(color: borderColor)),
          ],
        ),
        const SizedBox(height: 24),

        // 🚨 GOOGLE & BIOMETRICS
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialButton(
              Icons.g_mobiledata_rounded,
              "Google",
              _loginWithGoogle,
              isDark,
              borderColor,
            ),
            if (_canCheckBiometrics) ...[
              const SizedBox(width: 16),
              _buildSocialButton(
                Icons.fingerprint_rounded,
                "Biometrics",
                _handleBiometricLogin,
                isDark,
                borderColor,
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),

        _buildSignUpText(isDark, primaryColor),
      ],
    );
  }

  // --- STEP 2: PASSWORD ENTRY UI ---
  Widget _buildPasswordStepUI(bool isDark, Color primaryColor) {
    Color borderColor = isDark ? Colors.white24 : const Color(0xFFE5E7EB);
    Color labelColor = isDark ? Colors.white : const Color(0xFF111827);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Read-only Email display box with "Change" button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.mail_outline,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _emailController.text,
                  style: TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text("Change", style: TextStyle(color: primaryColor)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          "Password",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: "Enter your password",
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: isDark ? Colors.white54 : Colors.grey[500],
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
          ),
          onFieldSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: 12),

        // 🚨 ADDED NAVIGATOR FOR PASSWORD RECOVERY
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
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              "Reset password",
              style: TextStyle(color: primaryColor, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Sign in",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Divider(color: borderColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "or",
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(child: Divider(color: borderColor)),
          ],
        ),
        const SizedBox(height: 24),

        _buildSignUpText(isDark, primaryColor),
      ],
    );
  }

  // Helper widget to keep the social buttons looking clean and matching the border styling
  Widget _buildSocialButton(
    IconData icon,
    String label,
    VoidCallback onTap,
    bool isDark,
    Color borderColor,
  ) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 24,
          color: isDark ? Colors.white : Colors.black87,
        ),
        label: Text(
          label,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
