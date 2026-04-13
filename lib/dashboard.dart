import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// SCREEN IMPORTS
import 'package:trideta_v2/screens/admin/profile_menu_screen.dart';
import 'package:trideta_v2/screens/admin/school_profile_screen.dart';
import 'package:trideta_v2/screens/admin/alerts_screen.dart';
import 'package:trideta_v2/screens/admin/student_management_screen.dart';
import 'package:trideta_v2/screens/admin/finance_centre_screen.dart';
import 'package:trideta_v2/screens/admin/staff_directory_screen.dart';

// 🚨 RESULT ENGINE IMPORTS
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
  int _selectedIndex = 0;

  // --- SCHOOL DATA STATE ---
  String _schoolName = "Loading School...";
  String? _schoolLogoUrl;
  String _currentSession = "Loading...";
  String _currentTerm = "";

  @override
  void initState() {
    super.initState();
    _fetchSchoolData();
  }

  Future<void> _fetchSchoolData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      final school = await Supabase.instance.client
          .from('schools')
          .select()
          .eq('id', schoolId)
          .single();

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
        });
      }
    } catch (e) {
      debugPrint("Error fetching school data: $e");
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // 🚨 THE NEW RESULTS POPUP MENU 🚨
  void _showResultsMenu(BuildContext context, bool isDark, Color primaryColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Academic Results Hub",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Select a module to manage student academics.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 25),

              _buildMenuOption(
                context,
                title: "1. Cognitive Scores (CA & Exam)",
                subtitle: "Enter subject scores for your classes",
                icon: Icons.edit_document,
                color: primaryColor,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResultComputationScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuOption(
                context,
                title: "2. Affective Domain & Remarks",
                subtitle: "Rate student behaviors (1-5) and comment",
                icon: Icons.psychology_alt_rounded,
                color: Colors.orange,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AffectiveDomainScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuOption(
                context,
                title: "3. Master Broadsheet",
                subtitle: "View grid, compute averages & rank students",
                icon: Icons.table_chart_rounded,
                color: Colors.green,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MasterBroadsheetScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuOption(
                context,
                title: "4. Generate Report Cards",
                subtitle: "View, download and print final PDFs",
                icon: Icons.print_rounded,
                color: Colors.blue,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReportCardScreen()),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
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

    // 🚨 THE MAGIC SHAPE-SHIFTER: LayoutBuilder
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          // 💻 DESKTOP LAYOUT (Side Navigation)
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: navBarColor,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  selectedIconTheme: IconThemeData(color: primaryColor),
                  selectedLabelTextStyle: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
                  indicatorColor: primaryColor.withOpacity(0.1),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 15),
                    child: _schoolLogoUrl != null
                        ? CircleAvatar(
                            radius: 24,
                            backgroundColor: primaryColor.withOpacity(0.1),
                            backgroundImage: NetworkImage(_schoolLogoUrl!),
                          )
                        : Icon(
                            Icons.admin_panel_settings_rounded,
                            color: primaryColor,
                            size: 40,
                          ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Students'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.notifications_outlined),
                      selectedIcon: Icon(Icons.notifications),
                      label: Text('Alerts'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.menu),
                      selectedIcon: Icon(Icons.menu_open),
                      label: Text('Menu'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: pages,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // 📱 MOBILE LAYOUT (Bottom Navigation)
          return Scaffold(
            backgroundColor: bgColor,
            body: IndexedStack(index: _selectedIndex, children: pages),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                backgroundColor: navBarColor,
                elevation: 0,
                indicatorColor: primaryColor.withOpacity(0.1),
                height: 70,
                destinations:
                    [
                      const NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: 'Home',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        selectedIcon: Icon(Icons.people),
                        label: 'Students',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.notifications_outlined),
                        selectedIcon: Icon(Icons.notifications),
                        label: 'Alerts',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.menu),
                        selectedIcon: Icon(Icons.menu_open),
                        label: 'Menu',
                      ),
                    ].map((dest) {
                      return NavigationDestination(
                        icon: dest.icon,
                        selectedIcon: Icon(
                          (dest.selectedIcon as Icon).icon,
                          color: primaryColor,
                        ),
                        label: dest.label,
                      );
                    }).toList(),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildHomeContent(bool isDark, Color primaryColor) {
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.white70 : Colors.grey[600]!;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchSchoolData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSchoolHeader(textColor, subTextColor, primaryColor),
              const SizedBox(height: 25),
              _buildSessionCard(primaryColor),
              const SizedBox(height: 30),

              Text(
                "PEOPLE & ADMINISTRATION",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: primaryColor.withOpacity(0.8),
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 15),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.school_rounded,
                color: Colors.orange,
                title: "Student Management",
                subtitle: "Admissions, Class List & Profiles",
                onTap: () => setState(() => _selectedIndex = 1),
              ),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.badge_rounded,
                color: Colors.purple,
                title: "Staff Directory",
                subtitle: "Teachers, Roles & Permissions",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffDirectoryScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 25),
              Text(
                "ACADEMICS & FINANCE",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: primaryColor.withOpacity(0.8),
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 15),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.analytics_rounded,
                color: primaryColor,
                title: "Results & Broadsheets",
                subtitle: "Scores, Affective Traits & Rankings",
                onTap: () => _showResultsMenu(context, isDark, primaryColor),
              ),

              _buildModuleTile(
                isDark: isDark,
                icon: Icons.account_balance_wallet_rounded,
                color: Colors.green,
                title: "Finance Centre",
                subtitle: "Payments, Receipts & Debtors",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FinanceCentreScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              if (_schoolLogoUrl == null)
                _buildLogoWarning(isDark, primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolHeader(
    Color textColor,
    Color subTextColor,
    Color primaryColor,
  ) {
    return Row(
      children: [
        Container(
          height: 65,
          width: 65,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
            ],
            border: Border.all(color: primaryColor.withOpacity(0.2), width: 2),
            image: _schoolLogoUrl != null
                ? DecorationImage(
                    image: NetworkImage(_schoolLogoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: _schoolLogoUrl == null
              ? Icon(Icons.school_rounded, color: primaryColor, size: 32)
              : null,
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(
                  fontSize: 14,
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _schoolName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                "CURRENT ACTIVE TIMELINE",
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
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              _currentTerm,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
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
    Color textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: isDark ? Colors.white24 : Colors.grey[300],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoWarning(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: primaryColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            color: primaryColor,
            size: 24,
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "Enhance your documents by adding your school logo.",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SchoolProfileScreen()),
            ).then((_) => _fetchSchoolData()),
            child: Text(
              "Add Now",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
