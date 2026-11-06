import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trideta_v2/services/docs_storage.dart';
import 'package:trideta_v2/utils/resilient_request.dart';
import 'package:trideta_v2/widgets/docs_widgets.dart';

/// The school admin sends the syllabus and the scheme of work (PDF) to the
/// teachers of each subject and class.
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this document?'),
        content: const Text(
          'Teachers will no longer see it. You can send a new one at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _IssueDocSheet(
        schoolId: _schoolId!,
        session: _session,
        term: _term,
        classes: _classes,
      ),
    );
    if (created == true) {
      if (mounted) showDocSnack(context, 'Sent to the teachers of that subject.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final d in _docs) {
      if (d['deleted_at'] != null) continue;
      grouped.putIfAbsent(d['class_name'].toString(), () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Curriculum Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _issue,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Send document'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: grouped.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'No documents yet.\n\nTap Send document to send a syllabus or a scheme of work to the teachers of a subject. They will be able to download it.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          for (final d in entry.value)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                                title: Text(d['title'].toString()),
                                subtitle: Text(
                                  '${d['subject_name']} · ${kindLabel(d['kind'].toString())} · ${d['session']}${d['term'] != null ? ' · ${d['term']}' : ''}\nSent ${formatShortDate(d['created_at'])}',
                                ),
                                isThreeLine: true,
                                onTap: () => _open(d),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) => v == 'open' ? _open(d) : _remove(d),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'open', child: Text('Open')),
                                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                                  ],
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
      final p = await DocsStorage.pickPdf(maxBytes: DocsStorage.maxCurriculumBytes);
      if (p != null && mounted) setState(() => _pdf = p);
    } catch (e) {
      if (mounted) showDocSnack(context, friendlyDocError(e), error: true);
    }
  }

  Future<void> _send() async {
    if (_className == null || _subject == null || _pdf == null || _titleController.text.trim().isEmpty) {
      showDocSnack(context, 'Choose the class, the subject and a PDF file first.', error: true);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send a document to teachers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Teachers assigned to that subject and class can download it.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'syllabus', label: Text('Syllabus')),
                ButtonSegment(value: 'scheme', label: Text('Scheme of work')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _autoTitle();
              }),
            ),
            const SizedBox(height: 12),
            LabeledDropdown<String>(
              label: 'Class',
              value: _classId,
              items: [
                for (final c in widget.classes)
                  DropdownMenuItem(value: c['id'] as String, child: Text(c['name'].toString())),
              ],
              onChanged: _busy ? null : _onClassChanged,
            ),
            const SizedBox(height: 12),
            LabeledDropdown<String>(
              label: _loadingSubjects ? 'Subject (loading...)' : 'Subject',
              value: _subject,
              items: [
                for (final s in _subjects) DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _subject = v;
                      _autoTitle();
                    }),
            ),
            const SizedBox(height: 12),
            Text(
              _kind == 'scheme'
                  ? 'For ${widget.term}, ${widget.session}'
                  : 'For the ${widget.session} session',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              enabled: !_busy,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
            PdfPickerTile(pdf: _pdf, onPick: _busy ? null : _pick),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_busy ? 'Sending...' : 'Send to teachers'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
