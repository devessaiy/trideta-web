import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

// 🚨 MODULAR UI IMPORTS (Fixed to point to your new components)
import 'package:trideta_v2/screens/auth/components/login_branding_panel.dart';
import 'package:trideta_v2/screens/auth/components/email_entry_step.dart';
import 'package:trideta_v2/screens/auth/components/password_entry_step.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with AuthErrorHandler {
  bool _isLoading = false;
  bool _canCheckBiometrics = false;
  int _currentStep = 0; // 0 = Email Step, 1 = Password Step

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
  // 🚨 UI STATE & THEME LOGIC
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
  // 🚨 AUTHENTICATION LOGIC
  // ============================================================================
  Future<void> _checkBiometrics() async {
    bool canCheck = await _biometricService.isBiometricAvailable();
    setState(() => _canCheckBiometrics = canCheck);
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      const webClientId =
          '141687394764-9fm23jupir4196b7h5ku0dvnullt7suu.apps.googleusercontent.com';

      // 1. Initialize the new v7+ Singleton
      await GoogleSignIn.instance.initialize(serverClientId: webClientId);

      // 2. Trigger the Native Bottom Sheet (signIn is now authenticate)
      final googleUser = await GoogleSignIn.instance.authenticate();

      // ignore: dead_code
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Extract the ID Token
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      // 4. Extract the Access Token (Moved to a separate authorization client in v7+)
      final authorizedUser = await googleUser.authorizationClient
          .authorizeScopes([]);
      final accessToken = authorizedUser.accessToken;

      if (idToken == null) {
        throw 'Missing Google Auth Token. Please try again.';
      }

      // 5. Pass both tokens to Supabase
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // 6. Route to the correct dashboard
      await _checkAndNavigate();
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Google Sign-In Failed.\n\nError: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                if (mounted)
                  showAuthErrorDialog(
                    "Biometric scan failed. Auto-login was not enabled.",
                  );
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
  // 🚨 ROUTING LOGIC
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
        if (profileCreated)
          profile = await _supabase
              .from('profiles')
              .select(
                'role, is_suspended, schools(brand_color, subscription_status)',
              )
              .eq('id', user.id)
              .maybeSingle();
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
        if (mounted)
          showAuthErrorDialog(
            "Access Denied. Your account has been suspended for violating community guidelines. Please contact support.",
          );
        return;
      }

      if (profile['schools'] != null) {
        final subStatus = profile['schools']['subscription_status'];
        if (subStatus == 'terminated') {
          await _supabase.auth.signOut();
          if (mounted)
            showAuthErrorDialog(
              "Access Denied. Your school's Trideta subscription has been terminated. Please contact your school administrator.",
            );
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
  // 🚨 UI BUILDER
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
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
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: _buildLoginForm(isDark, primaryColor),
                    ),
                  ),
                ),
              ],
            );
          } else {
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

  Widget _buildLoginForm(
    bool isDark,
    Color primaryColor, {
    bool isMobile = false,
  }) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

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

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: _currentStep == 0
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: EmailEntryStep(
            emailController: _emailController,
            isLoading: _isLoading,
            canCheckBiometrics: _canCheckBiometrics,
            onProceed: _proceedToPassword,
            onGoogleLogin: _loginWithGoogle,
            onBiometricLogin: _handleBiometricLogin,
          ),
          secondChild: PasswordEntryStep(
            passwordController: _passwordController,
            emailText: _emailController.text,
            isLoading: _isLoading,
            onLogin: _handleLogin,
            onEditEmail: () => setState(() => _currentStep = 0),
          ),
        ),
      ],
    );
  }
}
