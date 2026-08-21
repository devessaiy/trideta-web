import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    // 🚨 FIX: Removed the massive gradient wrapper.
    // Now it is just a completely transparent SafeArea holding the floating pill!
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The shadow sits strictly behind the pill
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  // Strong blur so content passing underneath looks like frosted glass
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      // Highly transparent background allows the blur to shine through
                      color: isDark
                          ? const Color(0xFF1E1E1E).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.05),
                        width: 1,
                      ),
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
    final Color activePillBg = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : primaryColor.withValues(alpha: 0.15);

    final Color activeItemColor = primaryColor;
    final Color inactiveItemColor = isDark
        ? Colors.white70
        : Colors.grey.shade700;

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
          color: isActive ? activePillBg : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              size: isActive ? 28 : 24,
              color: isActive ? activeItemColor : inactiveItemColor,
            ),
            if (isActive) ...[
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: activeItemColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
