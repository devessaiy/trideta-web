import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_settings_view.dart';

class OwnerMetricsView extends StatefulWidget {
  final Function(int) onNavigate;

  const OwnerMetricsView({super.key, required this.onNavigate});

  @override
  State<OwnerMetricsView> createState() => _OwnerMetricsViewState();
}

class _OwnerMetricsViewState extends State<OwnerMetricsView> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  int _activeSchoolsCount = 0;
  int _totalStudentsCount = 0;
  int _totalProfilesCount = 0;

  List<Map<String, dynamic>> _activityFeed = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // 🚨 STABLE FETCH ENGINE: Grabs metrics and recent actions securely without streams
  Future<void> _fetchDashboardData() async {
    if (mounted && !_isLoading) setState(() => _isLoading = true);

    try {
      // 1. Fetch Performance Counts
      final activeSchoolsData = await _supabase
          .from('schools')
          .select('id')
          .eq('subscription_status', 'active');
      final studentsData = await _supabase.from('students').select('id');
      final profilesData = await _supabase.from('profiles').select('id');

      // 2. Fetch Recent Activities (Top 5 of each)
      final recentSchools = await _supabase
          .from('schools')
          .select('id, name, created_at')
          .order('created_at', ascending: false)
          .limit(5);

      final recentStudents = await _supabase
          .from('students')
          .select('id, first_name, last_name, school_id, created_at')
          .order('created_at', ascending: false)
          .limit(5);

      final recentProfiles = await _supabase
          .from('profiles')
          .select('id, full_name, role, school_id, created_at')
          .order('created_at', ascending: false)
          .limit(5);

      // 3. Map School IDs to Names for the Feed
      final allSchoolsMap = <String, String>{};
      final allSchools = await _supabase.from('schools').select('id, name');
      for (var s in allSchools) {
        allSchoolsMap[s['id'].toString()] = s['name'].toString();
      }

      // 4. Combine into a unified feed
      List<Map<String, dynamic>> combinedActivities = [];

      for (var s in recentSchools) {
        combinedActivities.add({
          'type': 'school',
          'title': 'New School Registered',
          'subtitle': s['name'] ?? 'Unknown School',
          'date': DateTime.parse(s['created_at']).toLocal(),
          'icon': Icons.domain_add_rounded,
          'color': Colors.blue,
        });
      }

      for (var s in recentStudents) {
        String sName =
            allSchoolsMap[s['school_id']?.toString()] ?? 'Unknown School';
        combinedActivities.add({
          'type': 'student',
          'title': 'New Student Registered',
          'subtitle':
              '${s['first_name'] ?? ''} ${s['last_name'] ?? ''} joined $sName',
          'date': DateTime.parse(s['created_at']).toLocal(),
          'icon': Icons.person_add_alt_1_rounded,
          'color': Colors.green,
        });
      }

      for (var p in recentProfiles) {
        String sName =
            allSchoolsMap[p['school_id']?.toString()] ?? 'Unknown School';
        String role = (p['role'] ?? 'User').toString().toUpperCase();
        combinedActivities.add({
          'type': 'staff',
          'title': 'New $role Added',
          'subtitle': '${p['full_name'] ?? 'Unknown'} joined $sName',
          'date': DateTime.parse(p['created_at']).toLocal(),
          'icon': Icons.badge_rounded,
          'color': Colors.purple,
        });
      }

      // Sort combined feed by newest first
      combinedActivities.sort((a, b) => b['date'].compareTo(a['date']));

      if (mounted) {
        setState(() {
          _activeSchoolsCount = activeSchoolsData.length;
          _totalStudentsCount = studentsData.length;
          _totalProfilesCount = profilesData.length;
          _activityFeed = combinedActivities.take(15).toList(); // Keep top 15
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 25, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildAdminHeader(context, textColor, primaryColor),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildPerformanceCard(primaryColor),
              ),
              const SizedBox(height: 35),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "RECENT PLATFORM ACTIVITY",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              if (_isLoading && _activityFeed.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: TridetaLoader(color: primaryColor)),
                )
              else if (_activityFeed.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      "No recent activities found.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _activityFeed.length,
                  itemBuilder: (context, index) {
                    final activity = _activityFeed[index];
                    return _buildActivityTile(
                      isDark: isDark,
                      icon: activity['icon'],
                      color: activity['color'],
                      title: activity['title'],
                      subtitle: activity['subtitle'],
                      date: activity['date'],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 🚨 UI FIX: Relocated Settings icon securely to the top right of the Home view
  Widget _buildAdminHeader(
    BuildContext context,
    Color textColor,
    Color primaryColor,
  ) {
    return Row(
      children: [
        Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.verified_user_rounded,
            color: primaryColor,
            size: 28,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "App Owner",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "Trideta Master Console",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OwnerSettingsView()),
            );
          },
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.settings_rounded, color: primaryColor),
          ),
        ),
      ],
    );
  }

  // 🚨 UI FIX: Upgraded to real-time performance tracking
  Widget _buildPerformanceCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withValues(alpha: 0.9), primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.public, color: Colors.white70, size: 16),
                    SizedBox(width: 8),
                    Text(
                      "LIVE NETWORK STATUS",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem(
                      "Active Schools",
                      _activeSchoolsCount.toString(),
                    ),
                    _buildStatItem(
                      "Global Load",
                      _totalStudentsCount.toString(),
                    ),
                    _buildStatItem(
                      "Total Staff",
                      _totalProfilesCount.toString(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 🚨 UI FIX: Flattened WhatsApp-style feed
  Widget _buildActivityTile({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required DateTime date,
  }) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    String timeAgo = _getTimeAgo(date);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
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
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 80, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }

  String _getTimeAgo(DateTime date) {
    Duration diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return DateFormat('MMM dd, yyyy').format(date);
    if (diff.inDays > 0) return "${diff.inDays} days ago";
    if (diff.inHours > 0) return "${diff.inHours} hours ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes} minutes ago";
    return "Just now";
  }
}
