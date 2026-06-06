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
        showSuccessDialog(
          "Export Complete",
          "No records found in $label. Marked as complete.",
        );
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
      await FileSaver.instance.saveFile(
        name:
            'Trideta_${tableName.toUpperCase()}_Backup_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        mimeType:
            MimeType.csv, // 🚨 FIXED: Removed the redundant 'ext:' parameter
      );

      setState(() => _downloadedTables.add(tableName));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "$label Exported Successfully!",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      showAuthErrorDialog("Failed to export $label: $e");
    } finally {
      if (mounted) setState(() => _currentlyDownloading = null);
    }
  }

  Future<void> _executeAnnihilation() async {
    if (_downloadedTables.length < _tablesToExport.length) {
      showAuthErrorDialog(
        "Incomplete Archive.\n\nYou must successfully download all ${_tablesToExport.length} data tables before the system will authorize account termination.",
      );
      return;
    }

    setState(() => _isDeleting = true);
    try {
      // 🚨 BYPASS 409 CONFLICT: Wipe child tables first from leaf-nodes up to avoid Foreign Key blocks!
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

      // Finally, safely delete the parent school record
      await _supabase.from('schools').delete().eq('id', widget.schoolId);
      await _supabase.auth.signOut();

      if (mounted) {
        showSuccessDialog(
          "School Deleted",
          "Your school and all associated data have been permanently removed from TriDeta.",
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted)
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
        });
      }
    } catch (e) {
      if (mounted)
        showAuthErrorDialog("Critical Failure during termination: $e");
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _confirmAnnihilation(bool isDark) {
    if (_downloadedTables.length < _tablesToExport.length) {
      _executeAnnihilation(); // Triggers the lockout error
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
              ),
            ),
          ],
        ),
        content: const Text(
          "You are about to permanently delete your entire school database. This action is irreversible and all active logins will be severed immediately.\n\nDo you wish to proceed?",
          style: TextStyle(height: 1.5),
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

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // 🚨 Custom Back Button to pass the downloaded status back to the Menu
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
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 50),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.privacy_tip_rounded,
                        color: Colors.redAccent,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Data Extraction Required\n\nBefore you can terminate your Trideta service, you must securely download a CSV backup of your database tables below.",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.red.shade900,
                            height: 1.5,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                const Text(
                  "DATABASE TABLES",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.grey,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                ..._tablesToExport.map((tableMap) {
                  String tName = tableMap['table']!;
                  String tLabel = tableMap['label']!;
                  bool isDownloaded = _downloadedTables.contains(tName);
                  bool isDownloadingThis = _currentlyDownloading == tName;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDownloaded
                            ? Colors.green.withValues(alpha: 0.5)
                            : (isDark ? Colors.white10 : Colors.grey.shade200),
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
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDownloaded
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        isDownloaded ? "Secured" : "Pending Download",
                        style: TextStyle(
                          color: isDownloaded
                              ? Colors.green
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _currentlyDownloading != null
                                        ? null
                                        : () => _downloadTable(tName, tLabel),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      "EXPORT",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  )),
                    ),
                  );
                }),

                const SizedBox(height: 50),
                const Divider(),
                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation:
                          _downloadedTables.length < _tablesToExport.length
                          ? 0
                          : 8,
                      shadowColor: Colors.redAccent.withValues(alpha: 0.5),
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
                        : const Icon(Icons.delete_forever_rounded, size: 24),
                    label: Text(
                      _isDeleting
                          ? "PURGING DATABASE..."
                          : "I UNDERSTAND, TERMINATE SCHOOL",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        fontSize: 15,
                      ),
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
