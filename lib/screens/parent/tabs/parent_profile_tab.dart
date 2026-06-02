import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 IMPORT YOUR MAIN.DART SO WE CAN TALK TO YOUR THEME NOTIFIER!
import 'package:trideta_v2/main.dart';
// 🚨 IMPORT YOUR LOGIN SCREEN SO WE CAN NAVIGATE THERE!
import 'package:trideta_v2/screens/auth/login_screen.dart';

class ParentProfileTab extends StatefulWidget {
  final String parentName;

  const ParentProfileTab({super.key, required this.parentName});

  @override
  State<ParentProfileTab> createState() => _ParentProfileTabState();
}

class _ParentProfileTabState extends State<ParentProfileTab> {
  final _supabase = Supabase.instance.client;

  late String _selectedTheme;

  @override
  void initState() {
    super.initState();
    // Sync the starting UI with whatever your main.dart is currently set to
    if (themeNotifier.value == ThemeMode.light) {
      _selectedTheme = 'Light';
    } else if (themeNotifier.value == ThemeMode.dark) {
      _selectedTheme = 'Dark';
    } else {
      _selectedTheme = 'System';
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.redAccent),
              SizedBox(width: 10),
              Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            "Are you sure you want to sign out of your account?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                "Sign Out",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // 🚨 FIX: Forcefully sign out, then manually rip them back to the Login Screen
      await _supabase.auth.signOut();

      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) =>
              false, // This destroys the back-button history for security
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);

    String email = _supabase.auth.currentUser?.email ?? "No email provided";

    return SafeArea(
      child: Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ─── PROFILE HEADER ───
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: primaryColor.withValues(alpha: 0.1),
                      child: Text(
                        widget.parentName.isNotEmpty
                            ? widget.parentName[0].toUpperCase()
                            : 'P',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.parentName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: subTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ─── APPEARANCE SETTINGS ───
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "App Settings",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: subTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.palette_outlined,
                                color: primaryColor,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Appearance",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildThemeSegmentedControl(primaryColor, isDark),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ─── LOGOUT BUTTON ───
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.1,
                        ),
                        foregroundColor: Colors.redAccent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        "Sign Out",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // THEME CONTROL WIDGETS
  // ===========================================================================

  Widget _buildThemeSegmentedControl(Color primaryColor, bool isDark) {
    Color trackColor = isDark ? Colors.black26 : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildThemePill(
            'Light',
            Icons.wb_sunny_rounded,
            primaryColor,
            isDark,
          ),
          _buildThemePill(
            'System',
            Icons.brightness_auto_rounded,
            primaryColor,
            isDark,
          ),
          _buildThemePill('Dark', Icons.nightlight_round, primaryColor, isDark),
        ],
      ),
    );
  }

  Widget _buildThemePill(
    String mode,
    IconData icon,
    Color primaryColor,
    bool isDark,
  ) {
    bool isSelected = _selectedTheme == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTheme = mode);

          if (mode == 'Light') {
            themeNotifier.value = ThemeMode.light;
          } else if (mode == 'Dark') {
            themeNotifier.value = ThemeMode.dark;
          } else {
            themeNotifier.value = ThemeMode.system;
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2C2C2C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.white54 : Colors.grey.shade500),
              ),
              const SizedBox(width: 6),
              Text(
                mode,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
