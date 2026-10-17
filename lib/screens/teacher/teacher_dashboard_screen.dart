import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

// 🚨 NEW: Local Authentication for Security Gates
import 'package:trideta_v2/utils/lock_gate.dart';
import 'package:trideta_v2/screens/shared/about_trideta_screen.dart';
import 'package:trideta_v2/services/offline_queue.dart';
import 'package:trideta_v2/screens/teacher/teacher_documents_screen.dart';
import 'package:trideta_v2/widgets/sync_status_banner.dart';

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

  @override
  void initState() {
    super.initState();
    OfflineQueue.instance.start();
    _fetchDashboardData();

    if (themeNotifier.value == ThemeMode.light) {
      _selectedTheme = 'Light';
    } else if (themeNotifier.value == ThemeMode.dark) {
      _selectedTheme = 'Dark';
    } else {
      _selectedTheme = 'System';
    }
  }

  // Lock-screen gate: true only if the user really unlocked their phone.
  Future<bool> _authenticateUser(String reason) =>
      requireDeviceLock(context, reason);

  Future<void> _fetchDashboardData() async {
    final client = Supabase.instance.client;
    final cacheKey = 'dash:teacher:${client.auth.currentUser?.id}';

    // Show the last saved copy at once, then refresh from the server below.
    bool shownFromCache = false;
    final cached = await LocalCache.get(cacheKey);
    if (cached is Map && mounted) {
      setState(() {
        _teacherName = (cached['teacherName'] ?? "Teacher").toString();
        _teacherAvatar = cached['teacherAvatar']?.toString();
        _schoolName = (cached['schoolName'] ?? "My School").toString();
        _schoolLogoUrl = cached['schoolLogoUrl']?.toString();
        _currentSession = (cached['currentSession'] ?? "Not Set").toString();
        _currentTerm = (cached['currentTerm'] ?? "").toString();
        _unreadAlertsCount = (cached['unread'] as num?)?.toInt() ?? 0;
        final la = cached['latestAlert'];
        _latestAlert = la is Map ? Map<String, dynamic>.from(la) : null;
        _isLoading = false;
      });
      shownFromCache = true;
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final profile = await retryRead(
        () async => await client
            .from('profiles')
            .select('full_name, school_id, passport_url')
            .eq('id', user.id)
            .single(),
      );

      final schoolId = profile['school_id'];

      if (mounted) {
        setState(() {
          _teacherName = profile['full_name'] ?? "Teacher";
          _teacherAvatar = profile['passport_url'];
        });
      }

      final allowedAlertTypes = ['school_website', 'general', 'teacher_alert'];

      // Load the school, the latest alert and the unread count at the same
      // time instead of one after another.
      final schoolFuture = retryRead(
        () async => await client
            .from('schools')
            .select('name, logo_url, current_session, current_term')
            .eq('id', schoolId)
            .single(),
      );

      bool latestLoaded = false;
      Map<String, dynamic>? latestAlert;
      final latestFuture = () async {
        try {
          latestAlert = await retryRead(
            () async => await client
                .from('alerts')
                .select()
                .eq('school_id', schoolId)
                .filter('type', 'in', allowedAlertTypes)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle(),
          );
          latestLoaded = true;
        } catch (_) {}
      }();

      int? unread;
      final unreadFuture = () async {
        try {
          final allAlertsForBadge = await retryRead(
            () async => await client
                .from('alerts')
                .select('id')
                .eq('school_id', schoolId)
                .filter('type', 'in', allowedAlertTypes),
          );

          if (allAlertsForBadge.isNotEmpty) {
            final alertIds = (allAlertsForBadge as List)
                .map((a) => a['id'].toString())
                .toList();
            final readsData = await retryRead(
              () async => await client
                  .from('alert_reads')
                  .select('alert_id')
                  .eq('user_id', user.id)
                  .filter('alert_id', 'in', alertIds),
            );

            final readIds = (readsData as List)
                .map((r) => r['alert_id'].toString())
                .toSet();
            final count = allAlertsForBadge.length - readIds.length;
            unread = count > 0 ? count : 0;
          } else {
            unread = 0;
          }
        } catch (_) {}
      }();

      final school = await schoolFuture;
      await latestFuture;
      await unreadFuture;

      if (mounted) {
        setState(() {
          if (latestLoaded) _latestAlert = latestAlert;
          final unreadNow = unread;
          if (unreadNow != null) _unreadAlertsCount = unreadNow;

          _schoolName = school['name'] ?? "My School";
          // The logo address changes whenever a new logo is uploaded, so it
          // can be cached safely (no need to re-download on every refresh).
          _schoolLogoUrl = school['logo_url'];

          _currentSession = school['current_session'] ?? "Not Set";
          _currentTerm = school['current_term'] ?? "";
          _isLoading = false;
        });

        // Keep a saved copy for the next start (works with no internet).
        await LocalCache.put(cacheKey, {
          'teacherName': _teacherName,
          'teacherAvatar': _teacherAvatar,
          'schoolName': _schoolName,
          'schoolLogoUrl': _schoolLogoUrl,
          'currentSession': _currentSession,
          'currentTerm': _currentTerm,
          'unread': _unreadAlertsCount,
          'latestAlert': _latestAlert,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (!shownFromCache) {
          showAuthErrorDialog(
            "We couldn't load your dashboard completely. Please check your internet connection and pull down to refresh.",
          );
        }
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

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. Data loading, caching, avatar upload,
  // lock-screen gates and sign-out logic are unchanged.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = PUi.bg(isDark);
    Color navBarColor = PUi.surface(isDark);
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
          // Full sidebar on large desktops, slim icon rail on smaller ones.
          final bool expanded = constraints.maxWidth >= 1100;
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                _buildDesktopSidebar(
                  expanded,
                  isDark,
                  primaryColor,
                  navBarColor,
                ),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: PUi.border(isDark))),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 68,
                elevation: 0,
                backgroundColor: navBarColor,
                surfaceTintColor: Colors.transparent,
                indicatorColor: primaryColor.withValues(alpha: 0.14),
                indicatorShape: const StadiumBorder(),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primaryColor : PUi.muted(isDark),
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                destinations: [
                  NavigationDestination(
                    icon: Icon(
                      Icons.dashboard_outlined,
                      color: PUi.muted(isDark),
                    ),
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
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: PUi.muted(isDark),
                      ),
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
                    icon: Icon(
                      Icons.person_outline,
                      color: PUi.muted(isDark),
                    ),
                    selectedIcon: Icon(Icons.person, color: primaryColor),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🖥️ DESKTOP SIDEBAR
  // ---------------------------------------------------------------------------
  Widget _buildDesktopSidebar(
    bool expanded,
    bool isDark,
    Color primaryColor,
    Color navBarColor,
  ) {
    final String initial = _teacherName.isNotEmpty
        ? _teacherName[0].toUpperCase()
        : 'T';

    Widget avatar(double radius) => CircleAvatar(
      radius: radius,
      backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
      backgroundImage: _teacherAvatar != null
          ? NetworkImage(_teacherAvatar!)
          : null,
      child: _teacherAvatar == null
          ? Text(
              initial,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );

    return Container(
      width: expanded ? 264 : 92,
      decoration: BoxDecoration(
        color: navBarColor,
        border: Border(right: BorderSide(color: PUi.border(isDark))),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            expanded ? 20 : 14,
            28,
            expanded ? 20 : 14,
            20,
          ),
          child: Column(
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PUi.tint(primaryColor, isDark, 0.12),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Text(
                      "TRIDETA",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        letterSpacing: 2,
                        color: PUi.ink(isDark),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 36),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildDesktopNavItem(
                        Icons.dashboard_rounded,
                        "Dashboard",
                        0,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.notifications_active_rounded,
                        "Alerts",
                        1,
                        primaryColor,
                        isDark,
                        expanded,
                        badgeCount: _unreadAlertsCount,
                      ),
                      _buildDesktopNavItem(
                        Icons.person,
                        "Profile",
                        2,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PUi.surfaceAlt(isDark),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      avatar(19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _teacherName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: PUi.ink(isDark),
                              ),
                            ),
                            Text(
                              _schoolName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: PUi.muted(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                avatar(21),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavItem(
    IconData icon,
    String title,
    int index,
    Color primaryColor,
    bool isDark,
    bool expanded, {
    int badgeCount = 0,
  }) {
    final bool isSelected = _selectedIndex == index;
    final Color fg = isSelected ? Colors.white : PUi.muted(isDark);

    final Widget iconWidget = Badge(
      isLabelVisible: badgeCount > 0,
      label: Text(badgeCount.toString()),
      backgroundColor: Colors.redAccent,
      child: Icon(icon, color: fg, size: expanded ? 22 : 24),
    );

    void select() => setState(() => _selectedIndex = index);

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tooltip(
          message: title,
          child: Material(
            color: isSelected ? primaryColor : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: select,
              child: SizedBox(width: 54, height: 54, child: Center(child: iconWidget)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? primaryColor : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HOME TAB
  // ===========================================================================
  Widget _buildHomeContent(bool isDark, Color primaryColor) {
    return Container(
      color: PUi.bg(isDark),
      child: PBackdrop(
        accent: primaryColor,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _fetchDashboardData,
            color: primaryColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool wide = constraints.maxWidth >= 820;

                final header = _buildTeacherHeader(isDark, primaryColor);
                final session = _buildSessionCard(primaryColor);
                final carousel = TeacherDashboardCarousel(
                  latestAlert: _latestAlert,
                  primaryColor: primaryColor,
                  isDark: isDark,
                );
                final modules = _buildModules(isDark, primaryColor);

                final Widget body = wide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 32),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    session,
                                    const SizedBox(height: 24),
                                    carousel,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 28),
                              Expanded(flex: 6, child: modules),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          session,
                          const SizedBox(height: 20),
                          carousel,
                          const SizedBox(height: 24),
                          modules,
                        ],
                      );

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 40 : 20,
                    vertical: wide ? 32 : 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [const SyncStatusBanner(), body],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModules(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("CLASSROOM MANAGEMENT", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 14),

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

        const SizedBox(height: 14),
        Text("ACADEMIC TASKS", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 14),

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
        _buildModuleTile(
          isDark: isDark,
          icon: Icons.menu_book_rounded,
          color: Colors.indigo,
          title: "Lesson Notes & Documents",
          subtitle: "Download the syllabus and send lesson notes",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeacherDocumentsScreen()),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTeacherHeader(bool isDark, Color primaryColor) {
    return Row(
      children: [
        Container(
          height: 58,
          width: 58,
          decoration: BoxDecoration(
            color: PUi.surface(isDark),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.35),
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
              ? Icon(Icons.school_rounded, color: primaryColor, size: 26)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _schoolName,
                style: TextStyle(
                  fontSize: 13,
                  color: PUi.muted(isDark),
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                "Hello, ${_teacherName.split(' ').first}",
                style: PUi.title(isDark, size: 26),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.88), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 6,
            right: 8,
            width: 150,
            child: IgnorePointer(
              child: AspectRatio(
                aspectRatio: 300 / 190,
                child: CustomPaint(
                  painter: PScenePainter(
                    scene: PScene.hero,
                    line: Colors.white.withValues(alpha: 0.4),
                    tint: Colors.white.withValues(alpha: 0.08),
                    paper: primaryColor,
                  ),
                ),
              ),
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
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _currentSession,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
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
                      fontWeight: FontWeight.w700,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PCard(
        radius: 26,
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            PIconBadge(icon: icon, color: color, size: 52, iconSize: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.2,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 24, color: PUi.muted(isDark)),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PROFILE TAB
  // ===========================================================================
  Widget _buildProfileTab(bool isDark, Color primaryColor) {
    Color cardColor = PUi.surface(isDark);
    String email =
        Supabase.instance.client.auth.currentUser?.email ?? "No email provided";

    return Container(
      color: PUi.bg(isDark),
      child: PBackdrop(
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
                    Center(
                      child: Stack(
                        children: [
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
                              radius: 52,
                              backgroundColor: primaryColor.withValues(
                                alpha: 0.12,
                              ),
                              backgroundImage: _newAvatarBytes != null
                                  ? MemoryImage(_newAvatarBytes!)
                                        as ImageProvider
                                  : (_teacherAvatar != null
                                        ? NetworkImage(_teacherAvatar!)
                                        : null),
                              child:
                                  (_teacherAvatar == null &&
                                      _newAvatarBytes == null)
                                  ? Text(
                                      _teacherName.isNotEmpty
                                          ? _teacherName[0].toUpperCase()
                                          : 'T',
                                      style: TextStyle(
                                        fontSize: 38,
                                        fontWeight: FontWeight.w800,
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
                                    _newAvatarExtension = image.name
                                        .split('.')
                                        .last;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: PUi.bg(isDark),
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
                    ),

                    if (_newAvatarBytes != null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.icon(
                          style: PUi.filledPill(Colors.green, height: 46),
                          onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                          icon: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: TridetaLoader(color: Colors.white),
                                )
                              : const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                ),
                          label: Text(
                            _isUploadingAvatar ? "Saving..." : "Save Picture",
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Text(
                      _teacherName,
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

                    Text("APP SETTINGS", style: PUi.sectionLabel(isDark)),
                    const SizedBox(height: 12),

                    PCard(
                      radius: 28,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
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
                                _buildThemeSegmentedControl(
                                  primaryColor,
                                  isDark,
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: PUi.border(isDark),
                            indent: 20,
                            endIndent: 20,
                          ),

                          // 🚨 AUTHENTICATE BEFORE OPENING PASSWORD DIALOG
                          _buildSettingsRow(
                            isDark: isDark,
                            icon: Icons.lock_outline_rounded,
                            color: Colors.orange,
                            title: "Change Password",
                            onTap: () async {
                              bool authorized = await _authenticateUser(
                                'Authenticate to change your password.',
                              );
                              if (authorized && context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) =>
                                      const SmartChangePasswordDialog(),
                                );
                              }
                            },
                          ),
                          _buildSettingsRow(
                            isDark: isDark,
                            icon: Icons.info_outline_rounded,
                            color: Colors.teal,
                            title: "About Trideta",
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutTridetaScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    OutlinedButton.icon(
                      style: PUi.outlinedPill(Colors.redAccent, height: 56),
                      onPressed: () async {
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: cardColor,
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
                            actionsPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
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

  Widget _buildSettingsRow({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            PIconBadge(icon: icon, color: color, size: 40, iconSize: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                  color: PUi.ink(isDark),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: PUi.muted(isDark)),
          ],
        ),
      ),
    );
  }

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
