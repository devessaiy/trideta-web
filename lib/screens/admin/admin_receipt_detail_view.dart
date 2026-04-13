import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/foundation.dart'; // 🚨 ADDED FOR kIsWeb
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // 🚨 ADDED FOR WEB PDF PRINTING
import 'dart:convert';

class AdminReceiptDetailView extends StatefulWidget {
  final Map<String, dynamic> tx;
  const AdminReceiptDetailView({super.key, required this.tx});

  @override
  State<AdminReceiptDetailView> createState() => _AdminReceiptDetailViewState();
}

class _AdminReceiptDetailViewState extends State<AdminReceiptDetailView>
    with AuthErrorHandler {
  final _screenCtrl = ScreenshotController();
  final _supabase = Supabase.instance.client;
  bool _busy = false;
  bool _loading = true;

  String _schName = "TRIDETA SCHOOL";
  String _schAddr = "Nigeria";
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

        if (targetSession.isEmpty) {
          targetSession = s['current_session'] ?? "";
        }

        setState(() {
          _schName = s['name'] ?? "TRIDETA SCHOOL";
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

          final rawFeeData = await _supabase
              .from('fee_structures')
              .select(
                'fee_name, amount, applicable_classes, applicable_categories, academic_session',
              )
              .eq('school_id', sId);

          final txData = await _supabase
              .from('transactions')
              .select('category, amount, academic_session')
              .eq('student_id', stuId);

          Map<String, double> categoryPayments = {};
          for (var tx in txData) {
            String existingTxSession = (tx['academic_session'] ?? '')
                .toString();
            if (existingTxSession == targetSession ||
                existingTxSession.isEmpty) {
              String cat = (tx['category'] ?? '').toString();
              categoryPayments[cat] =
                  (categoryPayments[cat] ?? 0.0) +
                  (tx['amount'] ?? 0).toDouble();
            }
          }

          double outstanding = 0.0;

          for (var fee in rawFeeData) {
            String feeSession = (fee['academic_session'] ?? '').toString();
            if (feeSession == targetSession || feeSession.isEmpty) {
              bool classMatch = _doesItApply(fee['applicable_classes'], sClass);
              bool categoryMatch = _doesItApply(
                fee['applicable_categories'],
                sCategory,
                isCategory: true,
              );

              if (classMatch && categoryMatch) {
                String feeName = fee['fee_name'].toString();
                double expectedAmt = (fee['amount'] ?? 0).toDouble();
                double paidAmt = categoryPayments[feeName] ?? 0.0;

                double remaining = expectedAmt - paidAmt;
                if (remaining > 0) outstanding += remaining;
              }
            }
          }

          _currBal = outstanding;
          _prevBal = _currBal + (widget.tx['amount'] ?? 0.0).toDouble();
        }
      }
    } catch (e) {
      debugPrint("Overall Fetch Error: $e");
      if (mounted) showAuthErrorDialog("Could not calculate receipt balance.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _standardizeClass(String val) {
    String v = val.replaceAll(' ', '').toLowerCase();
    v = v
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3');
    v = v
        .replaceAll('four', '4')
        .replaceAll('five', '5')
        .replaceAll('six', '6');
    v = v
        .replaceAll('seven', '7')
        .replaceAll('eight', '8')
        .replaceAll('nine', '9');
    return v;
  }

  bool _doesItApply(
    dynamic columnData,
    String studentData, {
    bool isCategory = false,
  }) {
    String cleanStudentData = isCategory
        ? studentData.replaceAll(' ', '').toLowerCase()
        : _standardizeClass(studentData);
    if (isCategory &&
        (cleanStudentData.isEmpty || cleanStudentData == 'notfound')) {
      cleanStudentData = 'regular';
    }
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound') {
      return false;
    }
    if (columnData == null) return true;

    String colStr = isCategory
        ? columnData.toString().replaceAll(' ', '').toLowerCase()
        : _standardizeClass(columnData.toString());
    if (colStr.isEmpty ||
        colStr == 'all' ||
        colStr == '[]' ||
        colStr == '["all"]')
      return true;

    if (columnData is List) {
      if (columnData.isEmpty) return true;
      for (var item in columnData) {
        String cleanItem = isCategory
            ? item.toString().replaceAll(' ', '').toLowerCase()
            : _standardizeClass(item.toString());
        if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
      }
      return false;
    }

    try {
      List<dynamic> targetList = jsonDecode(columnData.toString());
      for (var item in targetList) {
        String cleanItem = isCategory
            ? item.toString().replaceAll(' ', '').toLowerCase()
            : _standardizeClass(item.toString());
        if (cleanItem == 'all' || cleanItem == cleanStudentData) return true;
      }
      return false;
    } catch (e) {
      return colStr.contains(cleanStudentData);
    }
  }

  // 🚨 NEW: WEB-SPECIFIC PDF DOWNLOAD/PRINT
  Future<void> _downloadWebPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await _screenCtrl.capture(
        delay: const Duration(milliseconds: 20),
        pixelRatio: 3.0,
      );
      if (bytes == null) return;

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (pw.Context ctx) =>
              pw.Center(child: pw.Image(pw.MemoryImage(bytes))),
        ),
      );

      // This safely triggers the browser's Print/Save-as-PDF dialog!
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: "Receipt_${widget.tx['id'].toString().substring(0, 8)}.pdf",
      );
    } catch (e) {
      if (mounted) showAuthErrorDialog("Error generating PDF: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 📱 MOBILE-SPECIFIC SHARING
  Future<void> _share(bool isPdf) async {
    if (kIsWeb) return; // Safeguard

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
        title: const Text("Share Receipt"),
        backgroundColor: primaryColor,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: Colors.grey.withOpacity(0.2),
                        width: 1,
                      ),
                      right: BorderSide(
                        color: Colors.grey.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: _buildContent(
                    isDark,
                    primaryColor,
                    payDate,
                    isDesktop: true,
                  ),
                ),
              ),
            );
          } else {
            return _buildContent(
              isDark,
              primaryColor,
              payDate,
              isDesktop: false,
            );
          }
        },
      ),
    );
  }

  Widget _buildContent(
    bool isDark,
    Color primaryColor,
    String payDate, {
    required bool isDesktop,
  }) {
    return Column(
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
                                  widget.tx['receipt_no']?.toString() ?? "N/A",
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
                                    painter: ZigZagPainter(
                                      isDark
                                          ? const Color(0xFF121212)
                                          : const Color(0xFFF1F4F8),
                                    ),
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

        // 🚨 CONDITIONAL RENDER: Web gets one button, Mobile gets two!
        Container(
          margin: isDesktop
              ? const EdgeInsets.only(bottom: 20, left: 20, right: 20)
              : EdgeInsets.zero,
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: isDesktop ? BorderRadius.circular(20) : null,
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
              : kIsWeb
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _downloadWebPdf,
                    icon: const Icon(Icons.print_rounded),
                    label: const Text(
                      "Download / Print PDF",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                )
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
