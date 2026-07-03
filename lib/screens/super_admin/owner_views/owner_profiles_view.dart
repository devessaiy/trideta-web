import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class OwnerProfilesManagementView extends StatelessWidget {
  const OwnerProfilesManagementView({super.key});

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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('profiles')
                  .stream(primaryKey: ['id']),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: TridetaLoader(color: Colors.indigo),
                  );
                }
                final profiles = snapshot.data!;

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isSuspended = profile['is_suspended'] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSuspended
                              ? Colors.red.withValues(alpha: 0.3)
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: isDark
                              ? Colors.white10
                              : Colors.grey.shade100,
                          backgroundImage: profile['passport_url'] != null
                              ? NetworkImage(profile['passport_url'])
                              : null,
                          child: profile['passport_url'] == null
                              ? Icon(Icons.person, color: Colors.grey.shade400)
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
                          padding: const EdgeInsets.only(top: 4.0),
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
                            color: isSuspended ? Colors.green : Colors.red,
                          ),
                          onPressed: () async {
                            await Supabase.instance.client
                                .from('profiles')
                                .update({'is_suspended': !isSuspended})
                                .eq('id', profile['id']);
                          },
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
}
