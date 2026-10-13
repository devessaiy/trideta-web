import 'package:flutter/material.dart';
import 'package:trideta_v2/services/docs_storage.dart';

const List<String> kMonthsShort = [
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

String formatShortDate(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  return '${d.day} ${kMonthsShort[d.month - 1]} ${d.year}';
}

String kindLabel(String kind) =>
    kind == 'syllabus' ? 'Syllabus' : 'Scheme of work';

String friendlyDocError(Object e) {
  if (e is DocsStorageException) return e.message;
  final s = e.toString();
  if (s.contains('NOTE_COMMENT'))
    return 'Please add a comment when returning a note.';
  if (s.contains('NOTE_STATE')) {
    return 'This note cannot be changed in its current state. Refresh and try again.';
  }
  if (s.contains('NOTE_LOCKED'))
    return 'This note is locked and cannot be changed.';
  if (s.contains('23505') || s.contains('duplicate key')) {
    return 'A lesson note for that week already exists for this subject. Open it from your list to replace the file.';
  }
  return 'Something went wrong. Please check your connection and try again.';
}

// 🚨 UI UPGRADE: Replaced Native Snackbar with a Premium Custom Popup
void showDocSnack(BuildContext context, String message, {bool error = false}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color primaryColor = error ? Colors.redAccent : Colors.green;
  final IconData icon = error
      ? Icons.error_outline_rounded
      : Icons.check_circle_outline_rounded;
  final String title = error ? "Action Failed" : "Success";

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey.shade600,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "OKAY",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class NoteStatusChip extends StatelessWidget {
  final String status;
  const NoteStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    switch (status) {
      case 'submitted':
        color = Colors.orange.shade800;
        label = 'Waiting for review';
        break;
      case 'approved':
        color = Colors.green.shade700;
        label = 'Approved';
        break;
      case 'returned':
        color = Colors.red.shade700;
        label = 'Returned';
        break;
      default:
        color = Colors.grey.shade700;
        label = 'Draft';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: Theme.of(context).primaryColor,
          ),
        ),
      ),
    );
  }
}

class PdfPickerTile extends StatelessWidget {
  final PickedPdf? pdf;
  final VoidCallback? onPick;
  const PdfPickerTile({super.key, required this.pdf, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final has = pdf != null;
    final primaryColor = Theme.of(context).primaryColor;

    return OutlinedButton.icon(
      onPressed: onPick,
      icon: Icon(
        has ? Icons.picture_as_pdf_rounded : Icons.attach_file_rounded,
        color: has ? Colors.redAccent : primaryColor,
      ),
      label: Text(
        has
            ? '${pdf!.name} (${(pdf!.size / 1024).round()} KB)'
            : 'Choose a PDF file',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: has ? Colors.redAccent : primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(55),
        backgroundColor: (has ? Colors.redAccent : primaryColor).withValues(
          alpha: 0.05,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
