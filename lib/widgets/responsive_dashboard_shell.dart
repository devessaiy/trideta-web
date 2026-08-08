import 'package:flutter/material.dart';

// Import your existing Parent screens
import 'package:trideta_v2/screens/parent/parent_dashboard_screen.dart';
import 'package:trideta_v2/screens/parent/parent_alerts_master_detail.dart';

class ResponsiveDashboardShell extends StatefulWidget {
  const ResponsiveDashboardShell({super.key});

  @override
  State<ResponsiveDashboardShell> createState() =>
      _ResponsiveDashboardShellState();
}

class _ResponsiveDashboardShellState extends State<ResponsiveDashboardShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 🚨 IF WIDE SCREEN (Desktop/Web) -> Use 3-Column Layout
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                // 1. LEFT COLUMN: Navigation Sidebar
                _buildSidebar(),

                // 2. MIDDLE & RIGHT COLUMNS: The Active Screen content
                Expanded(child: _buildSelectedDesktopScreen()),
              ],
            ),
          );
        }

        // 🚨 IF NARROW SCREEN (Mobile) -> Fallback to your standard mobile dashboard
        return const ParentDashboardScreen();
      },
    );
  }

  Widget _buildSidebar() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      width: 250, // Fixed width for sidebar
      color: bgColor,
      child: Column(
        children: [
          const SizedBox(height: 40),
          // Logo Area
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

          // Navigation Items
          _buildNavItem(Icons.home_rounded, "Home", 0),
          _buildNavItem(Icons.family_restroom, "Wards", 1),
          _buildNavItem(Icons.notifications_active_rounded, "Alerts", 2),
          _buildNavItem(Icons.person, "Profile", 3),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index) {
    bool isSelected = _selectedIndex == index;
    Color primaryColor = Theme.of(context).primaryColor;

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
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  Widget _buildSelectedDesktopScreen() {
    // This routes the desktop view based on which sidebar item is clicked.
    // For now, we point tab 2 (Alerts) to our new messaging layout.
    // You can point the others to the corresponding tabs inside ParentDashboardScreen later.
    switch (_selectedIndex) {
      case 0:
        return const Center(child: Text("Home Dashboard Content Here"));
      case 1:
        return const Center(child: Text("Wards Content Here"));
      case 2:
        // 🚨 This loads our new 2-column messaging app layout!
        return const ParentAlertsMasterDetail();
      case 3:
        return const Center(child: Text("Profile Content Here"));
      default:
        return const Center(child: Text("Home Dashboard Content Here"));
    }
  }
}
