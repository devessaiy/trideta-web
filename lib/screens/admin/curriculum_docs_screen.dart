import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/docs_storage.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/docs_widgets.dart';

class CurriculumDocsScreen extends StatefulWidget {
  const CurriculumDocsScreen({super.key});

  @override
  State<CurriculumDocsScreen> createState() => _CurriculumDocsScreenState();
}

class _CurriculumDocsScreenState extends State<CurriculumDocsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _schoolId;
  String _session = '';
  String _term = '';
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _docs = [];

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
      final classes = await retryRead(
        () async => await _supabase
            .from('classes')
            .select('id, name')
            .eq('school_id', schoolId)
            .order('list_order'),
      );
      final docs = await retryRead(
        () async => await _supabase
            .from('curriculum_docs')
            .select(
              'id, class_name, subject_name, kind, session, term, title, file_size, created_at',
            )
            .eq('school_id', schoolId)
            .order('class_name')
            .order('subject_name')
            .order('created_at', ascending: false),
      );
      if (!mounted) return;
      setState(() {
        _schoolId = schoolId;
        _session = (school['current_session'] ?? '').toString();
        _term = (school['current_term'] ?? '').toString();
        _classes = List<Map<String, dynamic>>.from(classes);
        _docs = List<Map<String, dynamic>>.from(docs);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  Future<void> _open(Map<String, dynamic> doc) async {
    try {
      await DocsStorage.open('curriculum_docs', doc['id'] as String);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _remove(Map<String, dynamic> doc) async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Document?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        content: const Text(
          'Teachers will no longer see it. You can send a new one at any time.',
        ),
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
    try {
      await retryIdempotent(
        () async => await _supabase
            .from('curriculum_docs')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', doc['id'] as String),
      );
      await _load();
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _issue() async {
    if (_schoolId == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IssueDocSheet(
        schoolId: _schoolId!,
        session: _session,
        term: _term,
        classes: _classes,
      ),
    );
    if (created == true) {
      if (mounted) {
        showDocSnack(context, 'Sent to the teachers of that subject.');
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC);
    Color primaryColor = Theme.of(context).primaryColor;
    Color textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final d in _docs) {
      if (d['deleted_at'] != null) continue;
      grouped.putIfAbsent(d['class_name'].toString(), () => []).add(d);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          'Curriculum Documents',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _issue,
        backgroundColor: primaryColor,
        elevation: 4,
        icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
        label: const Text(
          'SEND DOCUMENT',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: primaryColor,
              child: grouped.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          Icons.folder_open_rounded,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 20),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'No documents yet.\n\nTap Send document to send a syllabus or a scheme of work to the teachers of a subject.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  // 🚨 UI UPGRADE: WhatsApp-style Edge-to-Edge List
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: primaryColor,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          Container(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            child: Column(
                              children: [
                                for (
                                  int i = 0;
                                  i < entry.value.length;
                                  i++
                                ) ...[
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.redAccent
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                        Icons.picture_as_pdf_rounded,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      entry.value[i]['title'].toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textColor,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${entry.value[i]['subject_name']} · ${kindLabel(entry.value[i]['kind'].toString())}\nSent ${formatShortDate(entry.value[i]['created_at'])}',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                    isThreeLine: true,
                                    onTap: () => _open(entry.value[i]),
                                    trailing: PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                      color: isDark
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      onSelected: (v) => v == 'open'
                                          ? _open(entry.value[i])
                                          : _remove(entry.value[i]),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'open',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.open_in_new_rounded,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Open PDF',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                                color: Colors.redAccent,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.redAccent,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (i < entry.value.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 80,
                                        right: 24,
                                      ),
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
                      ],
                    ),
            ),
    );
  }
}

class _IssueDocSheet extends StatefulWidget {
  final String schoolId;
  final String session;
  final String term;
  final List<Map<String, dynamic>> classes;
  const _IssueDocSheet({
    required this.schoolId,
    required this.session,
    required this.term,
    required this.classes,
  });

  @override
  State<_IssueDocSheet> createState() => _IssueDocSheetState();
}

class _IssueDocSheetState extends State<_IssueDocSheet> {
  final _supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  String _kind = 'syllabus';
  String? _classId;
  String? _className;
  List<String> _subjects = [];
  String? _subject;
  PickedPdf? _pdf;
  bool _busy = false;
  bool _loadingSubjects = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _autoTitle() {
    if (_subject != null && _className != null) {
      _titleController.text = '$_subject ${kindLabel(_kind)} - $_className';
    }
  }

  Future<void> _onClassChanged(String? id) async {
    if (id == null) return;
    final cls = widget.classes.firstWhere((c) => c['id'] == id);
    setState(() {
      _classId = id;
      _className = cls['name'].toString();
      _subjects = [];
      _subject = null;
      _loadingSubjects = true;
    });
    try {
      final rows = await retryRead(
        () async => await _supabase
            .from('class_subjects')
            .select('subject_name')
            .eq('school_id', widget.schoolId)
            .eq('class_id', id)
            .order('subject_name'),
      );
      if (!mounted) return;
      setState(() {
        _subjects = rows.map((r) => r['subject_name'].toString()).toList();
        _loadingSubjects = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingSubjects = false);
        showDocSnack(context, friendlyDocError(e), error: true);
      }
    }
  }

  Future<void> _pick() async {
    try {
      final p = await DocsStorage.pickPdf(
        maxBytes: DocsStorage.maxCurriculumBytes,
      );
      if (p != null && mounted) setState(() => _pdf = p);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _send() async {
    if (_className == null ||
        _subject == null ||
        _pdf == null ||
        _titleController.text.trim().isEmpty) {
      showDocSnack(
        context,
        'Choose the class, the subject and a PDF file first.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final docId = newRequestId();
      final uploaded = await DocsStorage.upload(
        table: 'curriculum_docs',
        docId: docId,
        schoolId: widget.schoolId,
        bytes: _pdf!.bytes,
      );
      await retryIdempotent(
        () async => await _supabase.from('curriculum_docs').insert({
          'id': docId,
          'school_id': widget.schoolId,
          'class_name': _className,
          'subject_name': _subject,
          'kind': _kind,
          'session': widget.session,
          'term': _kind == 'scheme' ? widget.term : null,
          'title': _titleController.text.trim(),
          'file_key': uploaded.fileKey,
          'file_size': uploaded.fileSize,
        }),
        maxAttempts: 2,
      );
      if (mounted) Navigator.pop(context, true);
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
              'Send Document',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Teachers assigned to that subject and class can download it.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // 🚨 UI UPGRADE: Replaced SegmentedButton with AlertsScreen-style Pill Toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildPillToggle(
                    'syllabus',
                    'Syllabus',
                    isDark,
                    primaryColor,
                  ),
                  _buildPillToggle(
                    'scheme',
                    'Scheme of Work',
                    isDark,
                    primaryColor,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            LabeledDropdown<String>(
              label: 'Select Class',
              value: _classId,
              items: [
                for (final c in widget.classes)
                  DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(
                      c['name'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              onChanged: _busy ? null : _onClassChanged,
            ),
            const SizedBox(height: 16),
            LabeledDropdown<String>(
              label: _loadingSubjects
                  ? 'Subject (loading...)'
                  : 'Select Subject',
              value: _subject,
              items: [
                for (final s in _subjects)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _subject = v;
                      _autoTitle();
                    }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              enabled: !_busy,
              maxLength: 200,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Document Title',
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
                suffixText: _kind == 'scheme'
                    ? '${widget.term}, ${widget.session}'
                    : '${widget.session} session',
                suffixStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            PdfPickerTile(pdf: _pdf, onPick: _busy ? null : _pick),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                onPressed: _busy ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  _busy ? 'SENDING...' : 'SEND TO TEACHERS',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
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

  Widget _buildPillToggle(
    String value,
    String label,
    bool isDark,
    Color primaryColor,
  ) {
    bool isSelected = _kind == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _kind = value;
          _autoTitle();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white54 : Colors.grey.shade600),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
