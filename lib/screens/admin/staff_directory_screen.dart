import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_staff_screen.dart';
import 'staff_profile_screen.dart'; // Ensure this exists

class StaffDirectoryScreen extends StatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  State<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends State<StaffDirectoryScreen>
    with AuthErrorHandler {
  // 🚨 MIXED IN THE ERROR HANDLER
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
        // 🚨 REPLACED SNACKBAR WITH UNIVERSAL POPUP
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
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // ✅ ADDED DYNAMIC COLOR HERE
    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 EXTRACTED MAIN CONTENT FOR LAYOUT BUILDER
    Widget mainContent = Column(
      children: [
        // --- SEARCH BAR AREA ---
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          color: isDark ? bgColor : Colors.white,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Search name or role...",
              hintStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: primaryColor,
              ), // Dynamic!
              filled: true,
              fillColor: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // --- LIST AREA ---
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: primaryColor, // Dynamic!
                  child: _filteredList.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.3,
                            ),
                            _buildEmptyState(isDark),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _filteredList.length,
                          itemBuilder: (context, index) {
                            return _buildStaffCard(
                              _filteredList[index],
                              cardColor,
                              isDark,
                              primaryColor, // 🚨 Pass dynamic color here!
                            );
                          },
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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor, // Dynamic!
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained center column)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: mainContent,
                ),
              ),
            );
          } else {
            // 📱 MOBILE LAYOUT (Full Width)
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
          // If the add screen returns true (success), refresh the list
          if (result == true) {
            setState(() => _isLoading = true);
            _fetchStaff();
          }
        },
        backgroundColor: primaryColor, // Dynamic!
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

  // 🚨 Helper updated to accept primaryColor
  Widget _buildStaffCard(
    Map<String, dynamic> staff,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    final String id = staff['id'].toString(); // Used for Hero tag
    final String fullName = staff['full_name'] ?? "Unknown Staff";
    final String designation = staff['designation'] ?? "Staff Member";
    final String role = (staff['role'] ?? 'TEACHER').toString().toUpperCase();
    final String? passportUrl = staff['passport_url'];

    // 🚨 Make default 'Teacher' role use the Brand Color!
    Color roleColor = primaryColor;
    if (role == 'BURSAR') roleColor = Colors.green;
    if (role == 'PRINCIPAL') roleColor = Colors.purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffProfileScreen(staffData: staff),
              ),
            );
            // Refresh if the profile screen indicates a change (like a deletion)
            if (result == true) {
              setState(() => _isLoading = true);
              _fetchStaff();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Hero(
                  tag:
                      'staff_avatar_$id', // Ensure smooth transition to profile
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.1),
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
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        designation,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: roleColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isDark ? roleColor.withOpacity(0.8) : roleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
