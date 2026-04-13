import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;

// 🚨 CORRECTED IMPORTS
import 'package:trideta_v2/screens/parent/parent_financial_service.dart'; // Solves the Service!

class ReceiptDetailView extends StatefulWidget {
  final Map<String, dynamic> tx;
  const ReceiptDetailView({super.key, required this.tx});

  @override
  State<ReceiptDetailView> createState() => _ReceiptDetailViewState();
}

class _ReceiptDetailViewState extends State<ReceiptDetailView>
    with AuthErrorHandler {
  final _screenCtrl = ScreenshotController();
  final _supabase = Supabase.instance.client;
  final _financialService = ParentFinancialService(); // 🚨 NEW MODULAR SERVICE

  bool _busy = false;
  bool _loading = true;

  String _schName = "SCHOOL";
  String _schAddr = "Address";
  String? _logo;
  double _currBal = 0.0;
  double _prevBal = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchAccounting();
  }

  Future<void> _fetchAccounting() async {
    try {
      final sId = widget.tx['school_id'];
      final stuId = widget.tx['student_id'];
      String targetSession = widget.tx['academic_session'] ?? "";

      if (sId != null) {
        final s = await _supabase
            .from('schools')
            .select('name, address, logo_url, current_session')
            .eq('id', sId)
            .single();
        if (targetSession.isEmpty) targetSession = s['current_session'] ?? "";

        setState(() {
          _schName = s['name'] ?? "SCHOOL";
          _schAddr = s['address'] ?? "Address Unavailable";
          _logo = s['logo_url'];
        });

        if (stuId != null && targetSession.isNotEmpty) {
          final studentData = await _supabase
              .from('students')
              .select('class_level, category')
              .eq('id', stuId)
              .single();
          String sClass = (studentData['class_level'] ?? '').toString();
          String sCategory = (studentData['category'] ?? '').toString();

          // 🚨 Use the Centralized Service!
          final financialSummary = await _financialService.getFinancialSummary(
            schoolId: sId.toString(),
            studentId: stuId.toString(),
            sClass: sClass,
            sCategory: sCategory,
            session: targetSession,
          );

          _currBal = financialSummary['balance']!;
          _prevBal = _currBal + (widget.tx['amount'] ?? 0.0).toDouble();
        }
      }
    } catch (e) {
      if (mounted) showAuthErrorDialog("Could not calculate receipt balance.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share(bool isPdf) async {
    setState(() => _busy = true);
    try {
      final bytes = await _screenCtrl.capture(
        delay: const Duration(milliseconds: 20),
        pixelRatio: 3.0,
      );
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final name = "Receipt_${widget.tx['id'].toString().substring(0, 8)}";

      if (isPdf) {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            build: (pw.Context ctx) =>
                pw.Center(child: pw.Image(pw.MemoryImage(bytes))),
          ),
        );
        final file = File('${dir.path}/$name.pdf');
        await file.writeAsBytes(await pdf.save());
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Payment Receipt from $_schName');
      } else {
        final file = File('${dir.path}/$name.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Payment Receipt from $_schName');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF1F4F8);
    Color primaryColor = Theme.of(context).primaryColor;

    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final payDate = DateFormat(
      'dd MMM yyyy, hh:mm a',
    ).format(DateTime.parse(widget.tx['created_at']));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Digital Receipt"),
        backgroundColor: primaryColor,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Screenshot(
                  controller: _screenCtrl,
                  child: Container(
                    width: 340,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.04,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Center(
                                child: Text(
                                  _schName.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 45,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Container(
                              height: 6,
                              width: double.infinity,
                              color: primaryColor,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 30,
                              ),
                              child: Column(
                                children: [
                                  if (_logo != null)
                                    Image.network(_logo!, height: 60)
                                  else
                                    Icon(
                                      Icons.account_balance_rounded,
                                      size: 50,
                                      color: Colors.grey[400],
                                    ),
                                  const SizedBox(height: 15),
                                  Text(
                                    _schName.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: Colors.black,
                                      letterSpacing: 0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    _schAddr,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      "-----------------------------------------------",
                                      style: TextStyle(color: Colors.black12),
                                    ),
                                  ),
                                  const Text(
                                    "OFFICIAL PAYMENT RECEIPT",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1.0,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      "-----------------------------------------------",
                                      style: TextStyle(color: Colors.black12),
                                    ),
                                  ),
                                  _buildTicketRow("DATE", payDate),
                                  _buildTicketRow(
                                    "RECEIPT NO",
                                    widget.tx['receipt_no']?.toString() ??
                                        "N/A",
                                  ),
                                  _buildTicketRow(
                                    "STUDENT",
                                    widget.tx['student_name']?.toUpperCase() ??
                                        "N/A",
                                  ),
                                  _buildTicketRow(
                                    "PAYMENT FOR",
                                    widget.tx['category'] ?? "N/A",
                                  ),
                                  _buildTicketRow(
                                    "METHOD",
                                    widget.tx['payment_method'] ?? "N/A",
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      "-----------------------------------------------",
                                      style: TextStyle(color: Colors.black12),
                                    ),
                                  ),
                                  _buildTicketRow(
                                    "PREVIOUS BALANCE",
                                    NumberFormat.currency(
                                      symbol: '₦',
                                    ).format(_prevBal),
                                  ),
                                  _buildTicketRow(
                                    "TOTAL AMOUNT PAID",
                                    NumberFormat.currency(
                                      symbol: '₦',
                                    ).format(widget.tx['amount']),
                                    isBold: true,
                                    color: Colors.green.shade700,
                                  ),
                                  const Divider(
                                    height: 30,
                                    color: Colors.black26,
                                  ),
                                  _buildTicketRow(
                                    "CURRENT OUTSTANDING",
                                    NumberFormat.currency(
                                      symbol: '₦',
                                    ).format(_currBal),
                                    isBold: true,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      "-----------------------------------------------",
                                      style: TextStyle(color: Colors.black12),
                                    ),
                                  ),
                                  const Text(
                                    "Thank you for your payment!",
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 11,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    "Digital Receipt by TriDeta",
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: List.generate(
                                20,
                                (index) => Expanded(
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: CustomPaint(
                                      painter: ZigZagPainter(bgColor),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: _busy
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _share(false),
                          icon: const Icon(Icons.image),
                          label: const Text(
                            "Share Image",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _share(true),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text(
                            "Share PDF",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ZigZagPainter extends CustomPainter {
  final Color backgroundColor;

  ZigZagPainter(this.backgroundColor);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    var path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
