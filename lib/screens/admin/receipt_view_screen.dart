import 'package:trideta_v2/utils/auth_error_handler.dart';
import 'package:flutter/foundation.dart'; // 🚨 ADDED FOR kIsWeb
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // 🚨 ADDED FOR WEB PRINTING
import 'dart:io';
import 'dart:convert';

class ReceiptViewScreen extends StatefulWidget {
  final Map<String, dynamic> transactionData;

  const ReceiptViewScreen({super.key, required this.transactionData});

  @override
  State<ReceiptViewScreen> createState() => _ReceiptViewScreenState();
}

class _ReceiptViewScreenState extends State<ReceiptViewScreen>
    with AuthErrorHandler {
  // --- PRINTER & DATA SETUP ---
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;

  String _schoolName = "Loading...";
  String _schoolAddress = "Loading...";
  String? _logoUrl;

  double _currentBalance = 0.0;
  double _previousBalance = 0.0;
  bool _isLoadingData = true;

  final _screenCtrl = ScreenshotController();
  bool _busy = false;

  // 🚨 RBAC TRACKER
  String _userRole = 'admin'; // Default to admin

  @override
  void initState() {
    super.initState();
    _fetchReceiptData();
    if (!kIsWeb) {
      _initBluetooth(); // Only init Bluetooth if NOT on web
    }
  }

  // --- NEW BULLETPROOF ITEMIZED MATH FOR RECEIPTS ---
  Future<void> _fetchReceiptData() async {
    try {
      final supabase = Supabase.instance.client;
      final schoolId = widget.transactionData['school_id'];
      final studentId = widget.transactionData['student_id'];

      // Fetch User Role for RBAC
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();
        _userRole = profile['role']?.toString().toLowerCase() ?? 'admin';
      }

      // Look for session on the transaction, fallback to empty string temporarily
      String targetSession = widget.transactionData['academic_session'] ?? "";

      if (schoolId != null) {
        // 1. Fetch School Details & Fallback Session
        final school = await supabase
            .from('schools')
            .select('name, address, logo_url, current_session')
            .eq('id', schoolId)
            .single();

        if (targetSession.isEmpty) {
          targetSession = school['current_session'] ?? "";
        }

        setState(() {
          _schoolName = school['name'] ?? "School Name";
          _schoolAddress = school['address'] ?? "School Address";
          _logoUrl = school['logo_url'];
        });

        // 2. Calculate the TRUE balance using Itemized Math
        if (studentId != null && targetSession.isNotEmpty) {
          final studentData = await supabase
              .from('students')
              .select('class_level, category')
              .eq('id', studentId)
              .single();

          String sClass = (studentData['class_level'] ?? '').toString();
          String sCategory = (studentData['category'] ?? '').toString();

          final rawFeeData = await supabase
              .from('fee_structures')
              .select(
                'fee_name, amount, applicable_classes, applicable_categories, academic_session',
              )
              .eq('school_id', schoolId);

          final txData = await supabase
              .from('transactions')
              .select('category, amount, academic_session')
              .eq('student_id', studentId);

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
                if (remaining > 0) {
                  outstanding += remaining;
                }
              }
            }
          }

          setState(() {
            _currentBalance = outstanding;
            _previousBalance =
                _currentBalance +
                (widget.transactionData['amount'] ?? 0.0).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint("Data fetch error: $e");
      if (mounted) {
        showAuthErrorDialog(
          "We couldn't load the complete receipt details. Please check your internet connection.",
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
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
        (cleanStudentData.isEmpty || cleanStudentData == 'notfound'))
      cleanStudentData = 'regular';
    if (cleanStudentData.isEmpty || cleanStudentData == 'notfound')
      return false;
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

  // --- BLUETOOTH LOGIC ---
  Future<void> _initBluetooth() async {
    if (kIsWeb) return; // Safeguard
    try {
      _devices = await bluetooth.getBondedDevices();
      if (mounted) setState(() {});
      bool? isConnected = await bluetooth.isConnected;
      if (isConnected == true && mounted) setState(() => _connected = true);
    } catch (e) {
      debugPrint("Bluetooth init error: $e");
    }
  }

  void _connectToPrinter(BluetoothDevice? device) async {
    if (kIsWeb) return; // Safeguard
    if (device == null) return;
    setState(() => _selectedDevice = device);
    try {
      await bluetooth.connect(device);
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      showAuthErrorDialog(
        "Failed to connect to the printer. Please make sure it is turned on and paired with your device.",
      );
    }
  }

  // --- 🚨 NEW: WEB PRINTING LOGIC ---
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
        name:
            "Receipt_${widget.transactionData['id'].toString().substring(0, 8)}.pdf",
      );
    } catch (e) {
      if (mounted) showAuthErrorDialog("Error generating PDF: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- MOBILE PRINTING LOGIC ---
  void _printReceipt(String amountFormatted, String dateFormatted) async {
    if (kIsWeb) return; // Safeguard

    bool? isConnected = await bluetooth.isConnected;
    if (isConnected != true) {
      showAuthErrorDialog(
        "The printer disconnected. Please reconnect and try again.",
      );
      return;
    }

    try {
      final f = NumberFormat.currency(symbol: 'NGN ');
      bluetooth.printCustom(_schoolName, 2, 1);
      bluetooth.printCustom(_schoolAddress, 1, 1);
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printCustom("PAYMENT RECEIPT", 2, 1);
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printLeftRight("Date:", dateFormatted, 1);
      bluetooth.printLeftRight(
        "Receipt:",
        widget.transactionData['receipt_no']?.toString() ?? 'N/A',
        1,
      );
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printCustom(
        "STUDENT: ${widget.transactionData['student_name']}",
        1,
        0,
      );
      bluetooth.printLeftRight(
        "Category:",
        widget.transactionData['category'] ?? 'N/A',
        1,
      );
      bluetooth.printLeftRight(
        "Method:",
        widget.transactionData['payment_method'] ?? 'N/A',
        1,
      );
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printLeftRight("OLD BALANCE:", f.format(_previousBalance), 1);
      bluetooth.printLeftRight(
        "AMOUNT PAID:",
        amountFormatted.replaceFirst('₦', 'NGN '),
        1,
      );
      bluetooth.printLeftRight("NEW BALANCE:", f.format(_currentBalance), 1);
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printCustom("Thank you!", 1, 1);
      bluetooth.printCustom("Powered by TriDeta", 0, 1);
      bluetooth.printNewLine();
      bluetooth.printNewLine();
      bluetooth.paperCut();
    } catch (e) {
      showAuthErrorDialog(
        "A printing error occurred. Please check the printer's connection and paper roll.",
      );
    }
  }

  // --- MOBILE SHARING LOGIC ---
  Future<void> _share(bool isPdf) async {
    if (kIsWeb) return; // Safeguard

    setState(() => _busy = true);
    try {
      final bytes = await _screenCtrl.capture(
        delay: const Duration(milliseconds: 20),
        pixelRatio: 3.0,
      );
      if (bytes == null) {
        throw "Failed to capture receipt image.";
      }

      final dir = await getTemporaryDirectory();
      final name =
          "Receipt_${widget.transactionData['id'].toString().substring(0, 8)}";

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
        ], text: 'Payment Receipt from $_schoolName');
      } else {
        final file = File('${dir.path}/$name.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Payment Receipt from $_schoolName');
      }
    } catch (e) {
      if (mounted)
        showAuthErrorDialog(
          "Failed to generate the file. Please ensure your app has file storage permissions.",
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF1F4F8);
    Color primaryColor = Theme.of(context).primaryColor;

    if (_isLoadingData)
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );

    final amountFormatted = NumberFormat.currency(
      symbol: '₦',
    ).format(widget.transactionData['amount'] ?? 0);
    final currBalFormatted = NumberFormat.currency(
      symbol: '₦',
    ).format(_currentBalance);
    final prevBalFormatted = NumberFormat.currency(
      symbol: '₦',
    ).format(_previousBalance);

    String dateFormatted = "Unknown Date";
    if (widget.transactionData['created_at'] != null) {
      try {
        final date = DateTime.parse(widget.transactionData['created_at']);
        dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(date);
      } catch (e) {
        dateFormatted = "N/A";
      }
    }

    // 🚨 EXTRACTED MAIN CONTENT
    Widget mainContent = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 1. Premium Printer Selector (HIDDEN ON WEB)
          if (!kIsWeb) ...[
            _buildPrinterCard(isDark, primaryColor),
            const SizedBox(height: 30),
          ],

          // 2. The "Paper Ticket" UI (Wrapped for Sharing!)
          Screenshot(
            controller: _screenCtrl,
            child: _buildPaperReceipt(
              dateFormatted,
              amountFormatted,
              prevBalFormatted,
              currBalFormatted,
              primaryColor,
              bgColor,
            ),
          ),

          const SizedBox(height: 40),

          // 3. ACTION BUTTONS (WEB VS MOBILE LOGIC)
          if (kIsWeb) ...[
            // 💻 WEB: Standard Print / Save PDF Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 0,
                ),
                onPressed: _busy ? null : _downloadWebPdf,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.print_rounded, color: Colors.white),
                label: Text(
                  _busy ? "PREPARING..." : "PRINT / DOWNLOAD RECEIPT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ] else ...[
            // 📱 MOBILE: Bluetooth Print Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _connected
                      ? Colors.green.shade600
                      : Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 0,
                ),
                onPressed: _connected
                    ? () => _printReceipt(amountFormatted, dateFormatted)
                    : null,
                icon: Icon(
                  _connected
                      ? Icons.print_rounded
                      : Icons.print_disabled_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  _connected ? "PRINT PHYSICAL RECEIPT" : "PRINTER OFFLINE",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // 🚨 MOBILE: Share Button (Only Bursars get this, Admin shares via Alerts)
            if (_userRole == 'bursar') ...[
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _busy
                      ? null
                      : () => _share(true), // Sharing as PDF
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.share_rounded, color: Colors.white),
                  label: Text(
                    _busy ? "GENERATING..." : "SHARE DIGITAL RECEIPT",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 15),
            const Text(
              "Ensure your thermal printer is turned on and paired via Bluetooth.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          "Digital Receipt",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // 🚨 SHAPE-SHIFTER: LayoutBuilder
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // 💻 DESKTOP LAYOUT (Constrained Center Column)
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
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

  // --- UI COMPONENTS ---

  Widget _buildPrinterCard(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_connected ? Colors.green : Colors.red).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_connected_rounded,
              color: _connected ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BluetoothDevice>(
                hint: const Text(
                  "Select Thermal Printer",
                  style: TextStyle(fontSize: 14),
                ),
                value: _selectedDevice,
                isExpanded: true,
                items: _devices
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          d.name ?? "Unknown Device",
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _connectToPrinter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperReceipt(
    String date,
    String paid,
    String oldBal,
    String newBal,
    Color primaryColor,
    Color bgColor,
  ) {
    return Container(
      width: 320,
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
      child: Column(
        children: [
          Container(
            height: 6,
            width: double.infinity,
            color: primaryColor.withOpacity(0.8),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Column(
              children: [
                if (_logoUrl != null)
                  Image.network(
                    _logoUrl!,
                    height: 60,
                    errorBuilder: (c, e, s) => Icon(
                      Icons.school_rounded,
                      color: Colors.grey[400],
                      size: 50,
                    ),
                  )
                else
                  Icon(
                    Icons.account_balance_rounded,
                    color: Colors.grey[400],
                    size: 50,
                  ),
                const SizedBox(height: 15),
                Text(
                  _schoolName.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  _schoolAddress,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
                _buildTicketRow("DATE", date),
                _buildTicketRow(
                  "RECEIPT NO",
                  widget.transactionData['receipt_no']?.toString() ?? 'N/A',
                ),
                _buildTicketRow(
                  "STUDENT",
                  widget.transactionData['student_name']?.toUpperCase() ??
                      'N/A',
                ),
                _buildTicketRow(
                  "PAYMENT FOR",
                  widget.transactionData['category'] ?? 'N/A',
                ),
                _buildTicketRow(
                  "METHOD",
                  widget.transactionData['payment_method'] ?? 'N/A',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "-----------------------------------------------",
                    style: TextStyle(color: Colors.black12),
                  ),
                ),
                _buildTicketRow("PREVIOUS BALANCE", oldBal),
                _buildTicketRow(
                  "TOTAL AMOUNT PAID",
                  paid,
                  isBold: true,
                  color: Colors.green.shade700,
                ),
                const Divider(height: 30, color: Colors.black26),
                _buildTicketRow("CURRENT OUTSTANDING", newBal, isBold: true),
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
          _buildZigZagBottom(bgColor),
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
              color: Colors.grey[500],
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

  Widget _buildZigZagBottom(Color bgColor) {
    return Row(
      children: List.generate(
        20,
        (index) => Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: CustomPaint(painter: ZigZagPainter(bgColor)),
          ),
        ),
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
