import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/docs_storage.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/docs_widgets.dart';

/// Teachers download the syllabus and scheme of work from the admin, and send
/// their lesson notes (PDF) back for approval.
class TeacherDocumentsScreen extends StatefulWidget {
  const TeacherDocumentsScreen({super.key});

  @override
  State<TeacherDocumentsScreen> createState() => _TeacherDocumentsScreenState();
}

class _TeacherDocumentsScreenState extends State<TeacherDocumentsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _schoolId;
  String _session = '';
  String _term = '';
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, String>> _assignments = []; // class + subject pairs

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
      final school = await retryRead(
        () async => await _supabase
            .from('schools')
            .select('current_session, current_term')
            .eq('id', schoolId)
            .single(),
      );
      final assignRows = await retryRead(
        () async => await _supabase
            .from('staff_assignments')
            .select('class_assigned, subject_assigned')
            .eq('staff_id', user.id),
      );
      final docs = await retryRead(
        () async => await _supabase
            .from('curriculum_docs')
            .select(
              'id, class_name, subject_name, kind, session, term, title, created_at',
            )
            .order('class_name')
            .order('subject_name')
            .order('created_at', ascending: false),
      );
      final notes = await retryRead(
        () async => await _supabase
            .from('lesson_notes')
            .select(
              'id, class_name, subject_name, session, term, week_no, topic, status, review_comment, file_size, updated_at',
            )
            .eq('teacher_id', user.id)
            .order('updated_at', ascending: false),
      );

      final seen = <String>{};
      final pairs = <Map<String, String>>[];
      for (final r in assignRows) {
        final c = (r['class_assigned'] ?? '').toString().trim();
        final s = (r['subject_assigned'] ?? '').toString().trim();
        if (c.isEmpty || s.isEmpty) continue;
        if (seen.add('${c.toLowerCase()}|${s.toLowerCase()}')) {
          pairs.add({'class': c, 'subject': s});
        }
      }
      if (!mounted) return;
      setState(() {
        _schoolId = schoolId;
        _session = (school['current_session'] ?? '').toString();
        _term = (school['current_term'] ?? '').toString();
        _assignments = pairs;
        _docs = List<Map<String, dynamic>>.from(docs);
        _notes = List<Map<String, dynamic>>.from(notes);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  Future<void> _openDoc(String table, String id) async {
    try {
      await DocsStorage.open(table, id);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _newNote() async {
    if (_schoolId == null) return;
    if (_assignments.isEmpty) {
      showDocSnack(
        context,
        'You have no class and subject assigned yet. Ask your school admin to assign them to you.',
        error: true,
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewNoteSheet(
        schoolId: _schoolId!,
        session: _session,
        term: _term,
        assignments: _assignments,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _noteActions(Map<String, dynamic> note) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteSheet(note: note, schoolId: _schoolId!),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'Lesson Notes & Documents',
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
                tabs: const [
                  Tab(text: 'FROM ADMIN', iconMargin: EdgeInsets.zero),
                  Tab(text: 'MY NOTES', iconMargin: EdgeInsets.zero),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: _loading ? null : _newNote,
            backgroundColor: primaryColor,
            elevation: 4,
            icon: const Icon(Icons.note_add_rounded, color: Colors.white),
            label: const Text(
              'NEW LESSON NOTE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : TabBarView(
                children: [
                  _buildDocs(isDark, primaryColor, textColor),
                  _buildNotes(isDark, primaryColor, textColor),
                ],
              ),
      ),
    );
  }

  // 🚨 UI UPGRADE: WhatsApp-style Edge-to-Edge List for Curriculum Docs
  Widget _buildDocs(bool isDark, Color primaryColor, Color textColor) {
    return RefreshIndicator(
      onRefresh: _load,
      color: primaryColor,
      child: _docs.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(
                  Icons.folder_open_rounded,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Nothing here yet.\n\nWhen your school admin sends the syllabus or the scheme of work for a subject you teach, it will appear here to download.',
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
                      for (int i = 0; i < _docs.length; i++) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.redAccent.withValues(
                              alpha: 0.1,
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            _docs[i]['title'].toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_docs[i]['class_name']} · ${_docs[i]['subject_name']}\n${kindLabel(_docs[i]['kind'].toString())} · ${_docs[i]['session']}${_docs[i]['term'] != null ? ' · ${_docs[i]['term']}' : ''} · ${formatShortDate(_docs[i]['created_at'])}',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            Icons.download_rounded,
                            color: primaryColor,
                          ),
                          onTap: () => _openDoc(
                            'curriculum_docs',
                            _docs[i]['id'] as String,
                          ),
                        ),
                        if (i < _docs.length - 1)
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

  // 🚨 UI UPGRADE: WhatsApp-style Edge-to-Edge List for Teacher Notes
  Widget _buildNotes(bool isDark, Color primaryColor, Color textColor) {
    return RefreshIndicator(
      onRefresh: _load,
      color: primaryColor,
      child: _notes.isEmpty
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
                    'No lesson notes yet.\n\nTap New lesson note to send a PDF for your admin to approve.',
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
                      for (int i = 0; i < _notes.length; i++) ...[
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
                            'Week ${_notes[i]['week_no']}: ${_notes[i]['topic']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_notes[i]['class_name']} · ${_notes[i]['subject_name']} · ${_notes[i]['term']}',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                NoteStatusChip(
                                  status: _notes[i]['status'].toString(),
                                ),
                                if (_notes[i]['status'] == 'returned' &&
                                    (_notes[i]['review_comment'] ?? '')
                                        .toString()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Admin: ${_notes[i]['review_comment']}',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey.shade400,
                          ),
                          onTap: () => _noteActions(_notes[i]),
                        ),
                        if (i < _notes.length - 1)
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

// ============================================================================
// New lesson note
// ============================================================================
class _NewNoteSheet extends StatefulWidget {
  final String schoolId;
  final String session;
  final String term;
  final List<Map<String, String>> assignments;
  const _NewNoteSheet({
    required this.schoolId,
    required this.session,
    required this.term,
    required this.assignments,
  });

  @override
  State<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends State<_NewNoteSheet> {
  final _supabase = Supabase.instance.client;
  final _topic = TextEditingController();
  int _pair = 0;
  int _week = 1;
  PickedPdf? _pdf;
  bool _busy = false;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final p = await DocsStorage.pickPdf(
        maxBytes: DocsStorage.maxLessonNoteBytes,
      );
      if (p != null && mounted) setState(() => _pdf = p);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _save({required bool submit}) async {
    if (_pdf == null || _topic.text.trim().isEmpty) {
      showDocSnack(
        context,
        'Enter the topic and choose your PDF first.',
        error: true,
      );
      return;
    }
    final a = widget.assignments[_pair];
    setState(() => _busy = true);
    try {
      final docId = newRequestId();
      final uploaded = await DocsStorage.upload(
        table: 'lesson_notes',
        docId: docId,
        schoolId: widget.schoolId,
        bytes: _pdf!.bytes,
        className: a['class'],
        subjectName: a['subject'],
      );
      await retryIdempotent(
        () async => await _supabase.from('lesson_notes').insert({
          'id': docId,
          'school_id': widget.schoolId,
          'class_name': a['class'],
          'subject_name': a['subject'],
          'session': widget.session,
          'term': widget.term,
          'week_no': _week,
          'topic': _topic.text.trim(),
          'file_key': uploaded.fileKey,
          'file_size': uploaded.fileSize,
          'status': submit ? 'submitted' : 'draft',
        }),
        maxAttempts: 2,
      );
      if (mounted) {
        showDocSnack(
          context,
          submit ? 'Sent to your admin for approval.' : 'Saved as a draft.',
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
            Text(
              'New Lesson Note',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.term}, ${widget.session}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            LabeledDropdown<int>(
              label: 'Class and subject',
              value: _pair,
              items: [
                for (var i = 0; i < widget.assignments.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${widget.assignments[i]['class']} · ${widget.assignments[i]['subject']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _pair = v ?? 0),
            ),
            const SizedBox(height: 16),
            LabeledDropdown<int>(
              label: 'Week',
              value: _week,
              items: [
                for (var w = 1; w <= 20; w++)
                  DropdownMenuItem(
                    value: w,
                    child: Text(
                      'Week $w',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _week = v ?? 1),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _topic,
              enabled: !_busy,
              maxLength: 200,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Topic',
                labelStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
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
            PdfPickerTile(pdf: _pdf, onPick: _busy ? null : _pick),
            const SizedBox(height: 6),
            Text(
              'Use a typed PDF of 2 MB or less.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: primaryColor.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _busy ? null : () => _save(submit: false),
                      child: Text(
                        'SAVE DRAFT',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
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
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _busy ? null : () => _save(submit: true),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'SUBMIT',
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
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// One lesson note: open, replace the file, submit, withdraw, remove
// ============================================================================
class _NoteSheet extends StatefulWidget {
  final Map<String, dynamic> note;
  final String schoolId;
  const _NoteSheet({required this.note, required this.schoolId});

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _supabase = Supabase.instance.client;
  bool _busy = false;

  String get _id => widget.note['id'] as String;
  String get _status => widget.note['status'].toString();

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        showDocSnack(context, okMessage);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  Future<void> _setStatus(String status) async {
    await retryIdempotent(
      () async => await _supabase
          .from('lesson_notes')
          .update({'status': status})
          .eq('id', _id),
      maxAttempts: 2,
    );
  }

  Future<void> _replaceFile({required bool thenSubmit}) async {
    final PickedPdf? pdf;
    try {
      pdf = await DocsStorage.pickPdf(maxBytes: DocsStorage.maxLessonNoteBytes);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
      return;
    }
    if (pdf == null) return;
    await _run(() async {
      final uploaded = await DocsStorage.upload(
        table: 'lesson_notes',
        docId: _id,
        schoolId: widget.schoolId,
        bytes: pdf!.bytes,
        className: widget.note['class_name'].toString(),
        subjectName: widget.note['subject_name'].toString(),
      );
      await retryIdempotent(
        () async => await _supabase
            .from('lesson_notes')
            .update({
              'file_key': uploaded.fileKey,
              'file_size': uploaded.fileSize,
              if (thenSubmit) 'status': 'submitted',
            })
            .eq('id', _id),
        maxAttempts: 2,
      );
    }, thenSubmit ? 'New file sent for approval.' : 'File replaced.');
  }

  Future<void> _remove() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove this lesson note?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        content: const Text('It will be permanently removed from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await retryIdempotent(
        () async => await _supabase
            .from('lesson_notes')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', _id),
        maxAttempts: 2,
      );
    }, 'Removed.');
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final editable = _status == 'draft' || _status == 'returned';

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black87;
    Color primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                        '${n['class_name']} · ${n['subject_name']} · ${n['term']}',
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

            if (_status == 'returned' &&
                (n['review_comment'] ?? '').toString().isNotEmpty) ...[
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
                          'ADMIN FEEDBACK',
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
                      n['review_comment'],
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

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
                  'OPEN PDF',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),

            if (editable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _replaceFile(thenSubmit: false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.swap_horiz_rounded, color: textColor),
                  label: Text(
                    'REPLACE PDF FILE',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _setStatus('submitted'),
                          'Sent to your admin for approval.',
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: Text(
                    _status == 'returned'
                        ? 'SUBMIT AGAIN'
                        : 'SUBMIT FOR APPROVAL',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text(
                    'Delete this note',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],

            if (_status == 'submitted') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _setStatus('draft'),
                          'Withdrawn. You can edit it now.',
                        ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.orange.shade700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.undo_rounded, color: Colors.orange.shade700),
                  label: Text(
                    'WITHDRAW TO EDIT',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],

            if (_status == 'approved')
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This note is approved and locked. Quiz questions will be generated from it.',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
