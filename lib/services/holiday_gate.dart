import 'package:flutter/material.dart';

/// What the school's holiday settings say about running End of Term or
/// End of Year. The database enforces the same rule; this is for showing a
/// clear message before the admin tries.
class HolidayGate {
  final bool gateEnabled;
  final bool onHoliday;
  final DateTime? resumesOn;

  const HolidayGate({
    required this.gateEnabled,
    required this.onHoliday,
    this.resumesOn,
  });

  factory HolidayGate.fromSchool(Map<String, dynamic> s) => HolidayGate(
    gateEnabled: s['holiday_gate_enabled'] == true,
    onHoliday: s['is_on_holiday'] == true,
    resumesOn: s['holiday_resumes_on'] == null
        ? null
        : _dateOnly(DateTime.tryParse(s['holiday_resumes_on'].toString())),
  );

  static DateTime? _dateOnly(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  /// Today's date in Nigeria (UTC+1, no daylight saving).
  static DateTime get todayInNigeria {
    final n = DateTime.now().toUtc().add(const Duration(hours: 1));
    return DateTime(n.year, n.month, n.day);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get canRun {
    if (!gateEnabled) return true;
    if (!onHoliday || resumesOn == null) return false;
    return !todayInNigeria.isBefore(resumesOn!);
  }

  String get blockedTitle {
    if (!onHoliday) return 'Declare the school holiday first';
    if (resumesOn == null) return 'Set the resumption date';
    return 'Available from ${formatDate(resumesOn!)}';
  }

  String get blockedMessage {
    if (!onHoliday) {
      return 'End of Term and End of Year are run on the resumption date, after the school has been declared on holiday. Publish every class result in the Master Broadsheet, then declare the holiday there.';
    }
    if (resumesOn == null) {
      return 'Open the Master Broadsheet and set the date the school resumes.';
    }
    return 'The school is on holiday until ${formatDate(resumesOn!)}. Running this on the resumption date moves the school to the new term and reopens attendance.';
  }
}

/// Turns the database's holiday rules into a clear message, or null if the
/// error is something else.
String? friendlyHolidayError(Object e) {
  final s = e.toString();
  if (s.contains('HOLIDAY_REQUIRED')) {
    return 'Declare the school holiday in the Master Broadsheet first. End of Term and End of Year can only be run on the resumption date.';
  }
  if (s.contains('HOLIDAY_NOT_OVER')) {
    final m = RegExp(r'\((\d{4}-\d{2}-\d{2}|not set)\)').firstMatch(s);
    final when = m == null ? '' : ' (${m.group(1)})';
    return 'It is not the resumption date yet$when. End of Term and End of Year can only be run on or after the resumption date.';
  }
  return null;
}

class HolidayGateBanner extends StatelessWidget {
  final HolidayGate gate;
  const HolidayGateBanner({super.key, required this.gate});

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gate.blockedTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  gate.blockedMessage,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
