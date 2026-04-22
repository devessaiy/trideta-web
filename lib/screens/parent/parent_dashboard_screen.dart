import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

// 🚨 CORRECTED IMPORTS
import 'package:trideta_v2/screens/auth/login_screen.dart'; // Solves AuthErrorHandler
import 'package:trideta_v2/screens/parent/parent_child_detail_screen.dart'; // Connects to the Modular Child Detail

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;
  int _currentIndex = 0;
  bool _isLoading = true;

  String _parentName = "Parent";
  String _parentEmail = "";
  String _primarySession = "N/A";

  List<Map<String, dynamic>> _myChildren = [];
  List<Map<String, dynamic>> _alerts = [];

  bool _showAlertBrief = true;

  @override
  void initState() {
    super.initState();
    _fetchParentData();
  }

  Future<void> _fetchParentData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      _parentEmail = user.email ?? "";

      // 1. Fetch Profile Name as a fallback
      final profile = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) _parentName = profile['full_name'] ?? "Parent";

      // 2. Fetch all children AND their respective school details
      final childrenData = await _supabase
          .from('students')
          .select(
            '*, schools(id, name, logo_url, contact_phone, contact_email, current_session)',
          )
          .eq('parent_email', _parentEmail);

      _myChildren = List<Map<String, dynamic>>.from(childrenData);

      if (_myChildren.isNotEmpty) {
        _primarySession = _myChildren[0]['schools']['current_session'] ?? "N/A";

        // 🚨 RBAC DUAL-ROLE FIX: Grab the actual Parent Name from the child's record!
        if (_myChildren[0]['parent_name'] != null &&
            _myChildren[0]['parent_name'].toString().isNotEmpty) {
          _parentName = _myChildren[0]['parent_name'];
        }
      }

      // 3. Fetch Alerts
      if (_myChildren.isNotEmpty) {
        List<String> schoolIds = _myChildren
            .map((c) => c['school_id'].toString())
            .toSet()
            .toList();
        try {
          final alertsData = await _supabase
              .from('alerts')
              .select('*, schools(name, logo_url)')
              .filter('school_id', 'in', schoolIds)
              .order('created_at', ascending: false);
          _alerts = List<Map<String, dynamic>>.from(alertsData);
        } catch (_) {}
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to load dashboard data. Check your internet connection.",
        );
      }
    }
  }

  Future<void> _launchContact(String type, String value) async {
    final Uri url = Uri(scheme: type, path: value);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open contact app.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color navBarColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    final List<Widget> pages = [
      _buildHomeTab(isDark, primaryColor),
      _buildWardsTab(isDark, primaryColor),
      _buildAlertsTab(isDark, primaryColor),
      _buildProfileTab(isDark, primaryColor),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: navBarColor,
        indicatorColor: primaryColor.withOpacity(0.1),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: primaryColor),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom, color: primaryColor),
            label: 'Wards',
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(
              Icons.notifications_active_rounded,
              color: primaryColor,
            ),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: primaryColor),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HOME TAB (Sleek Header & Briefing)
  // ===========================================================================

  Widget _buildHomeTab(bool isDark, Color primaryColor) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color subTextColor = isDark ? Colors.white70 : Colors.grey[600]!;

    return SafeArea(
      child: RefreshIndicator(
        color: primaryColor,
        onRefresh: _fetchParentData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildParentHeader(textColor, subTextColor, primaryColor),
              const SizedBox(height: 25),
              _buildSessionCard(primaryColor),
              const SizedBox(height: 30),

              if (_alerts.isNotEmpty && _showAlertBrief) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 30),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.campaign_rounded,
                      color: Colors.orange,
                    ),
                    title: const Text(
                      "New Alert Notification",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      _alerts[0]['title'] ??
                          'Check your alerts tab for recent updates.',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _showAlertBrief = false),
                    ),
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                ),
              ],

              Text(
                "DASHBOARD OVERVIEW",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.grey[500],
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickStatCard(
                      "My Wards",
                      _myChildren.length.toString(),
                      Icons.face_retouching_natural_rounded,
                      primaryColor,
                      cardColor,
                      1,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildQuickStatCard(
                      "Unread Alerts",
                      _alerts.length.toString(),
                      Icons.notifications_active_rounded,
                      Colors.orange,
                      cardColor,
                      2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParentHeader(
    Color textColor,
    Color subTextColor,
    Color primaryColor,
  ) {
    return Row(
      children: [
        Container(
          height: 65,
          width: 65,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
            ],
            border: Border.all(color: primaryColor.withOpacity(0.2), width: 2),
          ),
          child: Icon(Icons.person_rounded, color: primaryColor, size: 32),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(
                  fontSize: 14,
                  color: subTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _parentName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _parentEmail,
                style: TextStyle(fontSize: 13, color: subTextColor),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: Colors.white70,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                "CURRENT SESSION",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            _primarySession,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              "Parent Portal",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(
    String title,
    String val,
    IconData icon,
    Color color,
    Color cardColor,
    int targetTab,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = targetTab),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 15),
            Text(
              val,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. MY WARDS TAB
  // ===========================================================================

  Widget _buildWardsTab(bool isDark, Color primaryColor) {
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.family_restroom_rounded,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 15),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "My Linked Wards",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "Manage academic and financial records",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              color: primaryColor,
              onRefresh: _fetchParentData,
              child: _myChildren.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Icon(
                          Icons.face_retouching_off_rounded,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 15),
                        Center(
                          child: Text(
                            "No children linked to your account yet.",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _myChildren.length,
                      itemBuilder: (context, index) {
                        final child = _myChildren[index];
                        final school = child['schools'];
                        String fName = child['first_name'] ?? '';
                        String lName = child['last_name'] ?? '';
                        String initial = fName.isNotEmpty ? fName[0] : '?';
                        String passport = child['passport_url'] ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.05),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: primaryColor.withOpacity(0.1),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.white,
                                      backgroundImage:
                                          school['logo_url'] != null
                                          ? NetworkImage(school['logo_url'])
                                          : null,
                                      child: school['logo_url'] == null
                                          ? Icon(
                                              Icons.school,
                                              size: 12,
                                              color: primaryColor,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        school['name'] ?? 'Unknown School',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.all(15),
                                leading: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: primaryColor.withOpacity(
                                    0.1,
                                  ),
                                  backgroundImage: passport.isNotEmpty
                                      ? NetworkImage(passport)
                                      : null,
                                  child: passport.isEmpty
                                      ? Text(
                                          initial,
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  "$fName $lName",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                subtitle: Text(
                                  "Class: ${child['class_level']} • Session: ${school['current_session'] ?? 'N/A'}",
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  15,
                                  0,
                                  15,
                                  15,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          // 🚨 NAVIGATE TO THE MODULAR DETAIL SCREEN!
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ParentChildDetailScreen(
                                                    childData: child,
                                                  ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.analytics_outlined,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          "VIEW RECORD",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton(
                                      onPressed: () => _showContactAdminSheet(
                                        school,
                                        isDark,
                                        primaryColor,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.orange
                                            .withOpacity(0.1),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.support_agent_rounded,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContactAdminSheet(
    Map<String, dynamic> school,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Contact ${school['name']} Admin",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withOpacity(0.1),
                  child: const Icon(Icons.phone, color: Colors.green),
                ),
                title: const Text("Call School"),
                subtitle: Text(school['contact_phone'] ?? 'No phone provided'),
                onTap: school['contact_phone'] != null
                    ? () => _launchContact('tel', school['contact_phone'])
                    : null,
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  child: const Icon(Icons.email, color: Colors.blue),
                ),
                title: const Text("Email School"),
                subtitle: Text(school['contact_email'] ?? 'No email provided'),
                onTap: school['contact_email'] != null
                    ? () => _launchContact('mailto', school['contact_email'])
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 3. ALERTS TAB
  // ===========================================================================

  Widget _buildAlertsTab(bool isDark, Color primaryColor) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 15),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Notifications",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "Stay updated with school announcements",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              color: primaryColor,
              onRefresh: _fetchParentData,
              child: _alerts.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                        ),
                        Icon(
                          Icons.notifications_off_rounded,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 15),
                        Center(
                          child: Text(
                            "No new alerts from the school.",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _alerts.length,
                      itemBuilder: (ctx, i) {
                        final alert = _alerts[i];
                        final school = alert['schools'];

                        Color alertColor = primaryColor;
                        IconData icon = Icons.notifications;
                        String type = (alert['type'] ?? '')
                            .toString()
                            .toLowerCase();

                        if (type.contains('fee') ||
                            type.contains('finance') ||
                            type.contains('urgent')) {
                          alertColor = Colors.orange;
                          icon = Icons.account_balance_wallet;
                        } else if (type.contains('academic')) {
                          alertColor = Colors.blue;
                          icon = Icons.school;
                        }

                        return Card(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          margin: const EdgeInsets.only(bottom: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                              color: alertColor.withOpacity(0.3),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, color: alertColor, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        alert['title'] ?? 'Notice',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: alertColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  alert['message'] ?? '',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      school['name'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      alert['created_at'] != null
                                          ? DateFormat(
                                              'MMM dd, hh:mm a',
                                            ).format(
                                              DateTime.parse(
                                                alert['created_at'],
                                              ),
                                            )
                                          : '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
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
  }

  Widget _buildProfileTab(bool isDark, Color primaryColor) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 30),
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: primaryColor.withOpacity(0.1),
              child: Icon(Icons.person, size: 50, color: primaryColor),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              _parentName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              "Parent Account",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 40),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Secure Logout",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () async {
              bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Logout"),
                  content: const Text("Are you sure you want to log out?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        "Logout",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _supabase.auth.signOut();
                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
