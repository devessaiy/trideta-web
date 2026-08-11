import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class ParentFinancialService {
  final _supabase = Supabase.instance.client;

  /// Fetches expected fees, total paid, and true outstanding balance factoring in wallet credit.
  Future<Map<String, double>> getFinancialSummary({
    required String schoolId,
    required String studentId,
    required String sClass,
    required String sCategory,
    required String session,
  }) async {
    // 1. Fetch Fees (DO NOT filter by session in DB to catch legacy empty strings)
    final rawFeeData = await _supabase
        .from('fee_structures')
        .select()
        .eq('school_id', schoolId);

    // 2. Fetch Payments
    final txData = await _supabase
        .from('transactions')
        .select()
        .eq('student_id', studentId);

    // 3. Fetch Wallet Balance
    final studentData = await _supabase
        .from('students')
        .select('wallet_balance')
        .eq('id', studentId)
        .single();

    double walletBalance = (studentData['wallet_balance'] ?? 0).toDouble();
    double availableCredit = walletBalance > 0 ? walletBalance : 0.0;

    // 🚨 Arrears form the baseline of the debt
    double outstanding = walletBalance < 0 ? walletBalance.abs() : 0.0;
    double totalPaid = 0.0;
    double totalExpected = outstanding;

    // Group payments by Category
    Map<String, double> categoryPayments = {};

    for (var tx in txData) {
      String txSession = (tx['academic_session'] ?? '').toString();
      if (txSession == session || txSession.isEmpty) {
        String cat = (tx['category'] ?? '').toString();
        double amt = (tx['amount'] ?? 0).toDouble();

        categoryPayments[cat] = (categoryPayments[cat] ?? 0.0) + amt;
        totalPaid += amt;
      }
    }

    // Calculate Expected & True Outstanding with Credit Offset
    for (var fee in rawFeeData) {
      String feeSession = (fee['academic_session'] ?? '').toString();

      if (feeSession == session || feeSession.isEmpty) {
        bool classMatch = doesItApply(fee['applicable_classes'], sClass);
        bool catMatch = doesItApply(
          fee['applicable_categories'],
          sCategory,
          isCategory: true,
        );

        if (classMatch && catMatch) {
          String feeName = fee['fee_name'].toString();
          double expectedAmt = (fee['amount'] ?? 0).toDouble();
          double paidAmt = categoryPayments[feeName] ?? 0.0;

          totalExpected += expectedAmt;

          double remaining = expectedAmt - paidAmt;
          if (remaining > 0) {
            // 🚨 ABSORB CREDIT ON PARENT UI
            if (availableCredit >= remaining) {
              availableCredit -= remaining;
              remaining = 0;
            } else if (availableCredit > 0) {
              remaining -= availableCredit;
              availableCredit = 0;
            }

            if (remaining > 0) {
              outstanding += remaining;
            }
          }
        }
      }
    }

    return {
      'expected': totalExpected,
      'paid': totalPaid,
      'balance': outstanding,
    };
  }

  // --- SYNCHRONIZED MATCHER ---
  bool doesItApply(
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
        colStr == '["all"]') {
      return true;
    }

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
}
