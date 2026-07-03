import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/super_admin/owner_views/school_master_details_screen.dart';

class OwnerSchoolsManagementView extends StatefulWidget {
  const OwnerSchoolsManagementView({super.key});

  @override
  State<OwnerSchoolsManagementView> createState() =>
      _OwnerSchoolsManagementViewState();
}

class _OwnerSchoolsManagementViewState
    extends State<OwnerSchoolsManagementView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter =
      "all"; // Options: 'all', 'active', 'paused_payment', 'terminated'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    Color primaryColor = Theme.of(context).primaryColor;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              "Client Schools",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ),

          // 🚨 SEARCH BAR
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search school name or acronym...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 🚨 PREMIUM FILTER CHIPS
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildFilterChip("All", "all", Colors.blue, isDark),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Paid (Active)",
                  "active",
                  Colors.green,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Owed (Paused)",
                  "paused_payment",
                  Colors.orange,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildFilterChip(
                  "Overdue (Terminated)",
                  "terminated",
                  Colors.red,
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 🚨 STREAM DATA LIST
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('schools')
                  .stream(primaryKey: ['id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(child: TridetaLoader(color: primaryColor));
                }

                List<Map<String, dynamic>> schools = snapshot.data ?? [];

                // 1. Apply Search Filter
                if (_searchQuery.isNotEmpty) {
                  schools = schools.where((school) {
                    final name = (school['name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final acronym = (school['acronym'] ?? '')
                        .toString()
                        .toLowerCase();
                    return name.contains(_searchQuery) ||
                        acronym.contains(_searchQuery);
                  }).toList();
                }

                // 2. Apply Status Filter
                if (_selectedFilter != 'all') {
                  schools = schools.where((school) {
                    final status = school['subscription_status'] ?? 'active';
                    return status == _selectedFilter;
                  }).toList();
                }

                if (schools.isEmpty) {
                  return const Center(
                    child: Text(
                      "No schools match this filter.",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  itemCount: schools.length,
                  itemBuilder: (context, index) {
                    final school = schools[index];
                    final status = school['subscription_status'] ?? 'active';

                    final bool isActive = status == 'active';
                    final bool isPaused = status == 'paused_payment';
                    final bool isTerminated = status == 'terminated';

                    Color statusColor = isActive
                        ? Colors.green
                        : (isPaused ? Colors.orange : Colors.red);
                    String displayStatus = isActive
                        ? "PAID & ACTIVE"
                        : (isPaused
                              ? "OWING (PAUSED)"
                              : "LONG OVERDUE (TERMINATED)");

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: !isActive
                              ? statusColor.withValues(alpha: 0.5)
                              : (isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  SchoolMasterDetailsScreen(school: school),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: statusColor.withValues(alpha: 0.1),
                          child: Icon(
                            isActive
                                ? Icons.verified_rounded
                                : (isPaused
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.block_rounded),
                            color: statusColor,
                          ),
                        ),
                        title: Text(
                          school['name'] ?? 'Unnamed School',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isTerminated
                                ? Colors.grey.shade500
                                : textColor,
                            decoration: isTerminated
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            "${school['acronym'] ?? ''} • $displayStatus",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          onSelected: (action) async {
                            await Supabase.instance.client
                                .from('schools')
                                .update({'subscription_status': action})
                                .eq('id', school['id']);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Subscription status updated successfully!",
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'active',
                              child: Text(
                                'Mark as Paid (10k / 30k)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'paused_payment',
                              child: Text(
                                'Pause Access (Owing)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'terminated',
                              child: Text(
                                'Terminate (Long Overdue)',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🚨 REUSABLE WIDGET FOR FILTER CHIPS
  Widget _buildFilterChip(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    bool isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.1)
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? color
                : (isDark ? Colors.white70 : Colors.grey.shade600),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
