import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DocsStorageException implements Exception {
  final String message;
  DocsStorageException(this.message);
  @override
  String toString() => message;
}

class UploadedDoc {
  final String fileKey;
  final int fileSize;
  const UploadedDoc(this.fileKey, this.fileSize);
}

class PickedPdf {
  final String name;
  final Uint8List bytes;
  const PickedPdf(this.name, this.bytes);
  int get size => bytes.length;
}

/// Talks to the 'docs-storage' function, which keeps the PDFs private in
/// Cloudflare R2. The app never sees any storage keys.
class DocsStorage {
  static const int maxCurriculumBytes = 5 * 1024 * 1024;
  static const int maxLessonNoteBytes = 2 * 1024 * 1024;

  static SupabaseClient get _client => Supabase.instance.client;
  static String get _endpoint =>
      '${Supabase.instance.client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '')}/functions/v1/docs-storage';

  static Map<String, String> _headers({String? contentType}) {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw DocsStorageException('Please sign in again.');
    return {
      'Authorization': 'Bearer $token',
      'apikey': Supabase.instance.client.rest.headers['apikey'] ?? '',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  static String _messageFrom(http.Response res) {
    String? serverError;
    try {
      final data = jsonDecode(res.body);
      if (data is Map && data['error'] != null) {
        serverError = data['error'].toString();
      }
    } catch (_) {}
    switch (serverError) {
      case 'STORAGE_NOT_CONFIGURED':
        return 'Document storage is not set up yet. Please try again later.';
      case 'Not allowed':
        return 'You are not allowed to do that for this class and subject.';
      case 'The file is too large':
        return 'The file is too large. Please compress the PDF and try again.';
      case 'Only PDF files are accepted':
        return 'Only PDF files are accepted.';
    }
    if (res.statusCode == 401) return 'Please sign in again.';
    if (res.statusCode == 404) return 'This document could not be found.';
    return serverError ?? 'Something went wrong. Please try again.';
  }

  /// Lets the user choose a PDF and checks its size.
  static Future<PickedPdf?> pickPdf({required int maxBytes}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      throw DocsStorageException('Could not read the file. Please try again.');
    }
    if (bytes.length > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw DocsStorageException(
        'The file is too large. The limit is $mb MB. Please compress the PDF and try again.',
      );
    }
    return PickedPdf(f.name, bytes);
  }

  /// Uploads a PDF. [table] is 'curriculum_docs' or 'lesson_notes'.
  static Future<UploadedDoc> upload({
    required String table,
    required String docId,
    required String schoolId,
    required Uint8List bytes,
    String? className,
    String? subjectName,
  }) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'action': 'upload',
        'table': table,
        'doc_id': docId,
        'school_id': schoolId,
        if (className != null) 'class_name': className,
        if (subjectName != null) 'subject_name': subjectName,
      },
    );
    final http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: _headers(contentType: 'application/pdf'),
            body: bytes,
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw DocsStorageException(
        'Could not upload. Please check your connection and try again.',
      );
    }
    if (res.statusCode != 200) throw DocsStorageException(_messageFrom(res));
    final data = jsonDecode(res.body) as Map;
    return UploadedDoc(
      data['file_key'] as String,
      (data['file_size'] as num).toInt(),
    );
  }

  /// Opens a document in the phone's PDF viewer or the browser.
  static Future<void> open(String table, String id) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_endpoint?action=download'),
            headers: _headers(contentType: 'application/json'),
            body: jsonEncode({'table': table, 'id': id}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw DocsStorageException(
        'Could not open the document. Please check your connection.',
      );
    }
    if (res.statusCode != 200) throw DocsStorageException(_messageFrom(res));
    final url = (jsonDecode(res.body) as Map)['url'] as String;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw DocsStorageException('No app was found to open PDF files.');
  }
}
