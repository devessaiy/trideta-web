import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:trideta_v2/widgets/trideta_loader.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'receipt_view_screen.dart';

class ReceiptHistoryScreen extends StatefulWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  State<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends State<ReceiptHistoryScreen>
    with AuthErrorHandler {
  final _supabase = Supabase.instance.client;

  String? _schoolId;

  // 🚨 ENGINE SWAP: Replaced Stream with stable State Variables
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // ===========================================================================
  // 🚨 STABLE FETCH ENGINE (Pull-to-Refresh instead of WebSockets)
  // ===========================================================================
  Future<void> _initData() async {
    await _fetchSchoolId();
    await _fetchTransactions();
  }

  Future<void> _fetchSchoolId() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single();
        _schoolId = profile['school_id'];
      }
    } catch (e) {
      debugPrint("School ID Fetch Error: $e");
    }
  }

  Future<void> _fetchTransactions() async {
    if (_schoolId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final data = await _supabase
          .from('transactions')
          .select()
          .eq('school_id', _schoolId!)
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Transaction Fetch Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Color primaryColor = Theme.of(context).primaryColor;

    // 🚨 UI FIX: Wrapped everything in a RefreshIndicator for pull-to-reload
    Widget mainContent = RefreshIndicator(
      onRefresh: _fetchTransactions,
      color: primaryColor,
      child: _isLoading && _transactions.isEmpty
          ? Center(child: TridetaLoader(color: primaryColor))
          : _hasError && _transactions.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: _buildErrorState(isDark, primaryColor),
                ),
              ],
            )
          : _transactions.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: _buildEmptyState(isDark),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 50),
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final tx = _transactions[index];
                return _buildTransactionCard(
                  tx,
                  cardColor,
                  isDark,
                  primaryColor,
                );
              },
            ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Transaction History",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
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
            return mainContent;
          }
        },
      ),
    );
  }

  // ===========================================================================
  // 🚨 FLAT UI BUILDERS (STRICTLY UNTOUCHED)
  // ===========================================================================
  Widget _buildTransactionCard(
    Map<String, dynamic> tx,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    final amountFormatted = NumberFormat.currency(
      symbol: '₦',
      decimalDigits: 0,
    ).format(tx['amount'] ?? 0);

    String dateFormatted = "Unknown Date";
    if (tx['created_at'] != null) {
      try {
        final date = DateTime.parse(tx['created_at']).toLocal();
        dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(date);
      } catch (e) {
        dateFormatted = "Invalid Date";
      }
    }

    IconData catIcon = Icons.payments_rounded;
    Color catColor = primaryColor;

    String category = (tx['category'] ?? '').toString().toLowerCase();
    if (category.contains('fee')) {
      catIcon = Icons.school_rounded;
      catColor = Colors.green;
    } else if (category.contains('uniform')) {
      catIcon = Icons.checkroom_rounded;
      catColor = Colors.orange;
    } else if (category.contains('pta')) {
      catIcon = Icons.groups_rounded;
      catColor = Colors.purple;
    }

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptViewScreen(transactionData: tx),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: catColor.withValues(alpha: 0.1),
                    child: Icon(catIcon, color: catColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx['student_name'] ?? 'Unknown Student',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${tx['category'] ?? 'Fee'} • ${tx['payment_method'] ?? 'N/A'}",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateFormatted,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amountFormatted,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "SUCCESSFUL",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 80, right: 24),
          child: Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 80,
            color: isDark ? Colors.white10 : Colors.grey[200],
          ),
          const SizedBox(height: 15),
          Text(
            "No transactions recorded yet",
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[400],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark, Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 80,
              color: isDark ? Colors.white24 : Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              "Connection Lost",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "We couldn't load the transaction history. Please check your connection or pull down to refresh.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
