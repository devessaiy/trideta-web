import 'package:flutter/material.dart';
import 'package:trideta_v2/screens/admin/student_admission_screen.dart';
import 'package:trideta_v2/screens/admin/student_profile_screen.dart';
import 'package:trideta_v2/screens/admin/id_card_generator_screen.dart';

// ===========================================================================
// 1. QUICK ACTIONS BOX (Handles Desktop/Mobile Width Dynamics)
// ===========================================================================
class StudentQuickActionsBox extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final VoidCallback onRefresh;

  const StudentQuickActionsBox({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;
    return Container(
      width: isDesktop ? null : double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Directory Tools",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StudentAdmissionScreen(),
                    ),
                  ).then((_) => onRefresh());
                },
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text(
                  "ADMIT STUDENT",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : primaryColor.withValues(alpha: 0.1),
                  foregroundColor: isDark ? Colors.white : primaryColor,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IdCardGeneratorScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.badge_rounded, size: 18),
                label: const Text(
                  "GENERATE ID",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 2. DESKTOP HEADER (With inner Stat Pill logic)
// ===========================================================================
class StudentDesktopHeader extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final int totalStudents;
  final int maleCount;
  final int femaleCount;
  final VoidCallback onRefresh;

  const StudentDesktopHeader({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.totalStudents,
    required this.maleCount,
    required this.femaleCount,
    required this.onRefresh,
  });

  Widget _buildDesktopStatPill(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Student Directory",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Manage enrollments, assign classes, and access full academic records across the institution.",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildDesktopStatPill(
                      "TOTAL",
                      totalStudents.toString(),
                      Icons.groups_rounded,
                      primaryColor,
                    ),
                    _buildDesktopStatPill(
                      "MALES",
                      maleCount.toString(),
                      Icons.male_rounded,
                      Colors.blue,
                    ),
                    _buildDesktopStatPill(
                      "FEMALES",
                      femaleCount.toString(),
                      Icons.female_rounded,
                      Colors.pink,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 30),
          StudentQuickActionsBox(
            primaryColor: primaryColor,
            isDark: isDark,
            onRefresh: onRefresh,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 3. MOBILE HEADER (With Mini Stats logic)
// ===========================================================================
class StudentMobileHeader extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final int totalStudents;
  final int maleCount;
  final int femaleCount;
  final VoidCallback onRefresh;

  const StudentMobileHeader({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.totalStudents,
    required this.maleCount,
    required this.femaleCount,
    required this.onRefresh,
  });

  Widget _buildMobileMiniStat(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Active Session",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.school_rounded,
                    color: Colors.white70,
                    size: 30,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                "Total Enrolled",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "$totalStudents",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMobileMiniStat(
                      Icons.male_rounded,
                      "MALES",
                      maleCount.toString(),
                    ),
                    Container(
                      width: 1,
                      height: 35,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _buildMobileMiniStat(
                      Icons.female_rounded,
                      "FEMALES",
                      femaleCount.toString(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        StudentQuickActionsBox(
          primaryColor: primaryColor,
          isDark: isDark,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

// ===========================================================================
// 4. CONTROLS BAR (Search & Filters)
// ===========================================================================
class StudentControlsBar extends StatelessWidget {
  final Color primaryColor;
  final bool isDark;
  final bool isDesktop;
  final String searchQuery;
  final String selectedClassFilter;
  final String selectedSort;
  final List<String> availableClasses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onClassChanged;
  final ValueChanged<String?> onSortChanged;

  const StudentControlsBar({
    super.key,
    required this.primaryColor,
    required this.isDark,
    required this.isDesktop,
    required this.searchQuery,
    required this.selectedClassFilter,
    required this.selectedSort,
    required this.availableClasses,
    required this.onSearchChanged,
    required this.onClassChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final searchField = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: TextField(
        onChanged: onSearchChanged,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: "Search by name...",
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white54 : Colors.grey.shade400,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );

    final filters = Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedClassFilter,
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                items: availableClasses.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onClassChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedSort,
                icon: Icon(
                  Icons.sort_rounded,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                items:
                    [
                      'First Name A-Z',
                      'First Name Z-A',
                      'Date Added (Newest)',
                      'Date Added (Oldest)',
                    ].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                onChanged: onSortChanged,
              ),
            ),
          ),
        ),
      ],
    );

    return isDesktop
        ? Row(
            children: [
              Expanded(flex: 2, child: searchField),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: filters),
            ],
          )
        : Column(children: [searchField, const SizedBox(height: 12), filters]);
  }
}

// ===========================================================================
// 5. STUDENT LIST CARD
// ===========================================================================
class StudentListCard extends StatelessWidget {
  final dynamic student;
  final bool isDark;
  final Color primaryColor;
  final bool isSelected;
  final bool isSelecting;
  final ValueChanged<String> onToggleSelection;
  final VoidCallback onRefresh;

  const StudentListCard({
    super.key,
    required this.student,
    required this.isDark,
    required this.primaryColor,
    required this.isSelected,
    required this.isSelecting,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final String fullName = "${student['first_name']} ${student['last_name']}";
    final String classLevel = student['class_level'] ?? 'Unassigned';
    final String? photoUrl = student['passport_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? primaryColor
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          if (isSelecting) {
            onToggleSelection(student['id']);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentProfileScreen(
                  name: student['first_name'] ?? '',
                  id: student['id'] ?? '',
                  studentClass: student['class'] ?? '',
                  imagePath: student['photo_url'],
                  parentPhone: student['parent_phone'],
                  parentEmail: student['parent_email'],
                ),
              ),
            ).then((_) => onRefresh());
          }
        },
        onLongPress: () => onToggleSelection(student['id']),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelecting)
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(student['id']),
                activeColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            CircleAvatar(
              radius: 24,
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl == null || photoUrl.isEmpty
                  ? Icon(Icons.person_rounded, color: primaryColor)
                  : null,
            ),
          ],
        ),
        title: Text(
          fullName,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "ID: ${student['admission_no'] ?? 'N/A'} • $classLevel",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}

// ===========================================================================
// 6. STICKY DELEGATE
// ===========================================================================
class StickyControlsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color bgColor;
  final EdgeInsets padding;

  StickyControlsDelegate({
    required this.child,
    required this.height,
    required this.bgColor,
    required this.padding,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: bgColor,
      padding: padding.copyWith(top: 10.0, bottom: 16.0),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant StickyControlsDelegate oldDelegate) {
    return true;
  }
}
