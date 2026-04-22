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
import 'package:trideta_v2/main.dart'; // 🚨 IMPORTED TO SYNC THE GLOBAL THEME

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

  void _showThemeSelectionPopup(SharedPreferences prefs) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    showDialog(
      context: context,
      barrierDismissible: true,
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
              Icons.brightness_auto,
              "System Default",
              ThemeMode.system,
              isDark,
              primaryColor,
            ),
            const Divider(),
            _buildThemeOption(
              ctx,
              Icons.light_mode,
              "Light Mode",
              ThemeMode.light,
              isDark,
              primaryColor,
            ),
            const Divider(),
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
    return ListTile(
      leading: Icon(icon, color: primary, size: 28),
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
      {'name': 'Trideta Blue', 'color': const Color(0xFF007ACC)},
      {'name': 'Emerald Green', 'color': const Color(0xFF10B981)},
      {'name': 'Royal Purple', 'color': const Color(0xFF8B5CF6)},
      {'name': 'Sunset Orange', 'color': const Color(0xFFF97316)},
      {'name': 'Crimson Red', 'color': const Color(0xFFEF4444)},
      {'name': 'Slate Grey', 'color': const Color(0xFF64748B)},
      {'name': 'Midnight Black', 'color': const Color(0xFF0F172A)},
      {'name': 'Teal', 'color': const Color(0xFF14B8A6)},
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
                // 1. UPDATE GLOBAL COLOR INSTANTLY
                appColorNotifier.value = c;

                // 2. BACKUP TO MEMORY
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('app_primary_color', c.value);

                // 3. PUSH HEX FORMAT TO DATABASE
                try {
                  String hexColor =
                      '#${c.value.toRadixString(16).substring(2, 8).toUpperCase()}';
                  final userId = Supabase.instance.client.auth.currentUser!.id;
                  final userData = await Supabase.instance.client
                      .from('profiles')
                      .select('school_id')
                      .eq('id', userId)
                      .single();

                  final schoolId = userData['school_id'];
                  if (schoolId != null) {
                    await Supabase.instance.client
                        .from('schools')
                        .update({'brand_color': hexColor})
                        .eq('id', schoolId);
                  }
                } catch (e) {
                  debugPrint("Failed to sync DB color: $e");
                }

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
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item['name'],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black54,
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

  Future<void> _handleLogout() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) showAuthErrorDialog(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    final user = Supabase.instance.client.auth.currentUser;
    String email = user?.email ?? 'admin@trideta.com';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Profile"),
        elevation: 0,
        backgroundColor: primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- PROFILE HEADER ---
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: primaryColor.withOpacity(0.1),
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 40,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "School Administrator",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(email, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Text(
                      "Active Subscription",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- APP CUSTOMIZATION SECTION ---
            const Text(
              "App Customization",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
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
              onTap: () => _showColorPicker(context, primaryColor),
            ),
            const SizedBox(height: 30),

            // --- ACCOUNT SETTINGS SECTION ---
            const Text(
              "School Management",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSettingsItem(
              title: "Update School Profile",
              subtitle: "Name, logo, address, and session",
              icon: Icons.domain,
              color: Colors.teal,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SchoolProfileScreen()),
              ),
            ),
            _buildSettingsItem(
              title: "System Configuration",
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
            const SizedBox(height: 30),

            // --- DATA MANAGEMENT SECTION ---
            const Text(
              "Data Management",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSettingsItem(
              title: "Export All Data (CSV)",
              subtitle: "Download school records and reports",
              icon: Icons.download_rounded,
              color: Colors.blueAccent,
              isDark: isDark,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Data export feature coming soon!"),
                  ),
                );
              },
            ),
            _buildSettingsItem(
              title: "Bulk Import Students",
              subtitle: "Upload CSV to add multiple students",
              icon: Icons.upload_file_rounded,
              color: Colors.deepPurple,
              isDark: isDark,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Bulk import coming soon!")),
                );
              },
            ),
            const SizedBox(height: 30),

            // --- NOTIFICATIONS & SECURITY ---
            const Text(
              "Preferences & Security",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSettingsItem(
              title: "Push Notifications",
              subtitle: "Manage alerts and updates",
              icon: Icons.notifications_active,
              color: Colors.pinkAccent,
              isDark: isDark,
              trailing: Switch(
                value: true,
                activeColor: primaryColor,
                onChanged: (val) {},
              ),
              onTap: () {},
            ),
            _buildSettingsItem(
              title: "Change Password",
              subtitle: "Update your account password",
              icon: Icons.lock_reset,
              color: Colors.brown,
              isDark: isDark,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Password reset sent to your email."),
                  ),
                );
              },
            ),
            _buildSettingsItem(
              title: "Two-Factor Authentication",
              subtitle: "Add an extra layer of security",
              icon: Icons.security,
              color: Colors.indigo,
              isDark: isDark,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("2FA Setup will be available soon."),
                  ),
                );
              },
            ),
            const SizedBox(height: 30),

            // --- SUPPORT & LEGAL SECTION ---
            const Text(
              "Support & Legal",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildSettingsItem(
              title: "Help Center & Tutorials",
              subtitle: "Learn how to use TriDeta",
              icon: Icons.help_outline,
              color: Colors.blueGrey,
              isDark: isDark,
              onTap: () async {
                final Uri url = Uri.parse('https://trideta.com/help');
                if (!await launchUrl(url)) {
                  debugPrint('Could not launch $url');
                }
              },
            ),
            _buildSettingsItem(
              title: "Contact Support",
              subtitle: "Email or chat with our team",
              icon: Icons.support_agent,
              color: Colors.blueGrey,
              isDark: isDark,
              onTap: () async {
                final Uri emailLaunchUri = Uri(
                  scheme: 'mailto',
                  path: 'support@trideta.com',
                  query: 'subject=TriDeta Admin Support Request',
                );
                launchUrl(emailLaunchUri);
              },
            ),
            _buildSettingsItem(
              title: "Terms of Service",
              icon: Icons.description_outlined,
              color: Colors.blueGrey,
              isDark: isDark,
              onTap: () async {
                final Uri url = Uri.parse('https://trideta.com/terms');
                launchUrl(url);
              },
            ),
            _buildSettingsItem(
              title: "Privacy Policy",
              icon: Icons.privacy_tip_outlined,
              color: Colors.blueGrey,
              isDark: isDark,
              onTap: () async {
                final Uri url = Uri.parse('https://trideta.com/privacy');
                launchUrl(url);
              },
            ),
            const SizedBox(height: 40),

            // --- LOGOUT BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                ),
                onPressed: () => _showLogoutDialog(context, isDark),
                icon: const Icon(Icons.logout),
                label: const Text(
                  "Log Out",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- APP VERSION ---
            Center(
              child: Text(
                "TriDeta School Management\nVersion 2.0.1 (Build 42)",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white30 : Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Log Out",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text("Are you sure you want to securely log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            child: const Text("Log Out", style: TextStyle(color: Colors.white)),
          ),
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
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              )
            : null,
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white30 : Colors.grey[400],
            ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The rest of the file continues with standard UI components and logic...

class AdminDashboard extends StatelessWidget {
  final Map<String, dynamic>? schoolData;

  const AdminDashboard({super.key, this.schoolData});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileMenuScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dashboard Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: "Total Students",
                    value: "1,240",
                    icon: Icons.people,
                    color: Colors.blue,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryCard(
                    title: "Total Teachers",
                    value: "84",
                    icon: Icons.person_pin_circle,
                    color: Colors.green,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: "Active Classes",
                    value: "32",
                    icon: Icons.class_,
                    color: Colors.orange,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryCard(
                    title: "Total Revenue",
                    value: "₦4.5M",
                    icon: Icons.account_balance_wallet,
                    color: Colors.purple,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Quick Actions Section
            Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionCard(
                  title: "Manage Students",
                  icon: Icons.group_add,
                  color: Colors.blueAccent,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Students
                  },
                ),
                _buildActionCard(
                  title: "Finance & Fees",
                  icon: Icons.payments,
                  color: Colors.green,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Finance
                  },
                ),
                _buildActionCard(
                  title: "Academics",
                  icon: Icons.menu_book,
                  color: Colors.orange,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Academics
                  },
                ),
                _buildActionCard(
                  title: "Staff Directory",
                  icon: Icons.badge,
                  color: Colors.purple,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Staff
                  },
                ),
                _buildActionCard(
                  title: "Send Messages",
                  icon: Icons.message,
                  color: Colors.teal,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Messaging
                  },
                ),
                _buildActionCard(
                  title: "Reports & Analytics",
                  icon: Icons.bar_chart,
                  color: Colors.redAccent,
                  isDark: isDark,
                  onTap: () {
                    // Navigate to Reports
                  },
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Recent Activity Section
            Text(
              "Recent Activity",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _buildActivityItem(
              title: "Fee Payment Received",
              subtitle: "John Doe (JSS 1) paid ₦50,000",
              time: "10 mins ago",
              icon: Icons.payment,
              iconColor: Colors.green,
              isDark: isDark,
            ),
            _buildActivityItem(
              title: "New Student Registered",
              subtitle: "Sarah Smith added to Primary 4",
              time: "1 hour ago",
              icon: Icons.person_add,
              iconColor: Colors.blue,
              isDark: isDark,
            ),
            _buildActivityItem(
              title: "Exam Results Published",
              subtitle: "First Term results for SSS 3 are live",
              time: "2 hours ago",
              icon: Icons.assessment,
              iconColor: Colors.orange,
              isDark: isDark,
            ),
            _buildActivityItem(
              title: "System Update",
              subtitle: "Platform updated to v2.0.1",
              time: "1 day ago",
              icon: Icons.system_update,
              iconColor: Colors.grey,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 28),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.trending_up, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required String title,
    required String subtitle,
    required String time,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white30 : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}
