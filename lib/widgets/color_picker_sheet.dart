import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trideta_v2/main.dart'; // IMPORTED TO SYNC THE GLOBAL THEME

class ColorPickerSheet extends StatelessWidget {
  final Color currentColor;

  const ColorPickerSheet({super.key, required this.currentColor});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;

    // 🚨 18 Premium Theme Colors
    final List<Map<String, dynamic>> themeColors = [
      {'name': 'Trideta Blue', 'color': const Color(0xFF007ACC)},
      {'name': 'Emerald Green', 'color': const Color(0xFF10B981)},
      {'name': 'Royal Purple', 'color': const Color(0xFF8B5CF6)},
      {'name': 'Sunset Orange', 'color': const Color(0xFFF97316)},
      {'name': 'Crimson Red', 'color': const Color(0xFFEF4444)},
      {'name': 'Slate Grey', 'color': const Color(0xFF64748B)},
      {'name': 'Midnight Black', 'color': const Color(0xFF0F172A)},
      {'name': 'Teal', 'color': const Color(0xFF14B8A6)},
      {'name': 'Electric Blue', 'color': const Color(0xFF007BFF)},
      {'name': 'Mint Green', 'color': const Color(0xFF36ADA3)},
      {'name': 'Vivid Coral', 'color': const Color(0xFFFF6F61)},
      {'name': 'Lavender Haze', 'color': const Color(0xFFB39DDB)},
      {'name': 'Neon Wasabi', 'color': const Color(0xFFD1E231)},
      {'name': 'Sunset Peach', 'color': const Color(0xFFFFDAB9)},
      {'name': 'Deep Berry', 'color': const Color(0xFF7D2C5E)},
      {'name': 'Tangerine', 'color': const Color(0xFFFBAB60)},
      {'name': 'Cyan', 'color': const Color(0xFF039FBE)},
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "School Brand Color",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Select a primary color to match your school's brand. This will immediately update the theme across your entire dashboard.",
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 25),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            children: themeColors.map((theme) {
              Color c = theme['color'];
              bool isSelected = currentColor.toARGB32() == c.toARGB32();

              return GestureDetector(
                onTap: () async {
                  // 1. UPDATE GLOBAL COLOR INSTANTLY
                  appColorNotifier.value = c;

                  // 2. BACKUP TO MEMORY
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('app_primary_color', c.toARGB32());

                  // 3. PUSH HEX FORMAT TO DATABASE
                  try {
                    String hexColor =
                        '#${c.toARGB32().toRadixString(16).substring(2, 8).toUpperCase()}';
                    final userId =
                        Supabase.instance.client.auth.currentUser!.id;
                    final userData = await Supabase.instance.client
                        .from('profiles')
                        .select('school_id')
                        .eq('id', userId)
                        .single();
                    final schoolId = userData['school_id'];

                    if (schoolId != null) {
                      await Supabase.instance.client
                          .from('schools')
                          .update({'brand_color': hexColor})
                          .eq('id', schoolId);
                    }
                  } catch (e) {
                    debugPrint("Failed to save brand color: $e");
                  }

                  if (context.mounted) Navigator.pop(context);
                },
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: textColor, width: 3)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: c.withValues(alpha: 0.4),
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
                      theme['name'].split(' ')[0], // Keep text compact
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? textColor : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
