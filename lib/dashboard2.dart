import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/utils/lock_gate.dart';
import 'package:trideta_v2/services/offline_queue.dart';
import 'package:trideta_v2/screens/admin/curriculum_docs_screen.dart';
import 'package:trideta_v2/screens/admin/lesson_note_review_screen.dart';
import 'package:trideta_v2/widgets/sync_status_banner.dart';
import 'package:trideta_v2/utils/resilient_request.dart';

// MODULAR UI IMPORTS
import 'package:trideta_v2/widgets/admin_bottom_nav_bar.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';
import 'package:trideta_v2/screens/admin/admin_dashboard_carousel.dart';

// SCREEN IMPORTS
import 'package:trideta_v2/screens/admin/profile_menu_screen.dart';
import 'package:trideta_v2/screens/admin/school_profile_screen.dart';
import 'package:trideta_v2/screens/admin/alerts_screen.dart';
import 'package:trideta_v2/screens/admin/student_management_screen.dart';
import 'package:trideta_v2/screens/admin/finance_centre_screen.dart';
import 'package:trideta_v2/screens/admin/staff_directory_screen.dart';

// RESULT ENGINE IMPORTS
import 'package:trideta_v2/screens/admin/result_computation_screen.dart';
import 'package:trideta_v2/screens/admin/affective_domain_screen.dart';
import 'package:trideta_v2/screens/admin/master_broadsheet_screen.dart';
import 'package:trideta_v2/screens/admin/report_card_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String userRole;
  const DashboardScreen({super.key, required this.userRole});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;

  late PageController _pageController;

  int _selectedIndex = 0;
  // ignore: unused_field
  bool _isLoading = true;

  // --- SCHOOL DATA STATE ---
  String _schoolName = "Loading School...";
  String? _schoolLogoUrl;
  String _currentSession = "Loading...";

  // --- ADMIN DATA STATE ---
  // ignore: unused_field
  String _adminName = "Loading...";
  Map<String, dynamic>? _latestAlert;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    OfflineQueue.instance.start();
    _fetchSchoolData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Lock-screen gate: true only if the user really unlocked their phone.
  Future<bool> _authenticateAdmin(String reason) =>
      requireDeviceLock(context, reason);

  Future<void> _fetchSchoolData() async {
    final cacheKey = 'dash:admin:${_supabase.auth.currentUser?.id}';

    // Show the last saved copy at once, then refresh from the server below.
    final cached = await LocalCache.get(cacheKey);
    if (cached is Map && mounted) {
      setState(() {
        _adminName = (cached['adminName'] ?? "Admin").toString();
        _schoolName = (cached['schoolName'] ?? "My School").toString();
        _schoolLogoUrl = cached['schoolLogoUrl']?.toString();
        _currentSession = (cached['currentSession'] ?? "Not Set").toString();
        final la = cached['latestAlert'];
        _latestAlert = la is Map ? Map<String, dynamic>.from(la) : null;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final profile = await retryRead(
        () async => await _supabase
            .from('profiles')
            .select('full_name, school_id')
            .eq('id', user.id)
            .single(),
      );

      final schoolId = profile['school_id'];

      if (mounted) {
        setState(() {
          _adminName = profile['full_name'] ?? "Admin";
        });
      }

      // Load the school and the latest alert at the same time.
      final schoolFuture = retryRead(
        () async => await _supabase
            .from('schools')
            .select('name, logo_url, current_session')
            .eq('id', schoolId)
            .single(),
      );

      bool alertLoaded = false;
      Map<String, dynamic>? alertRes;
      final alertFuture = () async {
        try {
          alertRes = await retryRead(
            () async => await _supabase
                .from('alerts')
                .select()
                .eq('school_id', schoolId)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle(),
          );
          alertLoaded = true;
        } catch (_) {}
      }();

      final school = await schoolFuture;
      await alertFuture;
      if (mounted && alertLoaded) _latestAlert = alertRes;

      if (mounted) {
        setState(() {
          _schoolName = school['name'] ?? "My School";
          // The logo address changes whenever a new logo is uploaded, so it
          // can be cached safely (no need to re-download on every refresh).
          _schoolLogoUrl = school['logo_url'];
          _currentSession = school['current_session'] ?? "Not Set";
          _isLoading = false;
        });

        // Keep a saved copy for the next start (works with no internet).
        await LocalCache.put(cacheKey, {
          'adminName': _adminName,
          'schoolName': _schoolName,
          'schoolLogoUrl': _schoolLogoUrl,
          'currentSession': _currentSession,
          'latestAlert': _latestAlert,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (index == 0) _fetchSchoolData();
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) _fetchSchoolData();
  }

  // ===========================================================================
  // 🖼️ UI ONLY — presentation below. School data loading/caching, page
  // switching and the lock-screen gates above are unchanged.
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = PUi.bg(isDark);
    Color navBarColor = PUi.surface(isDark);
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      _buildHomeContent(isDark, primaryColor),
      const StudentManagementScreen(),
      const AlertsScreen(),
      const ProfileMenuScreen(),
    ];

    // 🚨 UI FIX: Removed the massive full-screen _isLoading blocker right here!
    // The screen will now instantly render with "Loading..." text and smoothly snap the data into place.

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
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: pages,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          extendBody: true,
          body: PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: pages,
          ),
          bottomNavigationBar: AdminBottomNavBar(
            selectedIndex: _selectedIndex,
            onItemSelected: _onItemTapped,
            primaryColor: primaryColor,
            navBarColor: navBarColor,
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
    final Widget logo = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PUi.tint(primaryColor, isDark, 0.12),
        image: _schoolLogoUrl != null
            ? DecorationImage(
                image: NetworkImage(_schoolLogoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: _schoolLogoUrl == null
          ? Icon(Icons.school_rounded, color: primaryColor, size: 25)
          : null,
    );

    final String initial = _adminName.isNotEmpty && _adminName != "Loading..."
        ? _adminName[0].toUpperCase()
        : 'A';

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
                  logo,
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "TRIDETA",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 2,
                              color: PUi.ink(isDark),
                            ),
                          ),
                          Text(
                            "ADMIN",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 2,
                              color: PUi.muted(isDark),
                            ),
                          ),
                        ],
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
                        Icons.people_alt_rounded,
                        "Students",
                        1,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.campaign_rounded,
                        "Action Center",
                        2,
                        primaryColor,
                        isDark,
                        expanded,
                      ),
                      _buildDesktopNavItem(
                        Icons.settings_rounded,
                        "Settings",
                        3,
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
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _adminName,
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
                CircleAvatar(
                  radius: 21,
                  backgroundColor: PUi.tint(primaryColor, isDark, 0.14),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
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
    bool expanded,
  ) {
    final bool isSelected = _selectedIndex == index;
    final Color fg = isSelected ? Colors.white : PUi.muted(isDark);

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
              onTap: () => _onItemTapped(index),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Icon(icon, color: fg, size: 24),
              ),
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
          onTap: () => _onItemTapped(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
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
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _fetchSchoolData,
            color: primaryColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool wide = constraints.maxWidth >= 820;

                final header = _buildAdminHeader(isDark, primaryColor);
                final session = _buildSessionCard(primaryColor);
                final carousel = AdminDashboardCarousel(
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
                          const SizedBox(height: 28),
                          if (_schoolLogoUrl == null)
                            _buildLogoWarning(isDark, primaryColor),
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
                          if (_schoolLogoUrl == null)
                            _buildLogoWarning(isDark, primaryColor),
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
        Text("ADMINISTRATIVE & FINANCE", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 14),

        _buildModuleTile(
          isDark: isDark,
          icon: Icons.account_balance_wallet_rounded,
          color: Colors.green.shade600,
          title: "Finance Centre",
          subtitle: "Manage School Finance here!",
          onTap: () async {
            bool auth = await _authenticateAdmin(
              'Authenticate to access the Finance Centre.',
            );
            if (auth && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FinanceCentreScreen()),
              );
            }
          },
        ),
        _buildModuleTile(
          isDark: isDark,
          icon: Icons.badge_rounded,
          color: Colors.orange.shade600,
          title: "Staff Directory",
          subtitle: "Manage teachers & other staff",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffDirectoryScreen()),
          ),
        ),
        const SizedBox(height: 14),
        Text("SCHOOL CURRICULUM", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 14),

        _buildModuleTile(
          isDark: isDark,
          icon: Icons.folder_copy_rounded,
          color: Colors.indigo.shade500,
          title: "Curriculum Documents",
          subtitle: "Send syllabus & scheme of work to teachers",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CurriculumDocsScreen()),
          ),
        ),
        _buildModuleTile(
          isDark: isDark,
          icon: Icons.fact_check_rounded,
          color: Colors.green.shade600,
          title: "Lesson Note Approvals",
          subtitle: "Review lesson notes sent by teachers",
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LessonNoteReviewScreen()),
          ),
        ),
        const SizedBox(height: 14),

        Text("ACADEMIC & RESULTS", style: PUi.sectionLabel(isDark)),
        const SizedBox(height: 14),

        _buildModuleTile(
          isDark: isDark,
          icon: Icons.edit_document,
          color: primaryColor,
          title: "Enter Subject Scores",
          subtitle: "Input CA and Exam scores here",
          onTap: () async {
            bool auth = await _authenticateAdmin(
              'Authenticate to modify student examination scores.',
            );
            if (auth && mounted) {
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
          color: Colors.purple.shade500,
          title: "Performance overview",
          subtitle: "Add behavior & Form Master comments",
          onTap: () async {
            bool auth = await _authenticateAdmin(
              'Authenticate to enter affective domains and remarks.',
            );
            if (auth && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AffectiveDomainScreen()),
              );
            }
          },
        ),
        _buildModuleTile(
          isDark: isDark,
          icon: Icons.table_chart_rounded,
          color: Colors.teal.shade500,
          title: "Master Broadsheet",
          subtitle: "Compute and publish term results",
          onTap: () async {
            bool auth = await _authenticateAdmin(
              'Authenticate to compute and publish results.',
            );
            if (auth && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MasterBroadsheetScreen(),
                ),
              );
            }
          },
        ),
        _buildModuleTile(
          isDark: isDark,
          icon: Icons.print_rounded,
          color: Colors.redAccent,
          title: "Report Cards",
          subtitle: "Generate & Print Report Cards.",
          onTap: () async {
            bool auth = await _authenticateAdmin(
              'Authenticate to view and print Report Cards.',
            );
            if (auth && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportCardScreen()),
              );
            }
          },
        ),
        // Keeps the last tile clear of the floating navigation bar on phones
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildAdminHeader(bool isDark, Color primaryColor) {
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
                "System Administrator",
                style: TextStyle(
                  fontSize: 13,
                  color: PUi.muted(isDark),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _schoolName,
                style: PUi.title(isDark, size: 24),
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
                      Icons.security_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "SECURE WORKSPACE",
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
                  child: const Text(
                    "All Systems Operational",
                    style: TextStyle(
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

  Widget _buildLogoWarning(bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: PCard(
        radius: 26,
        padding: const EdgeInsets.all(16),
        borderColor: primaryColor.withValues(alpha: 0.35),
        child: Row(
          children: [
            PIconBadge(
              icon: Icons.add_photo_alternate_rounded,
              color: primaryColor,
              size: 48,
              iconSize: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Add School Logo",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: PUi.ink(isDark),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "Enhance your documents by adding your school logo.",
                    style: TextStyle(fontSize: 12.5, color: PUi.muted(isDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              style: PUi.filledPill(primaryColor, height: 42).copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SchoolProfileScreen()),
              ).then((_) => _fetchSchoolData()),
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );
  }
}
