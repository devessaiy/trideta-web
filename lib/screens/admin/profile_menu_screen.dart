import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚨 UPDATED ABSOLUTE IMPORTS
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/screens/admin/school_profile_screen.dart';
import 'package:trideta_v2/screens/admin/school_configuration_screen.dart';
import 'package:trideta_v2/services/biometric_service.dart';

// 🚨 GLOBAL COLOR NOTIFIER: Use this in main.dart's MaterialApp to theme the entire app!
final ValueNotifier<Color> appColorNotifier = ValueNotifier(
  const Color(0xFF007ACC),
);

class ProfileMenuScreen extends StatefulWidget {
  const ProfileMenuScreen({super.key});

  @override
  State<ProfileMenuScreen> createState() => _ProfileMenuScreenState();
}

class _ProfileMenuScreenState extends State<ProfileMenuScreen>
    with AuthErrorHandler {
  @override
  void initState() {
    super.initState();
    _loadSavedColor();
  }

  // --- LOAD SAVED BRAND COLOR ---
  Future<void> _loadSavedColor() async {
    final prefs = await SharedPreferences.getInstance();
    int? colorValue = prefs.getInt('app_primary_color');
    if (colorValue != null) {
      appColorNotifier.value = Color(colorValue);
    }
  }

  // --- APPEARANCE / THEME LOGIC ---
  void _showAppearanceSettings(BuildContext context, Color currentPrimary) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "App Appearance",
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
              Icons.brightness_auto,
              "System Default",
              ThemeMode.system,
              isDark,
              currentPrimary,
            ),
            const Divider(),
            _buildThemeOption(
              ctx,
              Icons.light_mode,
              "Light Mode",
              ThemeMode.light,
              isDark,
              currentPrimary,
            ),
            const Divider(),
            _buildThemeOption(
              ctx,
              Icons.dark_mode,
              "Dark Mode",
              ThemeMode.dark,
              isDark,
              currentPrimary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext ctx,
    IconData icon,
    String title,
    ThemeMode mode,
    bool isDark,
    Color currentPrimary,
  ) {
    return ListTile(
      leading: Icon(icon, color: currentPrimary, size: 28),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () async {
        themeNotifier.value = mode;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_chosen_theme', true);
        await prefs.setString('saved_theme', mode.toString().split('.').last);
        if (ctx.mounted) Navigator.pop(ctx);
      },
    );
  }

  // --- BRAND COLOR PICKER LOGIC ---
  void _showColorPicker(BuildContext context, Color currentPrimary) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> schoolColors = [
      {'name': 'TriDeta Blue', 'color': const Color(0xFF007ACC)},
      {'name': 'Emerald Green', 'color': const Color(0xFF2E7D32)},
      {'name': 'Royal Purple', 'color': const Color(0xFF6A1B9A)},
      {'name': 'Crimson Red', 'color': const Color(0xFFC62828)},
      {'name': 'Sunset Orange', 'color': const Color(0xFFEF6C00)},
      {'name': 'Midnight Navy', 'color': const Color(0xFF1A237E)},
      {'name': 'Ocean Teal', 'color': const Color(0xFF00695C)},
      {'name': 'Deep Maroon', 'color': const Color(0xFF880E4F)},
      {'name': 'Light Green', 'color': const Color.fromARGB(255, 87, 164, 35)},
      {
        'name': 'Golden Green',
        'color': const Color.fromARGB(255, 109, 136, 14),
      },
      {'name': 'Gold', 'color': const Color.fromARGB(255, 101, 85, 3)},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "School Brand Color",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Wrap(
          spacing: 15,
          runSpacing: 15,
          alignment: WrapAlignment.center,
          children: schoolColors.map((item) {
            Color c = item['color'];
            bool isSelected = currentPrimary.value == c.value;

            return GestureDetector(
              onTap: () async {
                appColorNotifier.value = c;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('app_primary_color', c.value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: isDark ? Colors.white : Colors.black87,
                              width: 3,
                            )
                          : null,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 60,
                    child: Text(
                      item['name'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- HELP & SUPPORT MENU LOGIC ---
  void _showSupportMenu(BuildContext context, Color currentPrimary) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Help & Support",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.green,
                size: 28,
              ),
              title: Text(
                "WhatsApp Support",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                "Chat with TriDeta",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsApp(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.phone_in_talk_rounded,
                color: Colors.blue,
                size: 28,
              ),
              title: Text(
                "Direct Call",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                "07040686186",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _launchPhoneCall(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final Uri whatsappUrl = Uri.parse(
      "https://wa.me/2347015339793?text=Hello%20TriDeta%20Support,%20I%20need%20help%20with%20my%20school%20app.",
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          showAuthErrorDialog(
            "Could not open WhatsApp. Please ensure the app is installed on your device.",
          );
        }
      }
    } catch (e) {
      debugPrint("WhatsApp Error: $e");
      if (context.mounted) {
        showAuthErrorDialog("An error occurred while trying to open WhatsApp.");
      }
    }
  }

  Future<void> _launchPhoneCall(BuildContext context) async {
    final Uri phoneUrl = Uri.parse("tel:07040686186");

    try {
      if (await canLaunchUrl(phoneUrl)) {
        await launchUrl(phoneUrl);
      } else {
        if (context.mounted) {
          showAuthErrorDialog(
            "Could not launch the phone dialer. Your device might not support direct calling.",
          );
        }
      }
    } catch (e) {
      debugPrint("Phone Call Error: $e");
      if (context.mounted) {
        showAuthErrorDialog("An error occurred while trying to make a call.");
      }
    }
  }

  // --- LOGOUT LOGIC ---
  Future<void> _handleLogout(BuildContext context, Color currentPrimary) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.logout_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text("Sign Out?"),
              ],
            ),
            content: const Text(
              "Are you sure you want to log out of your administrative session?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "LOGOUT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // --- DELETE ENTIRE SCHOOL MODULE ---
  Future<void> _handleDeleteSchool(BuildContext context) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Column(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 60,
                ),
                SizedBox(height: 15),
                Text(
                  "DELETE ENTIRE SCHOOL?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: const Text(
              "This is a destructive action. You are about to permanently wipe all students, staff, financial records, and settings associated with this school.\n\nTHIS CANNOT BE UNDONE.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.only(
              bottom: 20,
              left: 20,
              right: 20,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "YES, WIPE DATA",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (context.mounted) Navigator.pop(context);

      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      showAuthErrorDialog(
        "Failed to delete school data. Please contact TriDeta support for manual wipe.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: appColorNotifier,
      builder: (context, dynamicPrimaryColor, child) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;
        Color bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF8FAFC);

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              "Menu & Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: dynamicPrimaryColor,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            elevation: 0,
            centerTitle: true,
          ),
          // 🚨 SHAPE-SHIFTER: LayoutBuilder added here!
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                // 💻 DESKTOP LAYOUT
                return Center(
                  child: Container(
                    width: 600,
                    margin: const EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _buildMenuContent(isDark, dynamicPrimaryColor),
                    ),
                  ),
                );
              } else {
                // 📱 MOBILE LAYOUT
                return _buildMenuContent(isDark, dynamicPrimaryColor);
              }
            },
          ),
        );
      },
    );
  }

  // 🚨 EXTRACTED MENU CONTENT (Shared by both Mobile and Web)
  Widget _buildMenuContent(bool isDark, Color dynamicPrimaryColor) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      children: [
        const MenuSectionHeader(title: "SCHOOL MANAGEMENT"),

        MenuActionCard(
          icon: Icons.store_mall_directory_rounded,
          title: "School Profile",
          subtitle: "Name, Logo, Address",
          color: dynamicPrimaryColor,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SchoolProfileScreen()),
          ),
          isDark: isDark,
        ),
        MenuActionCard(
          icon: Icons.account_tree_rounded,
          title: "School Configuration",
          subtitle: "Classes, Subjects & Structure",
          color: Colors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SchoolConfigurationScreen(),
            ),
          ),
          isDark: isDark,
        ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 15),

        const MenuSectionHeader(title: "APPEARANCE & SECURITY"),

        MenuActionCard(
          icon: Icons.palette_rounded,
          title: "App Appearance",
          subtitle: "Dark Mode, Light Mode, System",
          color: Colors.orange,
          onTap: () => _showAppearanceSettings(context, dynamicPrimaryColor),
          isDark: isDark,
        ),

        MenuActionCard(
          icon: Icons.color_lens_rounded,
          title: "Brand Color",
          subtitle: "Match your school uniform",
          color: dynamicPrimaryColor,
          onTap: () => _showColorPicker(context, dynamicPrimaryColor),
          isDark: isDark,
        ),

        MenuActionCard(
          icon: Icons.shield_rounded,
          title: "Security Settings",
          subtitle: "Password & Biometrics",
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
          ),
          isDark: isDark,
        ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 15),

        const MenuSectionHeader(title: "SUPPORT & ACCOUNT"),

        MenuActionCard(
          icon: Icons.support_agent_rounded,
          title: "Help & Support",
          subtitle: "WhatsApp Chat or Direct Call",
          color: Colors.green,
          onTap: () => _showSupportMenu(context, dynamicPrimaryColor),
          isDark: isDark,
        ),

        MenuActionCard(
          icon: Icons.logout_rounded,
          title: "Sign Out",
          subtitle: "Securely close session",
          color: Colors.orange,
          onTap: () => _handleLogout(context, dynamicPrimaryColor),
          isDark: isDark,
        ),

        const SizedBox(height: 15),

        MenuActionCard(
          icon: Icons.delete_forever_rounded,
          title: "Delete School Account",
          subtitle: "Permanently wipe all records",
          color: Colors.redAccent,
          onTap: () => _handleDeleteSchool(context),
          isDark: isDark,
        ),

        const SizedBox(height: 40),
        Center(
          child: Text(
            "TriDeta Admin v3.0.0",
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Center(
          child: Text(
            "Powered by TriDeta",
            style: TextStyle(color: Colors.grey[400], fontSize: 9),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

// ============================================================================
// SECURITY SETTINGS SCREEN
// ============================================================================

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;
  final _biometricService = BiometricService();

  bool _biometricsEnabled = false;
  bool _isLoading = true;
  String? _userId;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadSecurityPreferences();
  }

  Future<void> _loadSecurityPreferences() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _userId = user.id;
      _userEmail = user.email;

      bool isEnabledGlobally = await _biometricService.isBiometricEnabled();
      final creds = await _biometricService.getCredentials();
      bool belongsToThisUser = (creds != null && creds['email'] == _userEmail);

      if (mounted) {
        setState(() {
          _biometricsEnabled = isEnabledGlobally && belongsToThisUser;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleBiometrics(bool newValue) async {
    if (_userId == null || _userEmail == null) return;

    if (newValue == true) {
      bool passedChallenge = await _biometricService.authenticate();

      if (passedChallenge) {
        await _biometricService.setBiometricEnabled(true);

        final creds = await _biometricService.getCredentials();
        if (creds == null || creds['password'] == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Biometrics enabled. Please log out and log back in manually once to finish setup.",
                ),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Biometrics enabled securely."),
                backgroundColor: Colors.teal,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        setState(() => _biometricsEnabled = true);
      } else {
        if (mounted) {
          showAuthErrorDialog("Biometric verification failed.");
        }
        setState(() => _biometricsEnabled = false);
      }
    } else {
      await _biometricService.setBiometricEnabled(false);

      setState(() => _biometricsEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Biometrics disabled and credentials cleared."),
            backgroundColor: Colors.grey[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showPasswordModal(Color currentPrimary) {
    final passwordController = TextEditingController();
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 24,
                right: 24,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: SingleChildScrollView(
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
                      "Change Admin Password",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Enter a new strong password to secure your admin account. You will remain logged in.",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 25),

                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        prefixIcon: Icon(
                          Icons.lock_rounded,
                          color: currentPrimary,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: isUpdating
                            ? null
                            : () async {
                                if (passwordController.text.length < 6) {
                                  showAuthErrorDialog(
                                    "Password must be at least 6 characters long.",
                                  );
                                  return;
                                }

                                setModalState(() => isUpdating = true);

                                try {
                                  await _supabase.auth.updateUser(
                                    UserAttributes(
                                      password: passwordController.text.trim(),
                                    ),
                                  );

                                  await _biometricService.deleteCredentials();
                                  _loadSecurityPreferences();

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Password updated securely. If you use Biometrics, please re-enable them.",
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isUpdating = false);
                                  showAuthErrorDialog(
                                    "Failed to update password. Ensure your session is active and try again.",
                                  );
                                }
                              },
                        child: isUpdating
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                "UPDATE PASSWORD",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: appColorNotifier,
      builder: (context, dynamicPrimaryColor, child) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;
        Color bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF8FAFC);
        Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        if (_isLoading) {
          return Scaffold(
            backgroundColor: bgColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              "Security Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: dynamicPrimaryColor,
            foregroundColor: Colors.white,
            centerTitle: true,
            elevation: 0,
          ),
          // 🚨 SHAPE-SHIFTER: LayoutBuilder added for Security Settings
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                // 💻 DESKTOP LAYOUT
                return Center(
                  child: Container(
                    width: 600,
                    margin: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _buildSecurityContent(
                        isDark,
                        dynamicPrimaryColor,
                        cardColor,
                      ),
                    ),
                  ),
                );
              } else {
                // 📱 MOBILE LAYOUT
                return _buildSecurityContent(
                  isDark,
                  dynamicPrimaryColor,
                  cardColor,
                );
              }
            },
          ),
        );
      },
    );
  }

  // 🚨 EXTRACTED SECURITY CONTENT
  Widget _buildSecurityContent(
    bool isDark,
    Color dynamicPrimaryColor,
    Color cardColor,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const MenuSectionHeader(title: "AUTHENTICATION & ACCESS"),

        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: dynamicPrimaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.password_rounded, color: dynamicPrimaryColor),
            ),
            title: const Text(
              "Change Password",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              "Update your admin login password",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey,
            ),
            onTap: () => _showPasswordModal(dynamicPrimaryColor),
          ),
        ),

        const SizedBox(height: 15),

        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            secondary: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fingerprint_rounded, color: Colors.teal),
            ),
            title: const Text(
              "Biometric Login",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              "Use Face ID or Fingerprint to unlock",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            activeThumbColor: Colors.teal,
            value: _biometricsEnabled,
            onChanged: _toggleBiometrics,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// MODULAR UI COMPONENTS
// ============================================================================

class MenuSectionHeader extends StatelessWidget {
  final String title;
  const MenuSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Colors.grey,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class MenuActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;

  const MenuActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Colors.grey,
        ),
      ),
    );
  }
}
