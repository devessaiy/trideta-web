import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

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
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> navItems = [
      {
        'label': 'Home',
        'activeIcon': Icons.dashboard_rounded,
        'inactiveIcon': Icons.dashboard_outlined,
      },
      {
        'label': 'Students',
        'activeIcon': Icons.people_alt_rounded,
        'inactiveIcon': Icons.people_outline_rounded,
      },
      {
        'label': 'Alerts',
        'activeIcon': Icons.campaign_rounded,
        'inactiveIcon': Icons.campaign_outlined,
      },
      {
        'label': 'Settings',
        'activeIcon': Icons.settings_rounded,
        'inactiveIcon': Icons.settings_outlined,
      },
    ];

    // A floating frosted pill that sits over the page content.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20.0, left: 20.0, right: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.35 : 0.10,
                      ),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: PUi.surface(isDark).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: PUi.border(isDark), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(navItems.length, (index) {
                          final item = navItems[index];
                          final bool isActive = selectedIndex == index;

                          return _buildNavItem(
                            context: context,
                            isActive: isActive,
                            activeIcon: item['activeIcon'] as IconData,
                            inactiveIcon: item['inactiveIcon'] as IconData,
                            label: item['label'] as String,
                            index: index,
                            isDark: isDark,
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required bool isActive,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
    required int index,
    required bool isDark,
  }) {
    final Color inactiveItemColor = PUi.muted(isDark);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onItemSelected(index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? 20 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isActive ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              size: 24,
              color: isActive ? Colors.white : inactiveItemColor,
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
