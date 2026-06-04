import 'package:flutter/material.dart';

class AdminBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Color primaryColor;
  final Color navBarColor;

  const AdminBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.primaryColor,
    required this.navBarColor,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemSelected,
      backgroundColor: navBarColor,
      indicatorColor: primaryColor.withValues(alpha: 0.1),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded, color: primaryColor),
          label: 'Home',
        ),
        NavigationDestination(
          icon: const Icon(Icons.people_outline_rounded),
          selectedIcon: Icon(Icons.people_alt_rounded, color: primaryColor),
          label: 'Students',
        ),
        NavigationDestination(
          icon: const Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign_rounded, color: primaryColor),
          label: 'Alerts',
        ),
        // 🚨 CHANGED: Now uses the Settings icon and label to match desktop
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded, color: primaryColor),
          label: 'Settings',
        ),
      ],
    );
  }
}
