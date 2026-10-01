import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class OwnerProfilesManagementView extends StatefulWidget {
  const OwnerProfilesManagementView({super.key});

  @override
  State<OwnerProfilesManagementView> createState() => _OwnerProfilesManagementViewState();
}

class _OwnerProfilesManagementViewState extends State<OwnerProfilesManagementView> {
  final _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _roleFilter = "all";
  String _statusFilter = "all"; // all | active | suspended

  static const int _pageSize = 20;
  int _currentPage = 0;

  List<Map<String, dynamic>> _profiles = [];
  Map<String, String> _schoolNames = {};
  bool _isLoading = true;
  bool _hasError = false;
  String? _actioningProfileId;

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfiles() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final data = await _supabase.from('profiles').select().order('created_at', ascending: false);
      final schoolsData = await _supabase.from('schools').select('id, name');

      final nameMap = <String, String>{for (var s in schoolsData) s['id'].toString(): s['name'] ?? 'Unknown School'};

      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(data);
          _schoolNames = nameMap;
          _hasError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Profiles Fetch Error: $e");
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  List<String> get _availableRoles {
    final roles = _profiles.map((p) => (p['role'] ?? '').toString()).where((r) => r.isNotEmpty).toSet().toList();
    roles.sort();
    return roles;
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    List<Map<String, dynamic>> list = List.from(_profiles);

    if (_searchQuery.isNotEmpty) {
      list = list.where((p) {
        final name = (p['full_name'] ?? '').toString().toLowerCase();
        final email = (p['email'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || email.contains(_searchQuery);
      }).toList();
    }

    if (_roleFilter != 'all') {
      list = list.where((p) => (p['role'] ?? '').toString() == _roleFilter).toList();
    }

    if (_statusFilter == 'active') {
      list = list.where((p) => p['is_suspended'] != true).toList();
    } else if (_statusFilter == 'suspended') {
      list = list.where((p) => p['is_suspended'] == true).toList();
    }

    return list;
  }

  Future<void> _confirmAndToggleSuspend(Map<String, dynamic> profile) async {
    final isSuspended = profile['is_suspended'] == true;
    final name = profile['full_name'] ?? 'this user';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isSuspended ? "Restore $name?" : "Suspend $name?"),
        content: Text(
          isSuspended
              ? "This will restore their access to log in and use the app normally."
              : "This will immediately block them from logging in. Their data is preserved.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: isSuspended ? Colors.green : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSuspended ? "Restore" : "Suspend"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actioningProfileId = profile['id'].toString());
    try {
      await _supabase.from('profiles').update({'is_suspended': !isSuspended}).eq('id', profile['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isSuspended ? "$name restored" : "$name suspended"), backgroundColor: Colors.green),
        );
      }
      await _fetchProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _actioningProfileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    final filtered = _filteredProfiles;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 999999);
    final pageStart = _currentPage * _pageSize;
    final pageItems = filtered.skip(pageStart).take(_pageSize).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              "Global Directory",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() { _searchQuery = value.toLowerCase(); _currentPage = 0; }),
              decoration: InputDecoration(
                hintText: "Search name or email...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () { _searchController.clear(); setState(() { _searchQuery = ""; _currentPage = 0; }); },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildChip("All Roles", "all", Colors.indigo, isDark, isRole: true),
                  ..._availableRoles.map((r) => Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _buildChip(r.toUpperCase(), r, Colors.indigo, isDark, isRole: true),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildChip("All Status", "all", Colors.grey, isDark, isRole: false),
                const SizedBox(width: 10),
                _buildChip("Active", "active", Colors.green, isDark, isRole: false),
                const SizedBox(width: 10),
                _buildChip("Suspended", "suspended", Colors.red, isDark, isRole: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading && _profiles.isEmpty
                ? Center(child: TridetaLoader(color: primaryColor))
                : _hasError && _profiles.isEmpty
                    ? const Center(child: Text("Failed to load profiles."))
                    : RefreshIndicator(
                        onRefresh: _fetchProfiles,
                        color: primaryColor,
                        child: filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    child: const Center(
                                      child: Text("No profiles match this filter.",
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 8, bottom: 8),
                                itemCount: pageItems.length,
                                itemBuilder: (context, index) => _buildProfileTile(pageItems[index], isDark, textColor),
                              ),
                      ),
          ),
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                  ),
                  Text("Page ${_currentPage + 1} of $totalPages",
                      style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget _buildProfileTile(Map<String, dynamic> profile, bool isDark, Color textColor) {
    final isSuspended = profile['is_suspended'] == true;
    final schoolId = profile['school_id']?.toString();
    final schoolName = schoolId != null ? (_schoolNames[schoolId] ?? 'Unknown School') : null;
    final isActioning = _actioningProfileId == profile['id'].toString();

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
              backgroundImage: profile['passport_url'] != null ? NetworkImage(profile['passport_url']) : null,
              child: profile['passport_url'] == null ? Icon(Icons.person, color: Colors.grey.shade400) : null,
            ),
            title: Text(
              profile['full_name'] ?? 'No Name',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isSuspended ? Colors.grey.shade500 : textColor,
                decoration: isSuspended ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text("${(profile['role'] ?? '').toString().toUpperCase()} • ${profile['email'] ?? ''}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (schoolName == null ? Colors.blueGrey : Colors.indigo).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      schoolName ?? 'No School',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: schoolName == null ? Colors.blueGrey : Colors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            trailing: isActioning
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(
                      isSuspended ? Icons.restore_rounded : Icons.block_rounded,
                      color: isSuspended ? Colors.green : Colors.red,
                    ),
                    onPressed: () => _confirmAndToggleSuspend(profile),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 88, right: 24),
          child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ],
    );
  }

  Widget _buildChip(String label, String value, Color color, bool isDark, {required bool isRole}) {
    bool isSelected = isRole ? _roleFilter == value : _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() {
        if (isRole) {
          _roleFilter = value;
        } else {
          _statusFilter = value;
        }
        _currentPage = 0;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : (isDark ? Colors.white24 : Colors.grey.shade300), width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : (isDark ? Colors.white70 : Colors.grey.shade600),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
