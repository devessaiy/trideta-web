import 'package:flutter/material.dart';
import 'package:trideta_v2/widgets/trideta_ui_kit.dart';

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

  BoxDecoration _pillDecoration() => BoxDecoration(
    color: PUi.surface(isDark),
    borderRadius: BorderRadius.circular(30),
    border: Border.all(color: PUi.border(isDark)),
  );

  @override
  Widget build(BuildContext context) {
    final searchField = Container(
      decoration: _pillDecoration(),
      child: TextField(
        onChanged: onSearchChanged,
        style: TextStyle(fontSize: 14, color: PUi.ink(isDark)),
        decoration: InputDecoration(
          hintText: "Search by name...",
          hintStyle: TextStyle(color: PUi.muted(isDark)),
          prefixIcon: Icon(Icons.search_rounded, color: PUi.muted(isDark)),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            decoration: _pillDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedClassFilter,
                dropdownColor: PUi.surface(isDark),
                borderRadius: BorderRadius.circular(20),
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: PUi.muted(isDark),
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: PUi.ink(isDark),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            decoration: _pillDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedSort,
                dropdownColor: PUi.surface(isDark),
                borderRadius: BorderRadius.circular(20),
                icon: Icon(
                  Icons.sort_rounded,
                  color: PUi.muted(isDark),
                  size: 18,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: PUi.ink(isDark),
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
