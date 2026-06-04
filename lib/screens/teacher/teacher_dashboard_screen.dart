import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

// 🚨 NEW: Local Authentication for Security Gates
import 'package:local_auth/local_auth.dart';

import 'package:trideta_v2/main.dart';
import 'package:trideta_v2/widgets/teacher_dashboard_carousel.dart';
import 'package:trideta_v2/screens/teacher/teacher_alerts_screen.dart';
import 'package:trideta_v2/screens/teacher/teacher_student_roster_screen.dart';
import 'package:trideta_v2/screens/admin/result_computation_screen.dart';
import 'package:trideta_v2/screens/admin/affective_domain_screen.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';

// 🚨 NEW: Import the smart password module (Ensure this path is correct!)
import 'package:trideta_v2/screens/auth/widgets/smart_change_password_dialog.dart';

class TeacherDashboardScreen extends StatefulWidget {
  final String userRole;
  const TeacherDashboardScreen({super.key, required this.userRole});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen>
    with AuthErrorHandler {
  int _selectedIndex = 0;
  bool _isLoading = true;

  // --- TEACHER & SCHOOL DATA STATE ---
  String _teacherName = "Loading...";
  String? _teacherAvatar;
  String _schoolName = "Loading School...";
  String? _schoolLogoUrl;
  String _currentSession = "Loading...";
  String _currentTerm = "";
  Map<String, dynamic>? _latestAlert;
  int _unreadAlertsCount = 0;

  // Profile Picture Upload State
  Uint8List? _newAvatarBytes;
  String _newAvatarExtension = 'jpg';
  bool _isUploadingAvatar = false;
  late String _selectedTheme;

  // Local Auth Instance
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();

    if (themeNotifier.value == ThemeMode.light) {
      _selectedTheme = 'Light';
    } else if (themeNotifier.value == ThemeMode.dark) {
      _selectedTheme = 'Dark';
    } else {
      _selectedTheme = 'System';
    }
  }

  // 🚨 NEW: Safe Biometric/Lockscreen Authenticator
  Future<bool> _authenticateUser(String reason) async {
    try {
      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      // If the device has no lock screen or runs on the Web, safely let them through.
      if (!canAuthenticate) return true;

      // Note: some local_auth versions may not expose AuthenticationOptions.
      // Use the simpler API for broader compatibility.
      return await _localAuth.authenticate(localizedReason: reason);
    } catch (e) {
      debugPrint("Local auth error: $e");
      return true; // Failsafe to prevent permanent lockouts on weird devices
    }
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, school_id, passport_url')
          .eq('id', user.id)
          .single();

      final schoolId = profile['school_id'];

      if (mounted) {
        setState(() {
          _teacherName = profile['full_name'] ?? "Teacher";
          _teacherAvatar = profile['passport_url'];
        });
      }

      final school = await Supabase.instance.client
          .from('schools')
          .select()
          .eq('id', schoolId)
          .single();

      final allowedAlertTypes = ['school_website', 'general', 'teacher_alert'];

      try {
        final alertRes = await Supabase.instance.client
            .from('alerts')
            .select()
            .eq('school_id', schoolId)
            .filter('type', 'in', allowedAlertTypes)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (mounted) _latestAlert = alertRes;
      } catch (_) {}

      try {
        final allAlertsForBadge = await Supabase.instance.client
            .from('alerts')
            .select('id')
            .eq('school_id', schoolId)
            .filter('type', 'in', allowedAlertTypes);

        if (allAlertsForBadge.isNotEmpty) {
          final alertIds = (allAlertsForBadge as List)
              .map((a) => a['id'].toString())
              .toList();
          final readsData = await Supabase.instance.client
              .from('alert_reads')
              .select('alert_id')
              .eq('user_id', user.id)
              .filter('alert_id', 'in', alertIds);

          final readIds = (readsData as List)
              .map((r) => r['alert_id'].toString())
              .toSet();
          int unread = allAlertsForBadge.length - readIds.length;

          if (mounted) {
            setState(() => _unreadAlertsCount = unread > 0 ? unread : 0);
          }
        } else {
          if (mounted) setState(() => _unreadAlertsCount = 0);
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _schoolName = school['name'] ?? "My School";
          _schoolLogoUrl = school['logo_url'];

          if (_schoolLogoUrl != null) {
            _schoolLogoUrl =
                "$_schoolLogoUrl?t=${DateTime.now().millisecondsSinceEpoch}";
          }

          _currentSession = school['current_session'] ?? "Not Set";
          _currentTerm = school['current_term'] ?? "";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "We couldn't load your dashboard completely. Please check your internet connection and pull down to refresh.",
        );
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) _fetchDashboardData();
  }

