import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EndOfTermProceedingsScreen extends StatefulWidget {
  const EndOfTermProceedingsScreen({super.key});

  @override
  State<EndOfTermProceedingsScreen> createState() =>
      _EndOfTermProceedingsScreenState();
}

class _EndOfTermProceedingsScreenState extends State<EndOfTermProceedingsScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isAdvancing = false;
  bool _confirmCheck = false;

  String? _schoolId;
  String _currentSession = "";
  String _currentTerm = "";
  String _nextTerm = "";

  @override
  void initState() {
    super.initState();
    _fetchSchoolStatus();
  }

  Future<void> _fetchSchoolStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      _schoolId = profile['school_id'];

      final school = await _supabase
          .from('schools')
          .select('current_session, current_term')
          .eq('id', _schoolId!)
          .single();

      _currentSession = school['current_session'] ?? "";
      _currentTerm = school['current_term'] ?? "1st Term";

      // Calculate the next term
      if (_currentTerm == '1st Term') {
        _nextTerm = '2nd Term';
      } else if (_currentTerm == '2nd Term') {
        _nextTerm = '3rd Term';
      } else {
        _nextTerm = 'End of Year'; // Will trigger the lock
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAuthErrorDialog("Failed to load school calendar data.");
      }
    }
  }

  // 🚨 ADDED: Explicit Confirm Dialog before Execution
  Future<void> _advanceTerm() async {
    if (!_confirmCheck || _nextTerm == 'End of Year' || _schoolId == null) {
      return;
    }

    final confirmController = TextEditingController();
    bool isConfirmed =
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            title: const Text(
              "IRREVERSIBLE TERM ADVANCEMENT",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You are about to advance the entire school to the $_nextTerm. This will instantly freeze all attendance, grades, and report cards for the $_currentTerm. To proceed, type CONFIRM below.",
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    hintText: "Type CONFIRM",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  if (confirmController.text.trim().toUpperCase() ==
                      "CONFIRM") {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text("EXECUTE ACTION"),
              ),
            ],
          ),
        ) ??
        false;

    if (!isConfirmed) return;

    setState(() => _isAdvancing = true);

    try {
      await _supabase
          .from('schools')
          .update({'current_term': _nextTerm})
          .eq('id', _schoolId!);

      if (mounted) {
        setState(() => _isAdvancing = false);
        showSuccessDialog(
          "Term Advanced Successfully",
          "The school is now operating in the $_nextTerm of $_currentSession. Attendance, Grades, and Broadsheets have been reset for the new term. Financial wallets have successfully carried over.",
          onOkay: () => Navigator.pop(context),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAdvancing = false);
        showAuthErrorDialog("Failed to advance term. Error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: TridetaLoader(color: primaryColor)),
      );
    }

    bool isLocked = _currentTerm == '3rd Term';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "End of Term Proceedings",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── STATUS HEADER ───
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? Colors.redAccent.withValues(alpha: 0.1)
                        : primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLocked
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isLocked
                            ? Icons.lock_rounded
                            : Icons.change_circle_rounded,
                        size: 40,
                        color: isLocked ? Colors.redAccent : primaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Current Academic Timeline",
                        style: TextStyle(
                          color: isLocked ? Colors.redAccent : primaryColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "$_currentTerm, $_currentSession",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // ─── ACTION PANEL ───
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: isLocked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.block_rounded,
                              size: 60,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "Term Advancement Locked",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "You are currently in the 3rd Term. You cannot advance to a 4th Term. To conclude this academic year and promote students to the next class, please use the End of Year Proceedings module instead.",
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.5, fontSize: 14),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Proceed to Next Term",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Advancing to the $_nextTerm will automatically perform the following system operations:",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 24),

                            _buildChecklistItem(
                              "Data Freeze",
                              "Locks all attendance, affective traits, exam scores, and report cards for $_currentTerm.",
                              Icons.ac_unit_rounded,
                              Colors.blue,
                            ),
                            _buildChecklistItem(
                              "Blank Slate",
                              "Generates clean, empty rosters and broadsheets for teachers to begin $_nextTerm.",
                              Icons.post_add_rounded,
                              Colors.green,
                            ),
                            _buildChecklistItem(
                              "Financial Rollover",
                              "Safely carries over all Perpetual Wallet credits and arrears into the new term.",
                              Icons.account_balance_wallet_rounded,
                              Colors.orange,
                            ),

                            const SizedBox(height: 30),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: _confirmCheck,
                                    activeColor: Colors.red,
                                    onChanged: (val) {
                                      setState(() => _confirmCheck = val!);
                                    },
                                  ),
                                  const Expanded(
                                    child: Text(
                                      "I confirm that all report cards have been published and I am ready to advance the school to the next term.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: (!_confirmCheck || _isAdvancing)
                                    ? null
                                    : _advanceTerm,
                                icon: _isAdvancing
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: TridetaLoader(
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.fast_forward_rounded,
                                        color: Colors.white,
                                      ),
                                label: Text(
                                  _isAdvancing
                                      ? "PROCESSING..."
                                      : "ADVANCE TO ${_nextTerm.toUpperCase()}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistItem(
    String title,
    String desc,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
