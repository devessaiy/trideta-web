import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';

import 'package:trideta_v2/widgets/trideta_loader.dart';

// MODULAR UI IMPORTS
import 'package:trideta_v2/widgets/admin_bottom_nav_bar.dart';
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
  final LocalAuthentication _localAuth = LocalAuthentication();

  late PageController _pageController;

  int _selectedIndex = 0;
  bool _isLoading = true;

  // --- SCHOOL DATA STATE ---
  String _schoolName = "Loading School...";
  String? _schoolLogoUrl;
  String _currentSession = "Loading...";

  // --- ADMIN DATA STATE ---
  String _adminName = "Loading...";
  Map<String, dynamic>? _latestAlert;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _fetchSchoolData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // SECURITY GATE (v3.0.1 Syntax)
  // 🚨 CONFIDENTIAL SECURITY GATE
  // 🚨 CONFIDENTIAL SECURITY GATE (Using the proven, error-free syntax)
  Future<bool> _authenticateAdmin(String reason) async {
    try {
      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) return true;

      // 🚨 FIXED: Using the simple API that perfectly matches your setup!
      return await _localAuth.authenticate(localizedReason: reason);
    } catch (e) {
      debugPrint("Local auth error: $e");
      return true;
    }
  }

  Future<void> _fetchSchoolData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('full_name, school_id')
          .eq('id', user.id)
          .single();

      final schoolId = profile['school_id'];

      if (mounted) {
        setState(() {
          _adminName = profile['full_name'] ?? "Admin";
        });
      }

      final school = await _supabase
          .from('schools')
          .select()
          .eq('id', schoolId)
          .single();

      try {
        final alertRes = await _supabase
            .from('alerts')
            .select()
            .eq('school_id', schoolId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (mounted) _latestAlert = alertRes;
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
          _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      _buildHomeContent(isDark, primaryColor),
      const StudentManagementScreen(),
      const AlertsScreen(),
      const ProfileMenuScreen(),
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
                      // 🚨 FIXED: Now uses School Logo or School Icon in Sidebar
                      _schoolLogoUrl != null
                          ? CircleAvatar(
                              radius: 25,
                              backgroundColor: primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              backgroundImage: NetworkImage(_schoolLogoUrl!),
                            )
                          : Icon(
                              Icons.school_rounded,
                              size: 50,
                              color: primaryColor,
                            ),
                      const SizedBox(height: 20),
                      const Text(
                        "TRIDETA ADMIN",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
                        Icons.people_alt_rounded,
                        "Students",
                        1,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.campaign_rounded,
                        "Action Center",
                        2,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.settings_rounded,
                        "Settings",
                        3,
                        primaryColor,
                      ),
                    ],
                  ),
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

  Widget _buildDesktopNavItem(
    IconData icon,
    String title,
    int index,
    Color primaryColor,
  ) {
    bool isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? primaryColor : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? primaryColor : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: primaryColor.withValues(alpha: 0.1),
      onTap: () => _onItemTapped(index),
    );
  }

  Widget _buildHomeContent(bool isDark, Color primaryColor) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchSchoolData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAdminHeader(textColor, subTextColor, primaryColor),
              const SizedBox(height: 30),

              if (_schoolLogoUrl == null)
                _buildLogoWarning(isDark, primaryColor),

              _buildGlassySessionCard(primaryColor),
              const SizedBox(height: 35),

              AdminDashboardCarousel(
                latestAlert: _latestAlert,
                primaryColor: primaryColor,
                isDark: isDark,
              ),
              const SizedBox(height: 30),

              Text(
                "ADMINISTRATIVE & FINANCE",
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
                icon: Icons.account_balance_wallet_rounded,
                color: Colors.green.shade600,
                title: "Finance Centre",
                subtitle: "Manage fees, receipts, and debtors",
                onTap: () async {
                  bool auth = await _authenticateAdmin(
                    'Authenticate to access the Finance Centre.',
                  );
                  if (auth && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FinanceCentreScreen(),
                      ),
                    );
                  }
                },
              ),
              _buildModuleTile(
                isDark: isDark,
                icon: Icons.badge_rounded,
                color: Colors.orange.shade600,
                title: "Staff Directory",
                subtitle: "Manage teachers and role assignments",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StaffDirectoryScreen(),
                  ),
                ),
              ),

              // 🚨 REMOVED: School Configuration module removed from here!
              const SizedBox(height: 30),
              Text(
                "ACADEMIC & RESULTS",
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
                title: "Affective Domain & Remarks",
                subtitle: "Rate behavior and add Form Master comments",
                onTap: () async {
                  bool auth = await _authenticateAdmin(
                    'Authenticate to enter affective domains and remarks.',
                  );
                  if (auth && mounted) {
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
                subtitle: "Generate and print student dossiers",
                onTap: () async {
                  bool auth = await _authenticateAdmin(
                    'Authenticate to view and print Report Cards.',
                  );
                  if (auth && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReportCardScreen(),
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

  Widget _buildAdminHeader(
    Color textColor,
    Color subTextColor,
    Color primaryColor,
  ) {
    return Row(
      children: [
        // 🚨 FIXED: Now explicitly uses the School Logo, with a School Icon fallback
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
                "System Administrator",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _schoolName,
                style: TextStyle(
                  fontSize: 20,
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
                  child: const Text(
                    "All Systems Operational",
                    style: TextStyle(
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

  Widget _buildLogoWarning(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 30),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_photo_alternate_rounded,
            color: primaryColor,
            size: 28,
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "Enhance your documents by adding your school logo.",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SchoolProfileScreen()),
            ).then((_) => _fetchSchoolData()),
            child: const Text(
              "Add Now",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
