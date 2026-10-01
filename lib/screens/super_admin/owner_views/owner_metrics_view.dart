import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_settings_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/owner_notifications_view.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/school_master_details_screen.dart';

// In-memory snapshot so switching tabs does not hit the backend again.
// Only pull-to-refresh (or returning from a sub-screen) fetches fresh data.
Map<String, dynamic>? _ownerMetricsCache;
String? _ownerMetricsCacheUser;

class OwnerMetricsView extends StatefulWidget {
  final Function(int) onNavigate;

  const OwnerMetricsView({super.key, required this.onNavigate});

  @override
  State<OwnerMetricsView> createState() => _OwnerMetricsViewState();
}

class _OwnerMetricsViewState extends State<OwnerMetricsView> {
  final _supabase = Supabase.instance.client;
  final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

  bool _isLoading = true;

  int _totalSchools = 0;
  int _activeCount = 0;
  int _pausedCount = 0;
  int _terminatedCount = 0;
  int _freeGrantedCount = 0;

  double _totalRevenue = 0;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _expiringSoon = [];
  List<Map<String, dynamic>> _recentPayments = [];
  List<Map<String, dynamic>> _activityFeed = [];

  @override
  void initState() {
    super.initState();
    if (!_restoreFromCache()) _fetchDashboardData();
  }

  bool _restoreFromCache() {
    final c = _ownerMetricsCache;
    if (c == null ||
        _ownerMetricsCacheUser != _supabase.auth.currentUser?.id) {
      return false;
    }
    _totalSchools = c['totalSchools'];
    _activeCount = c['activeCount'];
    _pausedCount = c['pausedCount'];
    _terminatedCount = c['terminatedCount'];
    _freeGrantedCount = c['freeGrantedCount'];
    _totalRevenue = c['totalRevenue'];
    _unreadNotifications = c['unreadNotifications'];
    _expiringSoon = c['expiringSoon'];
    _recentPayments = c['recentPayments'];
    _activityFeed = c['activityFeed'];
    _isLoading = false;
    return true;
  }

  Future<void> _fetchDashboardData() async {
    if (mounted && !_isLoading) setState(() => _isLoading = true);

    try {
      // 1. Schools + subscription snapshot
      final schoolsData = await _supabase
          .from('schools')
          .select(
            'id, name, acronym, subscription_status, subscription_tier, '
            'is_free_granted, subscription_expiry_date, logo_url, created_at',
          )
          .order('created_at', ascending: false);

      final schools = List<Map<String, dynamic>>.from(schoolsData);

      int active = 0, paused = 0, terminated = 0, free = 0;
      List<Map<String, dynamic>> expiring = [];
      final now = DateTime.now();

      for (var s in schools) {
        final status = s['subscription_status'] ?? 'active';
        final isFree = s['is_free_granted'] == true;
        if (status == 'active') active++;
        if (status == 'paused_payment') paused++;
        if (status == 'terminated') terminated++;
        if (isFree) free++;

        if (status == 'active' &&
            !isFree &&
            s['subscription_tier'] != 'tier_1' &&
            s['subscription_expiry_date'] != null) {
          final expiry = DateTime.tryParse(s['subscription_expiry_date']);
          if (expiry != null) {
            final daysLeft = expiry.difference(now).inDays;
            if (daysLeft <= 14) {
              expiring.add({...s, '_daysLeft': daysLeft});
            }
          }
        }
      }
      expiring.sort((a, b) => a['_daysLeft'].compareTo(b['_daysLeft']));

      // 1b. Unread notifications badge count
      final unreadData = await _supabase.from('admin_notifications').select('id').eq('is_read', false);
      final unreadCount = unreadData.length;

      // 2. Payments - recent + total revenue
      final paymentsData = await _supabase
          .from('school_subscription_payments')
          .select('school_id, amount_paid, tier_paid_for, provider, created_at')
          .eq('status', 'success')
          .order('created_at', ascending: false)
          .limit(200);

      final payments = List<Map<String, dynamic>>.from(paymentsData);
      double revenue = 0;
      for (var p in payments) {
        revenue += (p['amount_paid'] as num?)?.toDouble() ?? 0;
      }

      final schoolNameMap = <String, String>{
        for (var s in schools) s['id'].toString(): s['name'] ?? 'Unknown School',
      };
      final recentPayments = payments.take(5).map((p) {
        return {
          ...p,
          'school_name': schoolNameMap[p['school_id']?.toString()] ?? 'Unknown School',
        };
      }).toList();

      // 3. Recent platform activity feed (schools/students/staff)
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

      List<Map<String, dynamic>> combined = [];

      for (var s in schools.take(5)) {
        combined.add({
          'title': 'New School Registered',
          'subtitle': s['name'] ?? 'Unknown School',
          'date': DateTime.parse(s['created_at']).toLocal(),
          'icon': Icons.domain_add_rounded,
          'color': Colors.blue,
        });
      }
      for (var s in recentStudents) {
        String sName = schoolNameMap[s['school_id']?.toString()] ?? 'Unknown School';
        combined.add({
          'title': 'New Student Registered',
          'subtitle': '${s['first_name'] ?? ''} ${s['last_name'] ?? ''} joined $sName',
          'date': DateTime.parse(s['created_at']).toLocal(),
          'icon': Icons.person_add_alt_1_rounded,
          'color': Colors.green,
        });
      }
      for (var p in recentProfiles) {
        String sName = schoolNameMap[p['school_id']?.toString()] ?? 'Unknown School';
        String role = (p['role'] ?? 'User').toString().toUpperCase();
        combined.add({
          'title': 'New $role Added',
          'subtitle': '${p['full_name'] ?? 'Unknown'} joined $sName',
          'date': DateTime.parse(p['created_at']).toLocal(),
          'icon': Icons.badge_rounded,
          'color': Colors.purple,
        });
      }
      combined.sort((a, b) => b['date'].compareTo(a['date']));

      _ownerMetricsCacheUser = _supabase.auth.currentUser?.id;
      _ownerMetricsCache = {
        'totalSchools': schools.length,
        'activeCount': active,
        'pausedCount': paused,
        'terminatedCount': terminated,
        'freeGrantedCount': free,
        'totalRevenue': revenue,
        'unreadNotifications': unreadCount,
        'expiringSoon': expiring.take(5).toList(),
        'recentPayments': recentPayments,
        'activityFeed': combined.take(15).toList(),
      };

      if (mounted) {
        setState(() {
          _totalSchools = schools.length;
          _activeCount = active;
          _pausedCount = paused;
          _terminatedCount = terminated;
          _freeGrantedCount = free;
          _totalRevenue = revenue;
          _unreadNotifications = unreadCount;
          _expiringSoon = expiring.take(5).toList();
          _recentPayments = recentPayments;
          _activityFeed = combined.take(15).toList();
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
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: primaryColor,
        child: _isLoading && _totalSchools == 0
            ? Center(child: TridetaLoader(color: primaryColor))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 25, bottom: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildAdminHeader(context, textColor, primaryColor),
                    ),
                    const SizedBox(height: 24),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildRevenueCard(primaryColor),
                    ),
                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 112,
                        ),
                        children: [
                          _buildStatCard("Total Schools", _totalSchools.toString(),
                              Icons.domain_rounded, Colors.blueGrey, cardColor, textColor),
                          _buildStatCard("Active & Paid", _activeCount.toString(),
                              Icons.verified_rounded, Colors.green, cardColor, textColor),
                          _buildStatCard("Paused (Owing)", _pausedCount.toString(),
                              Icons.pause_circle_filled_rounded, Colors.orange, cardColor, textColor),
                          _buildStatCard("Terminated", _terminatedCount.toString(),
                              Icons.block_rounded, Colors.red, cardColor, textColor),
                        ],
                      ),
                    ),

