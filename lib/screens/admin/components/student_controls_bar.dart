import 'package:flutter/material.dart';

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
