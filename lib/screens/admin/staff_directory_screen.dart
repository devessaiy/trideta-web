import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🚨 FIX: Restored the proper connection to the actual Staff Profile screen!
import 'add_staff_screen.dart';
import 'staff_profile_screen.dart';

class StaffDirectoryScreen extends StatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  State<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends State<StaffDirectoryScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _filteredList = [];

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchStaff();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredList = _staffList.where((s) {
        final name = (s['full_name'] ?? "").toString().toLowerCase();
        final role = (s['designation'] ?? "").toString().toLowerCase();
        return name.contains(query) || role.contains(query);
      }).toList();
    });
  }

  Future<void> _fetchStaff() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      final schoolId = profile['school_id'];

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('school_id', schoolId)
          .neq('role', 'Admin')
          .order('full_name');

      if (mounted) {
        setState(() {
          _staffList = List<Map<String, dynamic>>.from(data);
          _filteredList = _staffList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "We couldn't load the staff directory. Please check your connection and try again.",
        );
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchStaff();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium matte backgrounds
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;

    Widget mainContent = Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          color: bgColor,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Search name or role...",
              hintStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.grey[400],
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade200,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        Expanded(
          child: _isLoading
              ? Center(child: TridetaLoader(color: primaryColor))
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: primaryColor,
                  child: _filteredList.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3,
                            ),
                            _buildEmptyState(isDark),
                          ],
                        )
                      : Container(
                          color: bgColor,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) {
                              return _buildStaffCard(
                                _filteredList[index],
                                isDark,
                                primaryColor,
                              );
                            },
                          ),
                        ),
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Staff Directory",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            return mainContent;
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddStaffScreen()),
          );
          if (result == true) {
            setState(() => _isLoading = true);
            _fetchStaff();
          }
        },
        backgroundColor: primaryColor,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text(
          "NEW STAFF",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[300],
          ),
          const SizedBox(height: 15),
          Text(
            "No staff members found",
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(
    Map<String, dynamic> staff,
    bool isDark,
    Color primaryColor,
  ) {
    final String id = staff['id'].toString();
    final String fullName = staff['full_name'] ?? "Unknown Staff";
    final String designation = staff['designation'] ?? "Staff Member";
    final String role = (staff['role'] ?? 'TEACHER').toString().toUpperCase();
    final String? passportUrl = staff['passport_url'];

    Color roleColor = primaryColor;
    if (role == 'BURSAR') roleColor = Colors.green;
    if (role == 'PRINCIPAL') roleColor = Colors.purple;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StaffProfileScreen(staffData: staff),
                ),
              );
              if (result == true) {
                setState(() => _isLoading = true);
                _fetchStaff();
              }
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: Hero(
                tag: 'staff_avatar_$id',
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    image: passportUrl != null
                        ? DecorationImage(
                            image: NetworkImage(passportUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: passportUrl == null
                      ? Center(
                          child: Text(
                            fullName.isNotEmpty
                                ? fullName[0].toUpperCase()
                                : "?",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: roleColor,
                              fontSize: 20,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              title: Text(
                fullName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  designation,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey[600],
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 89, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }
}