                    if (_freeGrantedCount > 0) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.card_giftcard_rounded, color: Colors.teal, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                "$_freeGrantedCount school${_freeGrantedCount == 1 ? '' : 's'} on Free/Granted access",
                                style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (_expiringSoon.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          "EXPIRING SOON",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._expiringSoon.map((s) => _buildExpiringTile(s, isDark, textColor)),
                    ],

                    if (_recentPayments.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          "RECENT PAYMENTS",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._recentPayments.map((p) => _buildPaymentTile(p, isDark, textColor)),
                    ],

                    const SizedBox(height: 30),
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
                    if (_activityFeed.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text("No recent activities found.", style: TextStyle(color: Colors.grey)),
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

  Widget _buildAdminHeader(BuildContext context, Color textColor, Color primaryColor) {
    return Row(
      children: [
        Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: primaryColor.withValues(alpha: 0.2), width: 2),
          ),
          child: Icon(Icons.verified_user_rounded, color: primaryColor, size: 28),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                "Trideta Master Console",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerNotificationsView()))
                .then((_) => _fetchDashboardData());
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.notifications_rounded, color: primaryColor),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      _unreadNotifications > 9 ? "9+" : _unreadNotifications.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerSettingsView()));
          },
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.settings_rounded, color: primaryColor),
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueCard(Color primaryColor) {
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
          BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: CircleAvatar(radius: 70, backgroundColor: Colors.white.withValues(alpha: 0.1)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 16),
                    SizedBox(width: 8),
                    Text(
                      "TOTAL REVENUE COLLECTED",
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  currencyFormat.format(_totalRevenue),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem("Active", _activeCount.toString()),
                    _buildStatItem("Free/Granted", _freeGrantedCount.toString()),
                    _buildStatItem("Expiring Soon", _expiringSoon.length.toString()),
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
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon, Color color, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildExpiringTile(Map<String, dynamic> school, bool isDark, Color textColor) {
    final daysLeft = school['_daysLeft'] as int;
    final label = daysLeft < 0
        ? "Expired ${-daysLeft}d ago"
        : daysLeft == 0
            ? "Expires today"
            : "$daysLeft day${daysLeft == 1 ? '' : 's'} left";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Material(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: const Icon(Icons.timer_rounded, color: Colors.orange),
          title: Text(school['name'] ?? 'Unknown School', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          subtitle: Text((school['subscription_tier'] ?? '').toString().toUpperCase(),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          trailing: Text(label, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SchoolMasterDetailsScreen(school: school)),
            ).then((_) => _fetchDashboardData());
          },
        ),
      ),
    );
  }

  Widget _buildPaymentTile(Map<String, dynamic> payment, bool isDark, Color textColor) {
    DateTime date = DateTime.parse(payment['created_at']).toLocal();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: const Icon(Icons.arrow_downward_rounded, color: Colors.green, size: 18),
      ),
      title: Text(currencyFormat.format(payment['amount_paid'] ?? 0),
          style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
      subtitle: Text("${payment['school_name']} • ${(payment['tier_paid_for'] ?? '').toString().toUpperCase()}",
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      trailing: Text(DateFormat('MMM dd').format(date),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
    );
  }

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
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor, letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey.shade600, height: 1.3)),
                      const SizedBox(height: 8),
                      Text(timeAgo, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 80, right: 24),
          child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
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
