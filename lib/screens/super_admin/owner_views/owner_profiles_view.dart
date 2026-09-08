import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class OwnerProfilesManagementView extends StatefulWidget {
  const OwnerProfilesManagementView({super.key});

  @override
  State<OwnerProfilesManagementView> createState() =>
      _OwnerProfilesManagementViewState();
}

class _OwnerProfilesManagementViewState
    extends State<OwnerProfilesManagementView> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  // 🚨 STABLE FETCH ENGINE (No Streams)
  Future<void> _fetchProfiles() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(data);
          _hasError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Profiles Fetch Error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              "Global Directory",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Expanded(
            child: _isLoading && _profiles.isEmpty
                ? const Center(child: TridetaLoader(color: Colors.indigo))
                : _hasError && _profiles.isEmpty
                ? const Center(child: Text("Failed to load profiles."))
                : RefreshIndicator(
                    onRefresh: _fetchProfiles,
                    color: Colors.indigo,
                    child: _profiles.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: const Center(
                                  child: Text(
                                    "No profiles found.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 8, bottom: 120),
                            itemCount: _profiles.length,
                            itemBuilder: (context, index) {
                              final profile = _profiles[index];
                              final isSuspended =
                                  profile['is_suspended'] == true;

                              return Column(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 8,
                                          ),
                                      leading: CircleAvatar(
                                        radius: 25,
                                        backgroundColor: isDark
                                            ? Colors.white10
                                            : Colors.grey.shade100,
                                        backgroundImage:
                                            profile['passport_url'] != null
                                            ? NetworkImage(
                                                profile['passport_url'],
                                              )
                                            : null,
                                        child: profile['passport_url'] == null
                                            ? Icon(
                                                Icons.person,
                                                color: Colors.grey.shade400,
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        profile['full_name'] ?? 'No Name',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isSuspended
                                              ? Colors.grey.shade500
                                              : textColor,
                                          decoration: isSuspended
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4.0,
                                        ),
                                        child: Text(
                                          "${profile['role'].toString().toUpperCase()} • ${profile['email']}",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          isSuspended
                                              ? Icons.restore_rounded
                                              : Icons.block_rounded,
                                          color: isSuspended
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                        onPressed: () async {
                                          // 🚨 Untouched Logic: Suspend/Restore User
                                          await _supabase
                                              .from('profiles')
                                              .update({
                                                'is_suspended': !isSuspended,
                                              })
                                              .eq('id', profile['id']);

                                          // Refresh the list after the update
                                          _fetchProfiles();
                                        },
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 88,
                                      right: 24,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
