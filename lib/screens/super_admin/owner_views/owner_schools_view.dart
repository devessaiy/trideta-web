import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/school_master_details_screen.dart';

class OwnerSchoolsManagementView extends StatefulWidget {
  const OwnerSchoolsManagementView({super.key});

  @override
  State<OwnerSchoolsManagementView> createState() => _OwnerSchoolsManagementViewState();
}

class _OwnerSchoolsManagementViewState extends State<OwnerSchoolsManagementView> {
  final _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter = "all"; // all | active | paused_payment | terminated | free_granted
  String _sortBy = "recent"; // recent | name | expiry

  static const int _pageSize = 20;
  int _currentPage = 0;

  List<Map<String, dynamic>> _allSchools = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSchools() async {
    if (mounted && !_isLoading) setState(() => _isLoading = true);
    try {
      final data = await _supabase.from('schools').select('*').order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allSchools = List<Map<String, dynamic>>.from(data);
          _hasError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Schools Fetch Error: $e");
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get _filteredSchools {
    List<Map<String, dynamic>> list = List.from(_allSchools);

    if (_searchQuery.isNotEmpty) {
      list = list.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final acronym = (s['acronym'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || acronym.contains(_searchQuery);
      }).toList();
    }

    if (_selectedFilter == 'free_granted') {
      list = list.where((s) => s['is_free_granted'] == true).toList();
    } else if (_selectedFilter != 'all') {
      list = list.where((s) => (s['subscription_status'] ?? 'active') == _selectedFilter).toList();
    }

    if (_sortBy == 'name') {
      list.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    } else if (_sortBy == 'expiry') {
      list.sort((a, b) {
        final ea = a['subscription_expiry_date'];
        final eb = b['subscription_expiry_date'];
        if (ea == null && eb == null) return 0;
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.toString().compareTo(eb.toString());
      });
    }
    // 'recent' is already the default order from the query

    return list;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    final filtered = _filteredSchools;
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
              "Client Schools",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() { _searchQuery = value.toLowerCase(); _currentPage = 0; }),
              decoration: InputDecoration(
                hintText: "Search school name or acronym...",
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
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip("All", "all", Colors.blue, isDark),
                        const SizedBox(width: 10),
                        _buildFilterChip("Active", "active", Colors.green, isDark),
                        const SizedBox(width: 10),
                        _buildFilterChip("Paused", "paused_payment", Colors.orange, isDark),
                        const SizedBox(width: 10),
                        _buildFilterChip("Terminated", "terminated", Colors.red, isDark),
                        const SizedBox(width: 10),
                        _buildFilterChip("Free/Granted", "free_granted", Colors.teal, isDark),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.sort_rounded, color: primaryColor),
                  initialValue: _sortBy,
                  onSelected: (v) => setState(() { _sortBy = v; _currentPage = 0; }),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'recent', child: Text('Most Recent')),
                    PopupMenuItem(value: 'name', child: Text('Name (A-Z)')),
                    PopupMenuItem(value: 'expiry', child: Text('Expiry Date')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading && _allSchools.isEmpty
                ? Center(child: TridetaLoader(color: primaryColor))
                : _hasError && _allSchools.isEmpty
                    ? const Center(child: Text("Failed to load schools."))
                    : RefreshIndicator(
                        onRefresh: _fetchSchools,
                        color: primaryColor,
                        child: filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    child: const Center(
                                      child: Text("No schools match this filter.",
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 8, bottom: 8),
                                itemCount: pageItems.length,
                                itemBuilder: (context, index) => _buildSchoolTile(pageItems[index], isDark, textColor),
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

  Widget _buildSchoolTile(Map<String, dynamic> school, bool isDark, Color textColor) {
    final status = school['subscription_status'] ?? 'active';
    final isFreeGranted = school['is_free_granted'] == true;
    final tier = (school['subscription_tier'] ?? 'tier_1').toString();

    final bool isActive = status == 'active';
    final bool isPaused = status == 'paused_payment';
    final bool isTerminated = status == 'terminated';

    Color statusColor = isActive ? Colors.green : (isPaused ? Colors.orange : Colors.red);
    String displayStatus = isActive ? "ACTIVE" : (isPaused ? "PAUSED" : "TERMINATED");

    String? expiryLabel;
    if (isActive && !isFreeGranted && tier != 'tier_1' && school['subscription_expiry_date'] != null) {
      final expiry = DateTime.tryParse(school['subscription_expiry_date']);
      if (expiry != null) {
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        if (daysLeft <= 14) {
          expiryLabel = daysLeft < 0 ? "Expired" : (daysLeft == 0 ? "Expires today" : "${daysLeft}d left");
        }
      }
    }

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => SchoolMasterDetailsScreen(school: school)))
                  .then((_) => _fetchSchools());
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(
                isActive ? Icons.verified_rounded : (isPaused ? Icons.pause_circle_filled_rounded : Icons.block_rounded),
                color: statusColor,
              ),
            ),
            title: Text(
              school['name'] ?? 'Unnamed School',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isTerminated ? Colors.grey.shade500 : textColor,
                decoration: isTerminated ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text("${school['acronym'] ?? ''} • $displayStatus",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tier.toUpperCase(),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ),
                  if (isFreeGranted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: const Text("FREE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ),
                  if (expiryLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(expiryLabel, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ),
                ],
              ),
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

  Widget _buildFilterChip(String label, String value, Color color, bool isDark) {
    bool isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() { _selectedFilter = value; _currentPage = 0; }),
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
