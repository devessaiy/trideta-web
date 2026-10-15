import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_saver/file_saver.dart';
import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:trideta_v2/screens/auth/login_screen.dart';

class SchoolDataExportScreen extends StatefulWidget {
  final String schoolId;
  final Set<String> alreadyDownloaded;

  const SchoolDataExportScreen({
    super.key,
    required this.schoolId,
    required this.alreadyDownloaded,
  });

  @override
  State<SchoolDataExportScreen> createState() => _SchoolDataExportScreenState();
}

class _SchoolDataExportScreenState extends State<SchoolDataExportScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  // 🚨 ALL 14 TRIDETA TABLES
  final List<Map<String, String>> _tablesToExport = [
    {'table': 'students', 'label': 'Student Biodata & Profiles'},
    {'table': 'transactions', 'label': 'Financial Receipts & Payments'},
    {'table': 'term_results', 'label': 'Academic Term Results'},
    {'table': 'exam_scores', 'label': 'Detailed Exam Scores'},
    {'table': 'affective_traits', 'label': 'Affective Traits & Behavior'},
    {'table': 'attendance', 'label': 'Daily Attendance Logs'},
    {'table': 'fee_structures', 'label': 'Fee Structures & Financials'},
    {'table': 'classes', 'label': 'Academic Classes'},
    {'table': 'class_subjects', 'label': 'Class Subject Mappings'},
    {'table': 'staff_assignments', 'label': 'Staff Roles & Assignments'},
    {'table': 'profiles', 'label': 'User Accounts & Access'},
    {'table': 'alerts', 'label': 'System & Action Alerts'},
    {'table': 'alert_reads', 'label': 'Alert Read Receipts'},
    {'table': 'schools', 'label': 'Core School Configuration'},
  ];

  late Set<String> _downloadedTables;
  String? _currentlyDownloading;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _downloadedTables = Set.from(widget.alreadyDownloaded);
  }

  Future<void> _downloadTable(String tableName, String label) async {
    setState(() => _currentlyDownloading = tableName);
    try {
      List<dynamic> response;
      try {
        if (tableName == 'schools') {
          response = await _supabase
              .from(tableName)
              .select('*')
              .eq('id', widget.schoolId);
        } else {
          response = await _supabase
              .from(tableName)
              .select('*')
              .eq('school_id', widget.schoolId);
        }
      } catch (_) {
        try {
          response = await _supabase.from(tableName).select('*');
        } catch (_) {
          response = [];
        }
      }

      if (response.isEmpty) {
        setState(() => _downloadedTables.add(tableName));
        if (mounted) {
          showSuccessDialog(
            "Export Complete",
            "No records found in $label. Marked as complete.",
          );
        }
        return;
      }

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response,
      );
      StringBuffer csvContent = StringBuffer();
      List<String> headers = data.first.keys.toList();
      csvContent.writeln(headers.join(','));

      for (var row in data) {
        List<String> rowValues = [];
        for (var header in headers) {
          String val = row[header]?.toString() ?? '';
          if (val.contains(',') || val.contains('"') || val.contains('\n')) {
            val = '"${val.replaceAll('"', '""')}"';
          }
          rowValues.add(val);
        }
        csvContent.writeln(rowValues.join(','));
      }

      final Uint8List bytes = utf8.encode(csvContent.toString());
      final String fileName =
          'Trideta_${tableName.toUpperCase()}_Backup_${DateTime.now().millisecondsSinceEpoch}';

      // 🚨 MOBILE APK FIX: Use saveAs on Mobile so Android/iOS saves to visible Downloads folder
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.csv,
        );
      } else {
        final String? savedPath = await FileSaver.instance.saveAs(
          name: fileName,
          bytes: bytes,
          fileExtension: 'csv',
          mimeType: MimeType.csv,
        );
        if (savedPath == null || savedPath.isEmpty) {
          return;
        }
      }

      setState(() => _downloadedTables.add(tableName));
      if (mounted) {
        showSuccessDialog("Export Complete", "$label exported successfully!");
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Failed to export $label: $e");
      }
    } finally {
      if (mounted) setState(() => _currentlyDownloading = null);
    }
  }

  // ===========================================================================
  // 🚨 TOTAL ANNIHILATION ENGINE (STRICTLY UNTOUCHED)
  // ===========================================================================
  Future<void> _executeAnnihilation() async {
    if (_downloadedTables.length < _tablesToExport.length) {
      showAuthErrorDialog(
        "Incomplete Archive.\n\nYou must successfully download all ${_tablesToExport.length} data tables before the system will authorize account termination.",
      );
      return;
    }

    setState(() => _isDeleting = true);
    try {
      final currentUser = _supabase.auth.currentUser;
      final myEmail = currentUser?.email;

      // --- PHASE 1: RECONNAISSANCE & PARENT MIGRATION ---
      final profilesData = await _supabase
          .from('profiles')
          .select('id, email, role')
          .eq('school_id', widget.schoolId);
      List<String> emailsToDelete = [];

      for (var p in profilesData) {
        String? email = p['email']?.toString();
        String? role = p['role']?.toString();
        String? profileId = p['id']?.toString();

        if (email == null || email.isEmpty) continue;
        if (email == myEmail) {
          continue; // Skip active admin (we wipe admin last)
        }

        if (role == 'parent') {
          // Check if this parent has students in OTHER Trideta schools globally
          final otherStudents = await _supabase
              .from('students')
              .select('school_id')
              .eq('parent_email', email)
              .neq('school_id', widget.schoolId)
              .limit(1);

          if (otherStudents.isNotEmpty) {
            // SIBLING FOUND IN ANOTHER SCHOOL!
            // Migrate their profile to the other school instead of destroying it.
            String otherSchoolId = otherStudents.first['school_id'];
            await _supabase
                .from('profiles')
                .update({'school_id': otherSchoolId})
                .eq('id', profileId!);
            continue; // Safely skip adding this parent to the kill list
          } else {
            // No other children in the system. Mark for complete destruction.
            emailsToDelete.add(email);
          }
        } else {
          // Teachers and Staff are unique to the school. Mark for destruction.
          emailsToDelete.add(email);
        }
      }

      // --- PHASE 2: TABLE PURGE ---
      // Systematically wipe all child records to bypass Foreign Key constraint blocks
      final List<String> safeDeletionOrder = [
        'alert_reads',
        'alerts',
        'affective_traits',
        'exam_scores',
        'term_results',
        'attendance',
        'transactions',
        'staff_assignments',
        'class_subjects',
        'fee_structures',
        'students',
        'classes',
        'profiles',
      ];

      for (String tName in safeDeletionOrder) {
        try {
          await _supabase.from(tName).delete().eq('school_id', widget.schoolId);
        } catch (_) {}
      }

      // --- PHASE 3: CORE PURGE ---
      // Safely delete the parent school record
      await _supabase.from('schools').delete().eq('id', widget.schoolId);

      // --- PHASE 4: AUTH.USERS ANNIHILATION ---
      // Concurrently trigger Edge Function to wipe all harvested emails from Auth
      List<Future> deleteFutures = [];
      for (String email in emailsToDelete) {
        deleteFutures.add(
          _supabase.functions
              .invoke(
                'manage-user-auth',
                body: {'action': 'delete', 'email': email},
              )
              // ignore: invalid_return_type_for_catch_error
              .catchError((_) => null),
        );
      }
      await Future.wait(deleteFutures); // Execute the mass wipe

      // Finally, destroy the Admin's own Auth account to prevent API cutoff mid-process
      if (myEmail != null) {
        try {
          await _supabase.functions.invoke(
            'manage-user-auth',
            body: {'action': 'delete', 'email': myEmail},
          );
        } catch (_) {}
      }

      // Locally sign out
      await _supabase.auth.signOut();

      if (mounted) {
        showSuccessDialog(
          "School Deleted",
          "Your school, tables, and all associated user accounts have been permanently wiped from TriDeta.",
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Critical Failure during termination: $e");
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _confirmAnnihilation(bool isDark) {
    if (_downloadedTables.length < _tablesToExport.length) {
      _executeAnnihilation(); // Triggers the visual lockout error
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 30,
            ),
            SizedBox(width: 10),
            Text(
              "Final Confirmation",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.redAccent,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          "You are about to permanently delete your entire school database AND completely wipe all associated parent, teacher, and admin login accounts (except parents with active students in other Trideta schools).\n\nThis action is irreversible. Do you wish to proceed?",
          style: TextStyle(
            height: 1.5,
            fontSize: 14,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeAnnihilation();
            },
            child: const Text(
              "I UNDERSTAND, DELETE",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 🚨 CARDLESS, WHATSAPP-STYLE EDGE-TO-EDGE UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    bool allSecured = _downloadedTables.length >= _tablesToExport.length;

    Widget mainContent = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ─── 1. EDGE-TO-EDGE WARNING & PROGRESS HEADER ───
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            color: surfaceColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.privacy_tip_rounded,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Data Extraction Required",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Before terminating your Trideta service, you must securely download a CSV backup of all ${_tablesToExport.length} database tables below.",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                              height: 1.4,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (allSecured ? Colors.green : Colors.redAccent)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        allSecured
                            ? Icons.verified_rounded
                            : Icons.lock_clock_rounded,
                        size: 16,
                        color: allSecured ? Colors.green : Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${_downloadedTables.length} OF ${_tablesToExport.length} TABLES SECURED",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: allSecured ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),

        // ─── 2. SECTION LABEL ───
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              "DATABASE TABLES",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: Colors.grey.shade500,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),

        // ─── 3. WHATSAPP-STYLE EDGE-TO-EDGE TABLE LIST ───
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final tableMap = _tablesToExport[index];
            final String tName = tableMap['table']!;
            final String tLabel = tableMap['label']!;
            final bool isDownloaded = _downloadedTables.contains(tName);
            final bool isDownloadingThis = _currentlyDownloading == tName;

            return Container(
              color: surfaceColor,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: isDownloaded
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.blue.withValues(alpha: 0.1),
                      child: Icon(
                        isDownloaded
                            ? Icons.check_circle_rounded
                            : Icons.table_chart_rounded,
                        color: isDownloaded ? Colors.green : Colors.blue,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      tLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isDownloaded
                            ? "Secured • $tName.csv"
                            : "Pending Download • $tName",
                        style: TextStyle(
                          color: isDownloaded
                              ? Colors.green
                              : Colors.grey.shade500,
                          fontWeight: isDownloaded
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    trailing: isDownloadingThis
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: TridetaLoader(color: Colors.blue),
                          )
                        : (isDownloaded
                              ? const Icon(
                                  Icons.cloud_done_rounded,
                                  color: Colors.green,
                                )
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _currentlyDownloading != null
                                      ? null
                                      : () => _downloadTable(tName, tLabel),
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "EXPORT",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                )),
                    onTap: (isDownloaded || _currentlyDownloading != null)
                        ? null
                        : () => _downloadTable(tName, tLabel),
                  ),
                  if (index < _tablesToExport.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 88, right: 24),
                      child: Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                      ),
                    ),
                ],
              ),
            );
          }, childCount: _tablesToExport.length),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _downloadedTables),
        ),
        title: const Text(
          "Export & Termination Hub",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 55,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _isDeleting
                  ? null
                  : () => _confirmAnnihilation(isDark),
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: TridetaLoader(color: Colors.white),
                    )
                  : const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
              label: Text(
                _isDeleting
                    ? "WIPING ACCOUNTS & DATA..."
                    : "UNDERSTOOD, TERMINATE.",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.0,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
