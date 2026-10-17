import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/screens/shared/about_trideta_screen.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trideta_v2/screens/admin/school_data_export_screen.dart';
import 'package:trideta_v2/widgets/color_picker_sheet.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

import 'package:trideta_v2/screens/auth/login_screen.dart';
import 'package:trideta_v2/screens/admin/school_profile_screen.dart';
import 'package:trideta_v2/screens/admin/school_configuration_screen.dart';
import 'package:trideta_v2/screens/admin/end_of_year_processing_screen.dart';
import 'package:trideta_v2/screens/admin/end_of_term_proceedings_screen.dart';
import 'package:trideta_v2/services/biometric_service.dart';
import 'package:trideta_v2/main.dart';

class ProfileMenuScreen extends StatefulWidget {
  const ProfileMenuScreen({super.key});

  @override
  State<ProfileMenuScreen> createState() => _ProfileMenuScreenState();
}

class _ProfileMenuScreenState extends State<ProfileMenuScreen>
    with AuthErrorHandler {
  final Set<String> _downloadedTables = {};
  final int _totalRequiredTables = 14;

  // 🚨 NEW: Dynamic Subscription Tracker
  String _subscriptionStatus = "Checking...";
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadSavedColor();
    _fetchSubscriptionStatus(); // 🚨 Fetch from DB on load
  }

  // 🚨 NEW: Fetch dynamic subscription status
  Future<void> _fetchSubscriptionStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();

      final school = await supabase
          .from('schools')
          .select('subscription_status')
          .eq('id', profile['school_id'])
          .single();

      if (mounted) {
        setState(() {
          _subscriptionStatus =
              school['subscription_status'] ?? 'Unknown Status';
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subscriptionStatus = "Error fetching status";
          _isLoadingStatus = false;
        });
      }
    }
  }

  // --- LOAD SAVED BRAND COLOR ---
  Future<void> _loadSavedColor() async {
    final prefs = await SharedPreferences.getInstance();
    int? colorValue = prefs.getInt('app_primary_color');
    if (colorValue != null) {
      appColorNotifier.value = Color(colorValue);
    }
  }

  void _showThemeSelectionPopup(SharedPreferences prefs) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: PUi.surface(isDark),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          "Choose Appearance",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: PUi.ink(isDark),
          ),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildThemeOption(
                ctx,
                Icons.brightness_auto,
                "System Default",
                ThemeMode.system,
                isDark,
                primaryColor,
              ),
              const SizedBox(height: 10),
              _buildThemeOption(
                ctx,
                Icons.light_mode,
                "Light Mode",
                ThemeMode.light,
                isDark,
                primaryColor,
              ),
              const SizedBox(height: 10),
              _buildThemeOption(
                ctx,
                Icons.dark_mode,
                "Dark Mode",
                ThemeMode.dark,
                isDark,
                primaryColor,
              ),
            ],
          ),
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
    Color primary,
  ) {
    return Material(
      color: PUi.surfaceAlt(isDark),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () async {
          themeNotifier.value = mode;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('has_chosen_theme', true);
          await prefs.setString('saved_theme', mode.toString().split('.').last);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: primary, size: 24),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  color: PUi.ink(isDark),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContactSupportOptions(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        decoration: BoxDecoration(
          color: PUi.surface(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: PUi.border(isDark)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: PUi.border(isDark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text("Contact Support", style: PUi.title(isDark, size: 24)),
              const SizedBox(height: 8),
              Text(
                "Choose how you would like to reach out to our team.",
                style: TextStyle(color: PUi.muted(isDark), fontSize: 13.5),
              ),
              const SizedBox(height: 22),
              PCard(
                radius: 22,
                shadow: false,
                color: PUi.surfaceAlt(isDark),
                borderColor: Colors.transparent,
                padding: const EdgeInsets.all(14),
                onTap: () {
                  launchUrl(
                    Uri(
                      scheme: 'mailto',
                      path: 'trideta.app@gmail.com',
                      query: 'subject=TriDeta Admin Support Request',
                    ),
                  );
                  Navigator.pop(ctx);
                },
                child: Row(
                  children: [
                    const PIconBadge(
                      icon: Icons.email,
                      color: Colors.blue,
                      size: 46,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Email Us",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: PUi.ink(isDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "trideta.app@gmail.com",
                            style: TextStyle(
                              fontSize: 13,
                              color: PUi.muted(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PCard(
                radius: 22,
                shadow: false,
                color: PUi.surfaceAlt(isDark),
                borderColor: Colors.transparent,
                padding: const EdgeInsets.all(14),
                onTap: () {
                  launchUrl(Uri.parse("https://wa.me/2347040686186"));
                  Navigator.pop(ctx);
                },
                child: Row(
                  children: [
                    const PIconBadge(
                      icon: Icons.chat,
                      color: Colors.green,
                      size: 46,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "WhatsApp Us",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: PUi.ink(isDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "07040686186",
                            style: TextStyle(
                              fontSize: 13,
                              color: PUi.muted(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _handleDeleteSchool(BuildContext context) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (_downloadedTables.length < _totalRequiredTables) {
      showAuthErrorDialog(
        "Action Prohibited.\n\nYou must first use the 'Export All Data (CSV)' module in Data & Security to backup all $_totalRequiredTables tables before the system will allow account deletion.",
      );
      return;
    }

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
              "This action is PERMANENT and CANNOT be undone.\n\nBecause you have exported your data, we will now proceed to permanently erase all student records, transactions, and school configurations.",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "I UNDERSTAND, DELETE",
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

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            const Center(child: TridetaLoader(color: Colors.redAccent)),
      );
    }

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final userData = await supabase
          .from('profiles')
          .select('school_id')
          .eq('id', userId)
          .single();

      final schoolId = userData['school_id'];

      if (schoolId == null) {
        throw "Could not identify your school ID.";
      }

      final List<String> safeDeletionOrder = [
        'alert_reads',
        'alerts',
        'affective_traits',
        'exam_scores',
        'term_results',
        'attendance',
        'transactions',
        'staff_assignments',
        'class_subjects',
        'fee_structures',
        'students',
        'classes',
        'profiles',
      ];
      for (String tName in safeDeletionOrder) {
        try {
          await supabase.from(tName).delete().eq('school_id', schoolId);
        } catch (_) {}
      }

      await supabase.from('schools').delete().eq('id', schoolId);
      await supabase.auth.signOut();

      if (context.mounted) {
        Navigator.pop(context);
        showSuccessDialog(
          "School Deleted",
          "Your school and all associated data have been permanently removed from TriDeta.",
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showAuthErrorDialog(
          "Failed to delete school. Please contact support. Error: $e",
        );
      }
    }
  }

  // 🚨 NEW: Dynamic color logic for subscription badge
  Color _getSubscriptionColor(String status) {
    status = status.toLowerCase();
    if (status.contains('active') || status.contains('trial')) {
      return Colors.green;
    } else if (status.contains('terminated') ||
        status.contains('suspended') ||
        status.contains('paused')) {
      return Colors.redAccent;
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    final user = Supabase.instance.client.auth.currentUser;
    String email = user?.email ?? 'admin@trideta.com';

    Color subColor = _getSubscriptionColor(_subscriptionStatus);

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // --- PROFILE HEADER ---
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: PUi.tint(primaryColor, isDark, 0.12),
                        child: Icon(
                          Icons.admin_panel_settings,
                          size: 44,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "School Administrator",
                      style: PUi.title(isDark, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Container(
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
                    const SizedBox(height: 12),

                    // 🚨 DYNAMIC SUBSCRIPTION BADGE
                    if (_isLoadingStatus)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      PPill(
                        text: _subscriptionStatus.toUpperCase(),
                        color: subColor,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // --- APP CUSTOMIZATION SECTION ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("APP CUSTOMIZATION", style: PUi.sectionLabel(isDark)),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                title: "App Theme",
                subtitle: "Light, Dark, or System Default",
                icon: Icons.brightness_6,
                color: primaryColor,
                isDark: isDark,
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  _showThemeSelectionPopup(prefs);
                },
              ),
              _buildSettingsItem(
                title: "School Brand Color",
                subtitle: "Change the primary color of the app",
                icon: Icons.color_lens,
                color: primaryColor,
                isDark: isDark,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (ctx) =>
                        ColorPickerSheet(currentColor: primaryColor),
                  );
                },
              ),
              const SizedBox(height: 30),

              // --- ACCOUNT SETTINGS SECTION ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("SCHOOL MANAGEMENT", style: PUi.sectionLabel(isDark)),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                title: "Update School Profile",
                subtitle: "Name, logo, address, and session",
                icon: Icons.domain,
                color: Colors.teal,
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SchoolProfileScreen(),
                  ),
                ),
              ),
              _buildSettingsItem(
                title: "School Configuration",
                subtitle: "Manage terms, active classes, and subjects",
                icon: Icons.settings_applications,
                color: Colors.orange,
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SchoolConfigurationScreen(),
                  ),
                ),
              ),
              _buildSettingsItem(
                title: "End of Term Proceedings",
                subtitle: "Process term closures & freeze data",
                icon: Icons.update_rounded,
                color: const Color(0xFF96B703),
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EndOfTermProceedingsScreen(),
                  ),
                ),
              ),
              _buildSettingsItem(
                title: "End of Year Proceedings",
                subtitle: "Promote students & graduate seniors",
                icon: Icons.warning_amber_rounded,
                color: Colors.redAccent,
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EndOfYearProcessingScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // --- DATA & SECURITY SECTION ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("DATA & SECURITY", style: PUi.sectionLabel(isDark)),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                title: "Export All Data (CSV)",
                subtitle: "Download school records and reports",
                icon: Icons.download_rounded,
                color: Colors.blueAccent,
                isDark: isDark,
                onTap: () async {
                  final supabase = Supabase.instance.client;
                  final user = supabase.auth.currentUser;
                  if (user != null) {
                    final profile = await supabase
                        .from('profiles')
                        .select('school_id')
                        .eq('id', user.id)
                        .single();
                    if (context.mounted) {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SchoolDataExportScreen(
                            schoolId: profile['school_id'],
                            alreadyDownloaded: _downloadedTables,
                          ),
                        ),
                      );
                      if (result != null && result is Set<String>) {
                        setState(() {
                          _downloadedTables.addAll(result);
                        });
                      }
                    }
                  }
                },
              ),
              _buildSettingsItem(
                title: "Security Settings",
                subtitle: "Password & Biometrics",
                icon: Icons.security,
                color: Colors.brown,
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SecuritySettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // --- SUPPORT & LEGAL SECTION ---
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text("SUPPORT & LEGAL", style: PUi.sectionLabel(isDark)),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                title: "Help Center & Tutorials",
                subtitle: "Learn how to use TriDeta",
                icon: Icons.help_outline,
                color: Colors.blueGrey,
                isDark: isDark,
                onTap: () async {
                  final Uri url = Uri.parse(
                    'https://www.youtube.com/@SkynexOfficial',
                  );
                  if (!await launchUrl(url)) {
                    debugPrint('Could not launch $url');
                  }
                },
              ),
              _buildSettingsItem(
                title: "Contact Support",
                subtitle: "Email or WhatsApp our team",
                icon: Icons.support_agent,
                color: Colors.blueGrey,
                isDark: isDark,
                onTap: () =>
                    _showContactSupportOptions(context, isDark, primaryColor),
              ),
              _buildSettingsItem(
                title: "Terms of Service",
                icon: Icons.description_outlined,
                color: Colors.blueGrey,
                isDark: isDark,
                onTap: () async {
                  final Uri url = Uri.parse(
                    'https://skynex.com.ng/trideta-terms',
                  );
                  launchUrl(url);
                },
              ),
              _buildSettingsItem(
                title: "Privacy Policy",
                icon: Icons.privacy_tip_outlined,
                color: Colors.blueGrey,
                isDark: isDark,
                onTap: () async {
                  final Uri url = Uri.parse(
                    'https://skynex.com.ng/trideta-privacy-policy',
                  );
                  launchUrl(url);
                },
              ),
              _buildSettingsItem(
                title: "About Trideta",
                subtitle: "Version, features and Skynex",
                icon: Icons.info_outline_rounded,
                color: Colors.teal,
                isDark: isDark,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutTridetaScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),

              // --- LOGOUT BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  onPressed: () async {
                    bool confirmLogout =
                        await showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: PUi.surface(isDark),
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            title: const Text(
                              "Confirm Logout",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            content: const Text(
                              "Are you sure you want to log out of your account?",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text(
                                  "Cancel",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  "Log Out",
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

                    if (!confirmLogout) return;

                    if (context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => const Center(child: TridetaLoader()),
                      );
                    }

                    await Supabase.instance.client.auth.signOut();

                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    "LOG OUT",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
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
      ),
    );
  }

  // 🚨 UI FIX: Replaced heavy shadow/border container with a sleek, flat ListTile and Divider
  Widget _buildSettingsItem({
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PCard(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            PIconBadge(icon: icon, color: color, size: 46, iconSize: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: -0.1,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.chevron_right_rounded, size: 24, color: PUi.muted(isDark)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ORIGINAL SECURITY SETTINGS SCREEN RESTORED
// -----------------------------------------------------------------------------
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen>
    with AuthErrorHandler {
  final BiometricService _biometricService = BiometricService();
  bool _isBiometricEnabled = false;
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadSecurityPreferences();
  }

  Future<void> _loadSecurityPreferences() async {
    bool canCheck = await _biometricService.isBiometricAvailable();
    bool isEnabled = await _biometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _canCheckBiometrics = canCheck;
        _isBiometricEnabled = isEnabled;
      });
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (!value) {
      await _biometricService.deleteCredentials();
      await _biometricService.setBiometricEnabled(false);
      setState(() => _isBiometricEnabled = false);
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      bool passedChallenge = await _biometricService.authenticate();
      if (passedChallenge) {
        if (mounted) _showBiometricPasswordPrompt(user.email!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Authentication failed. Cannot enable biometric login.",
              ),
            ),
          );
        }
      }
    }
  }

  void _showBiometricPasswordPrompt(String email) {
    final passCtrl = TextEditingController();
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Verify Password",
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "To enable quick biometric login, please enter your password one time to securely encrypt it on this device.",
            ),
            const SizedBox(height: 15),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Current Password",
                filled: true,
                fillColor: isDark ? Colors.black26 : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () async {
              if (passCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              await _biometricService.saveCredentials(
                email,
                passCtrl.text.trim(),
              );
              await _biometricService.setBiometricEnabled(true);
              setState(() => _isBiometricEnabled = true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Biometric login successfully enabled!"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text(
              "Save & Enable",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showPasswordModal(Color currentPrimary) {
    final passCtrl = TextEditingController();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Change Admin Password",
          style: TextStyle(fontWeight: FontWeight.bold, color: currentPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Please enter your new password below. You will be signed out of other devices.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "New Password",
                filled: true,
                fillColor: isDark ? Colors.black12 : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: currentPrimary),
            onPressed: () async {
              if (passCtrl.text.trim().length < 6) {
                showAuthErrorDialog(
                  "Password must be at least 6 characters long.",
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(password: passCtrl.text.trim()),
                );

                await _biometricService.deleteCredentials();
                await _biometricService.setBiometricEnabled(false);
                _loadSecurityPreferences();

                if (mounted) {
                  showSuccessDialog(
                    "Password Updated",
                    "Password updated securely. If you use Biometrics, please re-enable them.",
                  );
                }
              } catch (e) {
                if (mounted) showAuthErrorDialog(e.toString());
              }
            },
            child: const Text(
              "Update Password",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color dynamicPrimaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: PUi.bg(isDark),
      body: PBackdrop(
        accent: dynamicPrimaryColor,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: PUi.surface(isDark),
                            side: BorderSide(color: PUi.border(isDark)),
                            minimumSize: const Size(44, 44),
                          ),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: PUi.ink(isDark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Security Settings",
                          style: PUi.title(isDark, size: 24),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildSecurityContent(
                          isDark,
                          dynamicPrimaryColor,
                          constraints.maxWidth,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityContent(
    bool isDark,
    Color dynamicPrimaryColor,
    double screenWidth,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text("AUTHENTICATION", style: PUi.sectionLabel(isDark)),
          ),
          const SizedBox(height: 12),
          _buildSettingsItem(
            title: "Change Password",
            subtitle: "Update your account password",
            icon: Icons.lock_reset,
            color: dynamicPrimaryColor,
            isDark: isDark,
            onTap: () => _showPasswordModal(dynamicPrimaryColor),
          ),
          if (_canCheckBiometrics) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text("DEVICE SECURITY", style: PUi.sectionLabel(isDark)),
            ),
            const SizedBox(height: 12),
            PCard(
              radius: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                title: Text(
                  "Biometric Login",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: PUi.ink(isDark),
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    "Use fingerprint or face to login quickly",
                    style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                  ),
                ),
                secondary: const PIconBadge(
                  icon: Icons.fingerprint,
                  color: Colors.green,
                  size: 46,
                  iconSize: 22,
                ),
                activeThumbColor: dynamicPrimaryColor,
                value: _isBiometricEnabled,
                onChanged: _toggleBiometrics,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PCard(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            PIconBadge(icon: icon, color: color, size: 46, iconSize: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: -0.1,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.chevron_right_rounded, size: 24, color: PUi.muted(isDark)),
          ],
        ),
      ),
    );
  }
}