  Future<void> _uploadAvatar() async {
    if (_newAvatarBytes == null) return;
    setState(() => _isUploadingAvatar = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final fileName =
          'staff_${user!.id}_${DateTime.now().millisecondsSinceEpoch}.$_newAvatarExtension';

      await Supabase.instance.client.storage
          .from('staff_passports')
          .uploadBinary(fileName, _newAvatarBytes!);
      final newUrl = Supabase.instance.client.storage
          .from('staff_passports')
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('profiles')
          .update({'passport_url': newUrl})
          .eq('id', user.id);

      setState(() {
        _teacherAvatar = newUrl;
        _newAvatarBytes = null;
        _isUploadingAvatar = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile picture updated!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      _buildHomeContent(isDark, primaryColor),
      const TeacherAlertsScreen(),
      _buildProfileTab(isDark, primaryColor),
    ];

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                Container(
                  width: 250,
                  color: navBarColor,
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Icon(Icons.school, size: 50, color: primaryColor),
                      const SizedBox(height: 20),
                      const Text(
                        "TRIDETA",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _buildDesktopNavItem(
                        Icons.dashboard_rounded,
                        "Dashboard",
                        0,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.notifications_active_rounded,
                        "Alerts",
                        1,
                        primaryColor,
                        badgeCount: _unreadAlertsCount,
                      ),
                      _buildDesktopNavItem(
                        Icons.person,
                        "Profile",
                        2,
                        primaryColor,
                      ),
                    ],
                  ),
                ),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            backgroundColor: navBarColor,
            indicatorColor: primaryColor.withValues(alpha: 0.1),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(
                  Icons.dashboard_rounded,
                  color: primaryColor,
                ),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _unreadAlertsCount > 0,
                  label: Text(_unreadAlertsCount.toString()),
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.notifications_none_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: _unreadAlertsCount > 0,
                  label: Text(_unreadAlertsCount.toString()),
                  backgroundColor: Colors.redAccent,
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: primaryColor,
                  ),
                ),
                label: 'Alerts',
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: primaryColor),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopNavItem(
    IconData icon,
    String title,
    int index,
    Color primaryColor, {
    int badgeCount = 0,
  }) {
    bool isSelected = _selectedIndex == index;
    return ListTile(
      leading: Badge(
        isLabelVisible: badgeCount > 0,
        label: Text(badgeCount.toString()),
        backgroundColor: Colors.redAccent,
        child: Icon(icon, color: isSelected ? primaryColor : Colors.grey),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? primaryColor : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: primaryColor.withValues(alpha: 0.1),
      onTap: () => setState(() => _selectedIndex = index),
    );
  }

  // ===========================================================================
  // HOME TAB
  // ===========================================================================
  Widget _buildHomeContent(bool isDark, Color primaryColor) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTeacherHeader(textColor, subTextColor, primaryColor),
              const SizedBox(height: 30),

              _buildGlassySessionCard(primaryColor),
              const SizedBox(height: 35),

              TeacherDashboardCarousel(
                latestAlert: _latestAlert,
                primaryColor: primaryColor,
                isDark: isDark,
              ),
              const SizedBox(height: 30),

              Text(
                "CLASSROOM MANAGEMENT",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.people_alt_rounded,
                color: Colors.orange,
                title: "My Students & Attendance",
                subtitle: "Access rosters and mark daily attendance",
                onTap: () async {
                  // 🚨 AUTHENTICATE BEFORE ACCESS
                  bool authorized = await _authenticateUser(
                    'Authenticate to view student roster and attendance.',
                  );
                  if (authorized && context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TeacherStudentRosterScreen(),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 30),
              Text(
                "ACADEMIC TASKS",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.edit_document,
                color: primaryColor,
                title: "Enter Subject Scores",
                subtitle: "Input CA and Exam marks securely",
                onTap: () async {
                  // 🚨 AUTHENTICATE BEFORE ACCESS
                  bool authorized = await _authenticateUser(
                    'Authenticate to modify student examination scores.',
                  );
                  if (authorized && context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ResultComputationScreen(),
                      ),
                    );
                  }
                },
              ),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.psychology_alt_rounded,
                color: Colors.purple,
                title: "Affective Domain & Remarks",
                subtitle: "Rate behavior and add Form Master comments",
                onTap: () async {
                  // 🚨 AUTHENTICATE BEFORE ACCESS
                  bool authorized = await _authenticateUser(
                    'Authenticate to enter affective domains and remarks.',
                  );
                  if (authorized && context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AffectiveDomainScreen(),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherHeader(
    Color textColor,
    Color subTextColor,
    Color primaryColor,
  ) {
    return Row(
      children: [
        Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.2),
              width: 2,
            ),
            image: _schoolLogoUrl != null
                ? DecorationImage(
                    image: NetworkImage(_schoolLogoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: _schoolLogoUrl == null
              ? Icon(Icons.school_rounded, color: primaryColor, size: 24)
              : null,
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _schoolName,
                style: TextStyle(
                  fontSize: 13,
                  color: subTextColor,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                "Hello, ${_teacherName.split(' ').first}",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlassySessionCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.85), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "CURRENT TIMELINE",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  _currentSession,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    _currentTerm,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleTile({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
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
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PROFILE TAB
  // ===========================================================================
  Widget _buildProfileTab(bool isDark, Color primaryColor) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);
    String email =
        Supabase.instance.client.auth.currentUser?.email ?? "No email provided";

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
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
                        backgroundImage: _newAvatarBytes != null
                            ? MemoryImage(_newAvatarBytes!) as ImageProvider
                            : (_teacherAvatar != null
                                  ? NetworkImage(_teacherAvatar!)
                                  : null),
                        child:
                            (_teacherAvatar == null && _newAvatarBytes == null)
                            ? Text(
                                _teacherName.isNotEmpty
                                    ? _teacherName[0].toUpperCase()
                                    : 'T',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () async {
                          final image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 50,
                          );
                          if (image != null) {
                            final bytes = await image.readAsBytes();
                            setState(() {
                              _newAvatarBytes = bytes;
                              _newAvatarExtension = image.name.split('.').last;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF121212)
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_newAvatarBytes != null) ...[
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                    icon: _isUploadingAvatar
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: TridetaLoader(color: Colors.white),
                          )
                        : const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 18,
                          ),
                    label: Text(
                      _isUploadingAvatar ? "Saving..." : "Save Picture",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Text(
                  _teacherName,
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
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.palette_outlined,
                                  color: primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "Appearance",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
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
                      Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        indent: 20,
                        endIndent: 20,
                      ),

                      // 🚨 AUTHENTICATE BEFORE OPENING PASSWORD DIALOG
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          "Change Password",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: textColor,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                        onTap: () async {
                          bool authorized = await _authenticateUser(
                            'Authenticate to change your password.',
                          );
                          if (authorized && context.mounted) {
                            showDialog(
                              context: context,
                              builder: (_) => const SmartChangePasswordDialog(),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
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
                    onPressed: () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: const Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Sign Out",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          content: const Text(
                            "Are you sure you want to sign out of your account?",
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
                        ),
                      );
                      if (confirm == true) {
                        await Supabase.instance.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      }
                    },
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
    );
  }

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
