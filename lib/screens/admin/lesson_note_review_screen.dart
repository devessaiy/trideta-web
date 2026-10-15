import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/docs_storage.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/docs_widgets.dart';

class LessonNoteReviewScreen extends StatefulWidget {
  const LessonNoteReviewScreen({super.key});

  @override
  State<LessonNoteReviewScreen> createState() => _LessonNoteReviewScreenState();
}

class _LessonNoteReviewScreenState extends State<LessonNoteReviewScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _notes = [];
  Map<String, String> _teacherNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final profile = await retryRead(
        () async => await _supabase
            .from('profiles')
            .select('school_id')
            .eq('id', user.id)
            .single(),
      );
      final schoolId = profile['school_id'] as String;
      final notes = await retryRead(
        () async => await _supabase
            .from('lesson_notes')
            .select(
              'id, class_name, subject_name, term, week_no, topic, status, review_comment, teacher_id, submitted_at, reviewed_at, updated_at',
            )
            .eq('school_id', schoolId)
            .neq('status', 'draft')
            .order('updated_at', ascending: false),
      );
      final list = List<Map<String, dynamic>>.from(notes);
      final ids = list.map((n) => n['teacher_id'].toString()).toSet().toList();
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final people = await retryRead(
          () async => await _supabase
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', ids),
        );
        for (final p in people) {
          names[p['id'].toString()] = (p['full_name'] ?? 'Teacher').toString();
        }
      }
      if (!mounted) return;
      setState(() {
        _notes = list;
        _teacherNames = names;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  Future<void> _review(Map<String, dynamic> note) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        note: note,
        teacherName: _teacherNames[note['teacher_id'].toString()] ?? 'Teacher',
      ),
    );
    if (changed == true) await _load();
  }

  List<Map<String, dynamic>> _by(String status) =>
      _notes.where((n) => n['status'] == status).toList();

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'Lesson Note Approvals',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: bgColor,
          foregroundColor: textColor,
          elevation: 0,
          centerTitle: true,
          // 🚨 UI UPGRADE: Integrated the exact AlertsScreen TabBar layout
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark
                    ? Colors.white54
                    : Colors.grey.shade600,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                tabs: [
                  Tab(
                    text: 'WAITING (${_by('submitted').length})',
                    iconMargin: EdgeInsets.zero,
                  ),
                  const Tab(text: 'APPROVED', iconMargin: EdgeInsets.zero),
                  const Tab(text: 'RETURNED', iconMargin: EdgeInsets.zero),
                ],
              ),
            ),
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : TabBarView(
                children: [
                  _list(
                    _by('submitted'),
                    'No lesson notes are waiting for review.',
                    isDark,
                    primaryColor,
                  ),
                  _list(
                    _by('approved'),
                    'No approved lesson notes yet.',
                    isDark,
                    primaryColor,
                  ),
                  _list(
                    _by('returned'),
                    'No returned lesson notes.',
                    isDark,
                    primaryColor,
                  ),
                ],
              ),
      ),
    );
  }

  // 🚨 UI UPGRADE: WhatsApp-style Edge-to-Edge List
  Widget _list(
    List<Map<String, dynamic>> items,
    String empty,
    bool isDark,
    Color primaryColor,
  ) {
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return RefreshIndicator(
      onRefresh: _load,
      color: primaryColor,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(
                  Icons.inventory_2_outlined,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    empty,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 100),
              children: [
                Container(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  child: Column(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '${items[i]['class_name']} · ${items[i]['subject_name']} · Wk ${items[i]['week_no']}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: primaryColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${items[i]['topic']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_teacherNames[items[i]['teacher_id'].toString()] ?? 'Teacher'} · ${formatShortDate(items[i]['submitted_at'] ?? items[i]['updated_at'])}',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey.shade400,
                          ),
                          onTap: () => _review(items[i]),
                        ),
                        if (i < items.length - 1)
                          Padding(
                            padding: const EdgeInsets.only(left: 80, right: 24),
                            child: Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  final Map<String, dynamic> note;
  final String teacherName;
  const _ReviewSheet({required this.note, required this.teacherName});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _supabase = Supabase.instance.client;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _returning = false;

  String get _id => widget.note['id'] as String;
  String get _status => widget.note['status'].toString();

  @override
  void initState() {
    super.initState();
    _comment.text = (widget.note['review_comment'] ?? '').toString();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _decide(String status) async {
    if (status == 'returned' && _comment.text.trim().isEmpty) {
      showDocSnack(
        context,
        'Please write a comment for the teacher.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await retryIdempotent(
        () async => await _supabase
            .from('lesson_notes')
            .update({
              'status': status,
              if (status == 'returned') 'review_comment': _comment.text.trim(),
            })
            .eq('id', _id),
        maxAttempts: 2,
      );
      if (mounted) {
        showDocSnack(
          context,
          status == 'approved' ? 'Approved.' : 'Returned to the teacher.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week ${n['week_no']}: ${n['topic']}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${n['class_name']} · ${n['subject_name']} · ${n['term']}\nBy ${widget.teacherName}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                NoteStatusChip(status: _status),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                          DocsStorage.open('lesson_notes', _id).catchError((e) {
                            if (mounted) {
                              showDocSnack(
                                context,
                                friendlyDocError(e),
                                error: true,
                              );
                            }
                          }),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(Icons.picture_as_pdf_rounded, color: primaryColor),
                label: Text(
                  'OPEN LESSON NOTE',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_status == 'submitted' || _status == 'approved') ...[
              if (_returning || _status == 'approved') ...[
                TextField(
                  controller: _comment,
                  enabled: !_busy,
                  maxLines: 3,
                  maxLength: 1000,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Comment for the teacher',
                    hintText: 'What should be corrected?',
                    labelStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _busy ? null : () => _decide('returned'),
                    icon: const Icon(Icons.reply_rounded, color: Colors.white),
                    label: const Text(
                      'RETURN TO TEACHER',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
              if (_status == 'submitted') ...[
                if (!_returning)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 55,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.redAccent.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _returning = true),
                            child: const Text(
                              'REJECT',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 55,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _busy ? null : () => _decide('approved'),
                            child: const Text(
                              'APPROVE',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _returning = false),
                      child: const Text(
                        'Cancel Return',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ] else if (_status == 'returned') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.comment_rounded,
                          color: Colors.redAccent,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'YOUR FEEDBACK',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      n['review_comment'] ?? '',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Waiting for the teacher to fix it and send it again.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
