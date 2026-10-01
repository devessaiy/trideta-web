import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/school_master_details_screen.dart';

class OwnerNotificationsView extends StatefulWidget {
  const OwnerNotificationsView({super.key});

  @override
  State<OwnerNotificationsView> createState() => _OwnerNotificationsViewState();
}

class _OwnerNotificationsViewState extends State<OwnerNotificationsView> {
  final _supabase = Supabase.instance.client;

  String _typeFilter = "all";
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _hasError = false;

  static const Map<String, String> _typeLabels = {
    'new_school': 'New Schools',
    'new_student': 'New Students',
    'new_parent': 'New Parents',
    'subscription_expiring_soon': 'Expiring Soon',
    'subscription_expired': 'Expired',
  };

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('admin_notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(200);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _hasError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Notifications Fetch Error: $e");
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_typeFilter == 'all') return _notifications;
    return _notifications.where((n) => n['type'] == _typeFilter).toList();
  }

  int get _unreadCount => _notifications.where((n) => n['is_read'] != true).length;

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) return;
    setState(() => notification['is_read'] = true); // optimistic
    try {
      await _supabase.from('admin_notifications').update({'is_read': true}).eq('id', notification['id']);
    } catch (e) {
      debugPrint("Mark read failed: $e");
      if (mounted) setState(() => notification['is_read'] = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final unreadIds = _notifications.where((n) => n['is_read'] != true).map((n) => n['id']).toList();
    if (unreadIds.isEmpty) return;

    setState(() {
      for (var n in _notifications) {
        n['is_read'] = true;
      }
    });
    try {
      await _supabase.from('admin_notifications').update({'is_read': true}).inFilter('id', unreadIds);
    } catch (e) {
      debugPrint("Mark all read failed: $e");
      _fetchNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final filtered = _filtered;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text("Mark all read", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildFilterChip("All", "all", isDark, textColor, primaryColor),
                    ..._typeLabels.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: _buildFilterChip(e.value, e.key, isDark, textColor, primaryColor),
                        )),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading && _notifications.isEmpty
                  ? Center(child: TridetaLoader(color: primaryColor))
                  : _hasError && _notifications.isEmpty
                      ? Center(child: Text("Failed to load notifications.", style: TextStyle(color: textColor)))
                      : RefreshIndicator(
                          onRefresh: _fetchNotifications,
                          color: primaryColor,
                          child: filtered.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height: MediaQuery.of(context).size.height * 0.5,
                                      child: Center(
                                        child: Text("No notifications here.",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.only(top: 4, bottom: 40),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) =>
                                      _buildNotificationTile(filtered[index], isDark, textColor, cardColor),
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notification, bool isDark, Color textColor, Color cardColor) {
    final type = notification['type'] as String;
    final isUnread = notification['is_read'] != true;
    final date = DateTime.parse(notification['created_at']).toLocal();

    IconData icon;
    Color color;
    switch (type) {
      case 'new_school':
        icon = Icons.domain_add_rounded;
        color = Colors.blue;
        break;
      case 'new_student':
        icon = Icons.person_add_alt_1_rounded;
        color = Colors.green;
        break;
      case 'new_parent':
        icon = Icons.family_restroom_rounded;
        color = Colors.purple;
        break;
      case 'subscription_expiring_soon':
        icon = Icons.timer_rounded;
        color = Colors.orange;
        break;
      case 'subscription_expired':
        icon = Icons.error_rounded;
        color = Colors.red;
        break;
      default:
        icon = Icons.notifications_rounded;
        color = Colors.grey;
    }

    return Column(
      children: [
        Material(
          color: isUnread ? color.withValues(alpha: 0.04) : Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            leading: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (isUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: cardColor, width: 2)),
                    ),
                  ),
              ],
            ),
            title: Text(
              notification['title'] ?? '',
              style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, fontSize: 14, color: textColor),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification['body'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM dd, yyyy • hh:mm a').format(date),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                ],
              ),
            ),
            isThreeLine: true,
            onTap: () {
              _markAsRead(notification);
              if (notification['school_id'] != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SchoolMasterDetailsScreen(school: {'id': notification['school_id']}),
                  ),
                );
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 88, right: 24),
          child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark, Color textColor, Color primaryColor) {
    bool isSelected = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.1) : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? primaryColor : (isDark ? Colors.white24 : Colors.grey.shade300), width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? primaryColor : (isDark ? Colors.white70 : Colors.grey.shade600),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
