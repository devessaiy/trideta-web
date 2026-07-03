import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class SchoolMasterDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> school;

  const SchoolMasterDetailsScreen({super.key, required this.school});

  Future<void> _launchUrl(String scheme, String path) async {
    final Uri url = Uri(scheme: scheme, path: path);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchMaps(String? address) async {
    if (address == null || address.isEmpty) return;
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    final String schoolId = school['id'];
    final String name = school['name'] ?? 'Unknown School';
    final String acronym = school['acronym'] ?? '';
    final String? address = school['address'];
    final String? phone = school['contact_phone'];
    final String? email = school['contact_email'];
    final String status = school['subscription_status'] ?? 'active';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          name,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER & QUICK CONTACT ACTIONS
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: primaryColor.withValues(alpha: 0.1),
                        backgroundImage: school['logo_url'] != null
                            ? NetworkImage(school['logo_url'])
                            : null,
                        child: school['logo_url'] == null
                            ? Icon(Icons.domain, size: 30, color: primaryColor)
                            : null,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acronym,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'active'
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: status == 'active'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickAction(
                        Icons.phone,
                        "Call",
                        () => _launchUrl('tel', phone ?? ''),
                      ),
                      _buildQuickAction(
                        Icons.email,
                        "Email",
                        () => _launchUrl('mailto', email ?? ''),
                      ),
                      _buildQuickAction(
                        Icons.directions,
                        "Navigate",
                        () => _launchMaps(address),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. ADDRESS DISPLAY
            if (address != null && address.isNotEmpty) ...[
              Text(
                "LOCATION",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: Colors.redAccent.shade200,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(
                          fontSize: 15,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],

            // 3. POPULATION & ENGAGEMENT MATRIX
            Text(
              "ENGAGEMENT MATRIX",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade500,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildCountStreamCard(
                    context,
                    "Students",
                    Icons.school,
                    Supabase.instance.client
                        .from('students')
                        .stream(primaryKey: ['id'])
                        .map(
                          (data) => data
                              .where((d) => d['school_id'] == schoolId)
                              .toList(),
                        ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCountStreamCard(
                    context,
                    "Parents",
                    Icons.family_restroom,
                    Supabase.instance.client
                        .from('profiles')
                        .stream(primaryKey: ['id'])
                        .map(
                          (data) => data
                              .where(
                                (d) =>
                                    d['school_id'] == schoolId &&
                                    d['role'] == 'parent',
                              )
                              .toList(),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCountStreamCard(
                    context,
                    "Teachers",
                    Icons.badge,
                    Supabase.instance.client
                        .from('profiles')
                        .stream(primaryKey: ['id'])
                        .map(
                          (data) => data
                              .where(
                                (d) =>
                                    d['school_id'] == schoolId &&
                                    d['role'] == 'teacher',
                              )
                              .toList(),
                        ),
                  ),
                ),
                const SizedBox(width: 16),

                // 🚨 FIXED: Safe Dart mapping to handle multiple roles instead of .inFilter
                Expanded(
                  child: _buildCountStreamCard(
                    context,
                    "Admins & Bursars",
                    Icons.admin_panel_settings,
                    Supabase.instance.client
                        .from('profiles')
                        .stream(primaryKey: ['id'])
                        .map(
                          (profiles) => profiles
                              .where(
                                (p) =>
                                    p['school_id'] == schoolId &&
                                    (p['role'] == 'Admin' ||
                                        p['role'] == 'bursar'),
                              )
                              .toList(),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // 4. FEEDBACK & REPORTS LOG
            Text(
              "SCHOOL REPORTS & FEEDBACK",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade500,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('school_feedbacks')
                    .stream(primaryKey: ['id'])
                    .eq('school_id', schoolId)
                    .order('created_at'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: TridetaLoader()),
                    );

                  final feedbacks = snapshot.data ?? [];
                  if (feedbacks.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "No pending reports from this school.",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: feedbacks.length,
                    separatorBuilder: (_, _) => Divider(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final feedback = feedbacks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: feedback['status'] == 'pending'
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.green.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.support_agent,
                            color: feedback['status'] == 'pending'
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                        title: Text(
                          feedback['subject'] ?? 'No Subject',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "${feedback['sender_role'].toString().toUpperCase()} • ${feedback['message']}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade400,
                        ),
                        onTap: () {
                          // Room to add full message popup
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.blueAccent),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountStreamCard(
    BuildContext context,
    String title,
    IconData icon,
    Stream<List<Map<String, dynamic>>> stream,
  ) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 28),
          const SizedBox(height: 15),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              return Text(
                snapshot.data!.length.toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.0,
                ),
              );
            },
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
