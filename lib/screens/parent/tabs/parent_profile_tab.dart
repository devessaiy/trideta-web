import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 IMPORT YOUR MAIN.DART SO WE CAN TALK TO YOUR THEME NOTIFIER!
import 'package:trideta_v2/main.dart';
// 🚨 IMPORT YOUR LOGIN SCREEN SO WE CAN NAVIGATE THERE!
import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/screens/shared/about_trideta_screen.dart';
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';

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
          backgroundColor: PUi.surface(isDark),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Row(
            children: [
              const PIconBadge(
                icon: Icons.logout_rounded,
                color: Colors.redAccent,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Text(
                "Sign Out",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: PUi.ink(isDark),
                ),
              ),
            ],
          ),
          content: Text(
            "Are you sure you want to sign out of your account?",
            style: TextStyle(color: PUi.muted(isDark)),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: PUi.muted(isDark),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                "Sign Out",
                style: TextStyle(fontWeight: FontWeight.w700),
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

    String email = _supabase.auth.currentUser?.email ?? "No email provided";

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── PROFILE HEADER ───
                    Center(
                      child: PAvatar(
                        initial: widget.parentName.isNotEmpty
                            ? widget.parentName[0].toUpperCase()
                            : 'P',
                        imageUrl: '',
                        radius: 50,
                        ringColor: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.parentName,
                      style: PUi.title(isDark, size: 28),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: PUi.surface(isDark),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: PUi.border(isDark)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mail_outline_rounded,
                              size: 16,
                              color: PUi.muted(isDark),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: PUi.muted(isDark),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ─── APPEARANCE SETTINGS ───
                    Text("APP SETTINGS", style: PUi.sectionLabel(isDark)),
                    const SizedBox(height: 12),

                    PCard(
                      radius: 28,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              PIconBadge(
                                icon: Icons.palette_outlined,
                                color: primaryColor,
                                size: 40,
                                iconSize: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Appearance",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: PUi.ink(isDark),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _buildThemeSegmentedControl(primaryColor, isDark),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    PCard(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutTridetaScreen(),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          PIconBadge(
                            icon: Icons.info_outline_rounded,
                            color: primaryColor,
                            size: 40,
                            iconSize: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "About Trideta",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: PUi.ink(isDark),
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: PUi.muted(isDark),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ─── LOGOUT BUTTON ───
                    OutlinedButton.icon(
                      style: PUi.outlinedPill(Colors.redAccent, height: 56),
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text("Sign Out"),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
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
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: PUi.surfaceAlt(isDark),
        borderRadius: BorderRadius.circular(40),
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
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : PUi.muted(isDark),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : PUi.muted(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
