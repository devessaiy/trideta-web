import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_saver/file_saver.dart';

import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';

class SessionArchiveScreen extends StatefulWidget {
  const SessionArchiveScreen({super.key});

  @override
  State<SessionArchiveScreen> createState() => _SessionArchiveScreenState();
}

class _SessionArchiveScreenState extends State<SessionArchiveScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isAdvancing = false;

  String? _schoolId;
  String _currentSession = "";
  String _currentTerm = "";

  double _totalCollected = 0.0;
  int _transactionCount = 0;

  String _newSession = "2026/2027";
  String _newTerm = "1st Term";

  @override
  void initState() {
    super.initState();
    _fetchSessionStats();
  }

  Future<void> _fetchSessionStats() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      final schoolData = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();
      _currentSession = schoolData['current_session'] ?? "Unknown";
      _currentTerm = schoolData['current_term'] ?? "Unknown";

      // Calculate totals for the warning card
      final txData = await _supabase
          .from('transactions')
          .select('amount')
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession);

      double total = 0.0;
      for (var tx in txData) {
        total += (tx['amount'] ?? 0).toDouble();
      }

      if (mounted) {
        setState(() {
          _totalCollected = total;
          _transactionCount = txData.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog(
          "Failed to fetch session data. Please check connection.",
        );
      }
    }
  }

  // 🚨 UNIVERSAL CSV GENERATOR & DOWNLOADER (WEB & MOBILE PROOF)
  Future<void> _generateAndDownloadCSV() async {
    setState(() => _isGenerating = true);
    try {
      final txData = await _supabase
          .from('transactions')
          .select(
            'created_at, receipt_no, student_name, category, payment_method, amount',
          )
          .eq('school_id', _schoolId!)
          .eq('academic_session', _currentSession)
          .order('created_at', ascending: false);

      if (txData.isEmpty) {
        showAuthErrorDialog("No transactions found for $_currentSession.");
        setState(() => _isGenerating = false);
        return;
      }

      // Build CSV String
      StringBuffer csvContent = StringBuffer();
      csvContent.writeln(
        "Date,Receipt No,Student Name,Payment Purpose,Payment Method,Amount",
      );

      for (var tx in txData) {
        DateTime date = DateTime.parse(tx['created_at']).toLocal();
        String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);

        // Escape commas in strings to prevent CSV breaking
        String name = '"${tx['student_name']}"';
        String category = '"${tx['category']}"';
        String method = '"${tx['payment_method']}"';
        String amount = tx['amount'].toString();
        String receipt = tx['receipt_no'].toString();

        csvContent.writeln(
          "$formattedDate,$receipt,$name,$category,$method,$amount",
        );
      }

      // Convert String to Bytes
      final Uint8List bytes = utf8.encode(csvContent.toString());

      // 🚨 THE FIX: Use FileSaver for true cross-platform downloads
      // On Web: Triggers the browser's native download bar
      // On Mobile: Saves directly to the device's Downloads folder
      String cleanSessionName = _currentSession.replaceAll('/', '-');

      await FileSaver.instance.saveFile(
        name: 'Trideta_Financial_Archive_$cleanSessionName',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

      if (mounted) {
        showSuccessDialog(
          "Archive Downloaded",
          "Financial records for $_currentSession have been successfully saved to your device.",
        );
      }
    } catch (e) {
      showAuthErrorDialog("Failed to generate CSV: $e");
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // 🚨 GLOBAL SESSION ADVANCER
  Future<void> _advanceSession() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text(
                  "Advance Session?",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: const Text(
              "This will reset the global financial engine. Students will no longer be billed for the current session, and their ledgers will start fresh. Have you downloaded the financial archive?",
              style: TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Yes, Advance Now",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isAdvancing = true);
    try {
      await _supabase
          .from('schools')
          .update({'current_session': _newSession, 'current_term': _newTerm})
          .eq('id', _schoolId!);

      if (mounted) {
        showSuccessDialog(
          "Session Advanced",
          "The school is now in $_newSession ($_newTerm). The finance engine has been reset.",
        );
        Navigator.pop(context); // Return to Finance Centre
      }
    } catch (e) {
      if (mounted) {
        showAuthErrorDialog("Failed to advance session. Check connection.");
      }
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;
    final f = NumberFormat.currency(symbol: '₦', decimalDigits: 0);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "End of Session Closeout",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- CURRENT STATS HEADER ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.archive_rounded,
                          color: primaryColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "CURRENT SESSION: $_currentSession",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey.shade500,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        f.format(_totalCollected),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        "Total Revenue Across $_transactionCount Transactions",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // --- STEP 1: DOWNLOAD REPORT ---
                _buildSectionHeader(
                  "STEP 1: GENERATE ARCHIVE",
                  Icons.download_rounded,
                  primaryColor,
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Download Financial Report",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Export all payments, receipts, and debtor logs into a secure CSV format before advancing the calendar.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isGenerating
                              ? null
                              : _generateAndDownloadCSV,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(
                            _isGenerating
                                ? "GENERATING..."
                                : "DOWNLOAD CSV REPORT",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // --- STEP 2: DANGER ZONE (ADVANCE SESSION) ---
                _buildSectionHeader(
                  "STEP 2: ADVANCE ACADEMIC CALENDAR",
                  Icons.warning_rounded,
                  Colors.orange,
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Danger Zone",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Advancing the global calendar resets the financial dashboard. Ensure you have safely stored your CSV report first.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _newSession,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("New Session", isDark),
                              items:
                                  [
                                        '2024/2025',
                                        '2025/2026',
                                        '2026/2027',
                                        '2027/2028',
                                      ]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            e,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) =>
                                  setState(() => _newSession = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _newTerm,
                              dropdownColor: cardColor,
                              decoration: _inputStyle("New Term", isDark),
                              items: ['1st Term', '2nd Term', '3rd Term']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        e,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _newTerm = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isAdvancing ? null : _advanceSession,
                          icon: _isAdvancing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                ),
                          label: Text(
                            _isAdvancing
                                ? "PROCESSING..."
                                : "ADVANCE CALENDAR & RESET",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label, bool isDark) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
    );
  }
}
