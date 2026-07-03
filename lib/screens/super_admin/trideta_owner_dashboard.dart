import 'package:flutter/material.dart';

// 🚨 MODULAR VIEW IMPORTS
import 'package:trideta_v2/screens/super_admin/owner_views/owner_metrics_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_schools_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_profiles_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_social_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_settings_view.dart';

class TridetaOwnerDashboard extends StatefulWidget {
  const TridetaOwnerDashboard({super.key});

  @override
  State<TridetaOwnerDashboard> createState() => _TridetaOwnerDashboardState();
}

class _TridetaOwnerDashboardState extends State<TridetaOwnerDashboard> {
  late PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      OwnerMetricsView(onNavigate: _onItemTapped),
      OwnerSchoolsManagementView(),
      OwnerProfilesManagementView(),
      OwnerSocialModerationView(),
      OwnerSettingsView(), // 🚨 NEW MODULAR SETTINGS VIEW
    ];

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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 40,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "TRIDETA MASTER",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _buildDesktopNavItem(
                        Icons.dashboard_rounded,
                        "Overview",
                        0,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.domain_rounded,
                        "Client Schools",
                        1,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.people_alt_rounded,
                        "User Directory",
                        2,
                        primaryColor,
                      ),
                      _buildDesktopNavItem(
                        Icons.forum_rounded,
                        "Social Space",
                        3,
                        primaryColor,
                      ),
                      const Spacer(),
                      _buildDesktopNavItem(
                        Icons.settings_rounded,
                        "Settings & Security",
                        4,
                        primaryColor,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) =>
                        setState(() => _selectedIndex = index),
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
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            children: pages,
          ),
          bottomNavigationBar: BottomNavigationBar(
            backgroundColor: navBarColor,
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey.shade500,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
            onTap: _onItemTapped,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_rounded),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.domain_rounded),
                label: "Schools",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_alt_rounded),
                label: "Users",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.forum_rounded),
                label: "Social",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_rounded),
                label: "Settings",
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
}
