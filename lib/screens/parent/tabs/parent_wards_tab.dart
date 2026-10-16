import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/screens/parent/parent_child_detail_screen.dart';
import 'package:trideta_v2/screens/parent/parent_ui_kit.dart';
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
  // CONTACT ADMIN BOTTOM SHEET
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
      constraints: const BoxConstraints(maxWidth: 520),
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
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: PUi.border(isDark),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 26),
                    PIconBadge(
                      icon: Icons.support_agent_rounded,
                      color: primaryColor,
                      size: 68,
                      iconSize: 32,
                    ),
                    const SizedBox(height: 16),
                    Text("Contact Admin", style: PUi.title(isDark, size: 24)),
                    const SizedBox(height: 4),
                    Text(
                      adminName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: PUi.muted(isDark),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _buildContactTile(
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
                    _buildContactTile(
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

            return Container(
              decoration: BoxDecoration(
                color: PUi.surface(isDark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: PUi.border(isDark)),
              ),
              child: SafeArea(child: content),
            );
          },
        );
      },
    );
  }

  Widget _buildContactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback? onTap,
  }) {
    return PCard(
      radius: 22,
      shadow: false,
      color: PUi.surfaceAlt(isDark),
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          PIconBadge(icon: icon, color: color, size: 44, iconSize: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: PUi.ink(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: PUi.muted(isDark)),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: PUi.muted(isDark)),
        ],
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

  // ===========================================================================
  // WARD CARD
  // ===========================================================================
  Widget _buildWardCard(
    Map<String, dynamic> child,
    bool isMobile,
    bool isDark,
    Color primaryColor,
  ) {
    final school = child['schools'];

    String fName = child['first_name'] ?? '';
    String lName = child['last_name'] ?? '';
    String initial = fName.isNotEmpty ? fName[0] : '?';
    String passport = child['passport_url'] ?? '';

    Color schoolColor = _getSchoolColor(school, primaryColor);
    bool isSelected = !isMobile && _selectedChild?['id'] == child['id'];

    void openProfile() {
      if (isMobile) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentChildDetailScreen(childData: child),
          ),
        );
      } else {
        setState(() => _selectedChild = child);
      }
    }

    final String schoolName = (school?['name'] ?? 'Unknown School').toString();
    final String? logoUrl = school?['logo_url'];

    return GestureDetector(
      onTap: openProfile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 18),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: PUi.surface(isDark),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isSelected ? schoolColor : PUi.border(isDark),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? schoolColor.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: isDark ? 0 : 0.05),
              blurRadius: isSelected ? 22 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // School band
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: PUi.tint(schoolColor, isDark, 0.09),
              child: Row(
                children: [
                  if (logoUrl != null)
                    ClipOval(
                      child: Image.network(
                        logoUrl,
                        height: 22,
                        width: 22,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.school_rounded,
                          size: 18,
                          color: schoolColor,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.school_rounded, size: 18, color: schoolColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schoolName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: schoolColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    school?['current_session'] ?? 'N/A',
                    style: TextStyle(
                      color: PUi.muted(isDark),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PAvatar(
                        initial: initial,
                        imageUrl: passport,
                        radius: 30,
                        ringColor: schoolColor,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$fName $lName",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                letterSpacing: -0.3,
                                color: PUi.ink(isDark),
                              ),
                            ),
                            const SizedBox(height: 8),
                            PPill(
                              text:
                                  "Class: ${child['class_level'] ?? 'Unassigned'}",
                              color: schoolColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: PUi.filledPill(schoolColor, height: 48),
                          onPressed: openProfile,
                          child: const Text("View Profile"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: "Contact admin",
                        onPressed: school == null
                            ? null
                            : () => _showContactAdminSheet(
                                context,
                                school,
                                isDark,
                                primaryColor,
                              ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: PUi.tint(schoolColor, isDark, 0.1),
                          shape: const CircleBorder(),
                        ),
                        icon: Icon(
                          Icons.support_agent_rounded,
                          color: schoolColor,
                          size: 22,
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
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = PUi.bg(isDark);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 900;
          final double listWidth = constraints.maxWidth >= 1250 ? 400 : 350;

          Widget wardsList = Container(
            width: isMobile ? double.infinity : listWidth,
            decoration: BoxDecoration(
              color: bgColor,
              border: isMobile
                  ? null
                  : Border(right: BorderSide(color: PUi.border(isDark))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("My Linked Wards", style: PUi.title(isDark, size: 30)),
                      const SizedBox(height: 8),
                      Text(
                        "Manage academic & financial records",
                        style: TextStyle(
                          color: PUi.muted(isDark),
                          fontSize: 14,
                        ),
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
                                    MediaQuery.of(context).size.height * 0.1,
                              ),
                              Center(
                                child: PEmptyState(
                                  title: "No children linked to your account yet.",
                                  accent: primaryColor,
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: widget.myChildren.length,
                            itemBuilder: (context, index) {
                              return _buildWardCard(
                                widget.myChildren[index],
                                isMobile,
                                isDark,
                                primaryColor,
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Scaffold(
              backgroundColor: bgColor,
              body: PBackdrop(accent: primaryColor, child: wardsList),
            );
          }

          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                wardsList,
                Expanded(
                  child: _selectedChild == null
                      ? Center(
                          child: PEmptyState(
                            title: "Select a ward to view records",
                            accent: primaryColor,
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
