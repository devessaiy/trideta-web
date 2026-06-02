import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/screens/parent/parent_child_detail_screen.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class ParentWardsTab extends StatefulWidget {
  final List<Map<String, dynamic>> myChildren;
  final VoidCallback onRefresh;

  const ParentWardsTab({
    super.key,
    required this.myChildren,
    required this.onRefresh,
  });

  @override
  State<ParentWardsTab> createState() => _ParentWardsTabState();
}

class _ParentWardsTabState extends State<ParentWardsTab> {
  Map<String, dynamic>? _selectedChild;

  @override
  void initState() {
    super.initState();
    if (widget.myChildren.isNotEmpty) {
      _selectedChild = widget.myChildren[0];
    }
  }

  @override
  void didUpdateWidget(ParentWardsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.myChildren != oldWidget.myChildren &&
        widget.myChildren.isNotEmpty) {
      final stillExists = widget.myChildren.any(
        (c) => c['id'] == _selectedChild?['id'],
      );
      if (!stillExists) {
        _selectedChild = widget.myChildren[0];
      }
    }
  }

  Future<void> _launchContact(
    BuildContext context,
    String type,
    String value,
  ) async {
    final Uri url = Uri(scheme: type, path: value);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open contact app.")),
        );
      }
    }
  }

  // ===========================================================================
  // PREMIUM WHITE & GLASSY BOTTOM SHEET
  // ===========================================================================
  void _showContactAdminSheet(
    BuildContext context,
    Map<String, dynamic> school,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: Supabase.instance.client
              .from('profiles')
              .select('phone, email, full_name')
              .eq('school_id', school['id'])
              .ilike('role', 'admin')
              .limit(1)
              .maybeSingle(),
          builder: (context, snapshot) {
            Widget content;

            if (snapshot.connectionState == ConnectionState.waiting) {
              content = SizedBox(
                height: 250,
                child: Center(child: TridetaLoader(color: primaryColor)),
              );
            } else {
              final adminProfile = snapshot.data;
              final phone = adminProfile?['phone'];
              final email = adminProfile?['email'];
              final adminName =
                  adminProfile?['full_name'] ?? 'School Administration';

              content = Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white30 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 30),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.support_agent_rounded,
                        color: primaryColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Contact Admin",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      adminName,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildGlassyContactTile(
                      icon: Icons.phone_rounded,
                      title: "Call Phone",
                      subtitle: phone ?? 'No phone provided',
                      color: Colors.green,
                      isDark: isDark,
                      onTap: phone != null && phone.toString().isNotEmpty
                          ? () => _launchContact(context, 'tel', phone)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildGlassyContactTile(
                      icon: Icons.email_rounded,
                      title: "Send Email",
                      subtitle: email ?? 'No email provided',
                      color: Colors.blue,
                      isDark: isDark,
                      onTap: email != null && email.toString().isNotEmpty
                          ? () => _launchContact(context, 'mailto', email)
                          : null,
                    ),
                  ],
                ),
              );
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: SafeArea(child: content),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGlassyContactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.white,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // Helper to safely parse the Hex Color from the Database
  Color _getSchoolColor(Map<String, dynamic> school, Color fallback) {
    String? hexStr = school['brand_color'];
    if (hexStr != null && hexStr.isNotEmpty) {
      try {
        hexStr = hexStr.replaceAll('#', '');
        if (hexStr.length == 6) hexStr = 'FF$hexStr';
        return Color(int.parse(hexStr, radix: 16));
      } catch (_) {}
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;

    Color bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color subTextColor = isDark ? Colors.white70 : const Color(0xFF9098B1);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 900;

          Widget wardsList = Container(
            width: isMobile ? double.infinity : 380,
            decoration: BoxDecoration(
              color: bgColor,
              border: isMobile
                  ? null
                  : Border(
                      right: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "My Linked Wards",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Manage academic & financial records",
                        style: TextStyle(color: subTextColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: RefreshIndicator(
                    color: primaryColor,
                    onRefresh: () async => widget.onRefresh(),
                    child: widget.myChildren.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.2,
                              ),
                              Icon(
                                Icons.face_retouching_off_rounded,
                                size: 80,
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey[200],
                              ),
                              const SizedBox(height: 15),
                              Center(
                                child: Text(
                                  "No children linked to your account yet.",
                                  style: TextStyle(color: subTextColor),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            itemCount: widget.myChildren.length,
                            itemBuilder: (context, index) {
                              final child = widget.myChildren[index];
                              final school = child['schools'];

                              String fName = child['first_name'] ?? '';
                              String lName = child['last_name'] ?? '';
                              String initial = fName.isNotEmpty
                                  ? fName[0]
                                  : '?';
                              String passport = child['passport_url'] ?? '';

                              Color schoolColor = _getSchoolColor(
                                school,
                                primaryColor,
                              );
                              bool isSelected =
                                  !isMobile &&
                                  _selectedChild?['id'] == child['id'];

                              return GestureDetector(
                                onTap: () {
                                  if (isMobile) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ParentChildDetailScreen(
                                          childData: child,
                                        ),
                                      ),
                                    );
                                  } else {
                                    setState(() => _selectedChild = child);
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  margin: const EdgeInsets.only(bottom: 20),
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        schoolColor.withValues(alpha: 0.85),
                                        schoolColor,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.2),
                                      width: isSelected ? 2.5 : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: schoolColor.withValues(
                                          alpha: isSelected ? 0.4 : 0.2,
                                        ),
                                        blurRadius: isSelected ? 20 : 10,
                                        offset: Offset(0, isSelected ? 8 : 4),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        right: -30,
                                        top: -30,
                                        child: CircleAvatar(
                                          radius: 60,
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                      Positioned(
                                        left: -20,
                                        bottom: -40,
                                        child: CircleAvatar(
                                          radius: 50,
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.05),
                                        ),
                                      ),

                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 🚨 FIX: Top Row Text Overflow
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.2,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (school['logo_url'] !=
                                                            null)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  right: 6,
                                                                ),
                                                            child: Image.network(
                                                              school['logo_url'],
                                                              height: 14,
                                                              width: 14,
                                                            ),
                                                          )
                                                        else
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  right: 6,
                                                                ),
                                                            child: Icon(
                                                              Icons
                                                                  .school_rounded,
                                                              size: 14,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        Flexible(
                                                          child: Text(
                                                            school['name'] ??
                                                                'Unknown School',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 12,
                                                ), // Guarantee some breathing room
                                                Text(
                                                  school['current_session'] ??
                                                      'N/A',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),

                                            Row(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: CircleAvatar(
                                                    radius: 28,
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.2),
                                                    backgroundImage:
                                                        passport.isNotEmpty
                                                        ? NetworkImage(passport)
                                                        : null,
                                                    child: passport.isEmpty
                                                        ? Text(
                                                            initial,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 20,
                                                                ),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        "$fName $lName",
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 18,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Class: ${child['class_level'] ?? 'Unassigned'}",
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 20),

                                            Row(
                                              children: [
                                                Expanded(
                                                  child: FilledButton(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.white,
                                                      foregroundColor:
                                                          schoolColor,
                                                      elevation: 0,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 12,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                    ),
                                                    onPressed: () {
                                                      if (isMobile) {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                ParentChildDetailScreen(
                                                                  childData:
                                                                      child,
                                                                ),
                                                          ),
                                                        );
                                                      } else {
                                                        setState(
                                                          () => _selectedChild =
                                                              child,
                                                        );
                                                      }
                                                    },
                                                    child: const Text(
                                                      "View Profile",
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  onPressed: () =>
                                                      _showContactAdminSheet(
                                                        context,
                                                        school,
                                                        isDark,
                                                        primaryColor,
                                                      ),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.2),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.support_agent_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Scaffold(backgroundColor: bgColor, body: wardsList);
          }

          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                wardsList,
                Expanded(
                  child: _selectedChild == null
                      ? Center(
                          child: Text(
                            "Select a ward to view records",
                            style: TextStyle(color: subTextColor),
                          ),
                        )
                      : ParentChildDetailScreen(
                          key: ValueKey(_selectedChild!['id']),
                          childData: _selectedChild!,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
