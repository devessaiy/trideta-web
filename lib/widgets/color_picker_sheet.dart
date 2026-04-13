import 'package:flutter/material.dart';

class ColorPickerSheet extends StatelessWidget {
  final Color currentColor;
  final Function(Color) onColorSelected;

  const ColorPickerSheet({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    // The available theme colors
    final List<Map<String, dynamic>> themeColors = [
      {'name': 'Trideta Blue', 'color': const Color(0xFF007ACC)},
      {'name': 'Emerald Green', 'color': const Color(0xFF10B981)},
      {'name': 'Royal Purple', 'color': const Color(0xFF8B5CF6)},
      {'name': 'Sunset Orange', 'color': const Color(0xFFF97316)},
      {'name': 'Crimson Red', 'color': const Color(0xFFEF4444)},
      {'name': 'Slate Grey', 'color': const Color(0xFF64748B)},
      {'name': 'Midnight Black', 'color': const Color(0xFF0F172A)},
      {'name': 'Teal', 'color': const Color(0xFF14B8A6)},
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "School Brand Color",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Select a primary color to match your school's brand. This will update the theme across your entire dashboard.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 25),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            children: themeColors.map((theme) {
              bool isSelected = currentColor.value == theme['color'].value;
              return GestureDetector(
                onTap: () {
                  onColorSelected(theme['color']);
                  Navigator.pop(context);
                },
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: theme['color'],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? textColor : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme['color'].withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      theme['name'],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? textColor : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
