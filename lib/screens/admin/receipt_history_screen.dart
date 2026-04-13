import 'package:trideta_v2/utils/auth_error_handler.dart';
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
  // 🚨 Added AuthErrorHandler
  final _supabase = Supabase.instance.client;

  String? _schoolId;

  @override
  void initState() {
    super.initState();
    _fetchSchoolId();
  }

  Future<void> _fetchSchoolId() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final profile = await _supabase
          .from('profiles')
          .select('school_id')
          .eq('id', user.id)
          .single();
      if (mounted) {
        setState(() => _schoolId = profile['school_id']);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // 🚨 ADDED DYNAMIC COLOR HERE
    Color primaryColor = Theme.of(context).primaryColor;

    final Stream<List<Map<String, dynamic>>>? transactionStream =
        _schoolId == null
        ? null
        : _supabase
              .from('transactions')
              .stream(primaryKey: ['id'])
              .eq('school_id', _schoolId!)
              .order('created_at', ascending: false);

    // 🚨 EXTRACTED MAIN CONTENT FOR LAYOUT BUILDER
    Widget mainContent = transactionStream == null
        ? Center(child: CircularProgressIndicator(color: primaryColor))
        : StreamBuilder<List<Map<String, dynamic>>>(
            stream: transactionStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // 🚨 Shows clean layman UI instead of raw DB errors
                return _buildErrorState(isDark, primaryColor);
              }
              if (!snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: primaryColor),
                );
              }

              final transactions = snapshot.data!;

              if (transactions.isEmpty) return _buildEmptyState(isDark);

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  return _buildTransactionCard(
                    tx,
                    cardColor,
                    isDark,
                    primaryColor,
                  ); // Passed color down
                },
              );
            },
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Transaction History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor, // 🚨 Dynamic color
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained center column)
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
            // 📱 MOBILE LAYOUT
            return mainContent;
          }
        },
      ),
    );
  }

  // 🚨 Updated to receive primaryColor
  Widget _buildTransactionCard(
    Map<String, dynamic> tx,
    Color cardColor,
    bool isDark,
    Color primaryColor,
  ) {
    final amountFormatted = NumberFormat.currency(
      symbol: '₦',
    ).format(tx['amount'] ?? 0);

    String dateFormatted = "Unknown Date";
    if (tx['created_at'] != null) {
      try {
        final date = DateTime.parse(tx['created_at']);
        dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(date);
      } catch (e) {
        dateFormatted = "Invalid Date";
      }
    }

    // Logic for category icons
    IconData catIcon = Icons.payments_rounded;
    // 🚨 Default color now matches Brand instead of hardcoded blue
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: catColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(catIcon, color: catColor, size: 24),
        ),
        title: Text(
          tx['student_name'] ?? 'Unknown Student',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${tx['category'] ?? 'Fee'} • ${tx['payment_method'] ?? 'N/A'}",
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                dateFormatted,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        trailing: Column(
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptViewScreen(transactionData: tx),
            ),
          );
        },
      ),
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

  // 🚨 CLEAN, LAYMAN ERROR UI (Matches the rest of the app)
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
              "We couldn't load the transaction history. Please check your connection.",
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
