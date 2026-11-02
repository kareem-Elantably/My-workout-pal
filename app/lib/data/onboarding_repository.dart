import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/models.dart';

class Certificate {
  const Certificate({required this.id, required this.title, required this.filePath, this.issuer});

  final String id;
  final String title;
  final String? issuer;
  final String filePath;

  factory Certificate.fromJson(Map<String, dynamic> json) => Certificate(
        id: json['id'] as String,
        title: json['title'] as String,
        issuer: json['issuer'] as String?,
        filePath: json['file_path'] as String,
      );
}

class OnboardingRepository {
  OnboardingRepository(this._client);

  final SupabaseClient _client;

  /// The sign-up form for a role: one step per section, in section order.
  /// Questions without a section form a last step.
  Future<List<QuestionStep>> loadSteps(AppRole role) async {
    final results = await Future.wait<dynamic>([
      _client.from('question_sections').select().order('sort_order'),
      _client
          .from('questions')
          .select('*, question_options(*), role:roles!inner(key)')
          .eq('role.key', role.name)
          .eq('is_active', true)
          .order('sort_order'),
    ]);
    final sections = (results[0] as List).cast<Map<String, dynamic>>().map(QuestionSection.fromJson).toList();
    final questions = (results[1] as List).cast<Map<String, dynamic>>().map(Question.fromJson).toList();

    final steps = <QuestionStep>[
      for (final section in sections)
        QuestionStep(section: section, questions: questions.where((q) => q.sectionId == section.id).toList()),
      QuestionStep(section: null, questions: questions.where((q) => q.sectionId == null).toList()),
    ];
    return steps.where((step) => step.questions.isNotEmpty).toList();
  }

  /// question id -> answer value
  Future<Map<String, Object?>> loadAnswers(String userId) async {
    final rows = await _client.from('answers').select('question_id, value').eq('user_id', userId);
    return {for (final row in rows) row['question_id'] as String: row['value']};
  }

  /// Saves the given answers; a null value deletes a previous answer.
  Future<void> saveAnswers(String userId, Map<String, Object?> answers) async {
    final upserts = [
      for (final entry in answers.entries)
        if (entry.value != null) {'user_id': userId, 'question_id': entry.key, 'value': entry.value},
    ];
    final cleared = [for (final entry in answers.entries) if (entry.value == null) entry.key];
    if (upserts.isNotEmpty) {
      await _client.from('answers').upsert(upserts, onConflict: 'user_id,question_id');
    }
    if (cleared.isNotEmpty) {
      await _client.from('answers').delete().eq('user_id', userId).inFilter('question_id', cleared);
    }
  }

  Future<List<Certificate>> loadCertificates(String coachId) async {
    final rows = await _client.from('coach_certificates').select().eq('coach_id', coachId).order('uploaded_at');
    return rows.map(Certificate.fromJson).toList();
  }

  Future<void> uploadCertificate({
    required String coachId,
    required String title,
    String? issuer,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$coachId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client.storage.from('certificates').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentType(safeName)),
        );
    await _client.from('coach_certificates').insert({
      'coach_id': coachId,
      'title': title,
      if (issuer != null && issuer.isNotEmpty) 'issuer': issuer,
      'file_path': path,
    });
  }

  /// Final step of sign-up: record consents, save the sign-up weight as the
  /// first milestone (trainees), and submit the application.
  Future<void> submitApplication(SessionData session, AppRole role) async {
    final consents = (session.signupMetadata['consents'] as List? ?? const []).cast<String>();
    if (consents.isNotEmpty) {
      await _client.from('consents').upsert(
        [for (final kind in consents) {'user_id': session.userId, 'kind': kind, 'version': Env.consentVersion}],
        onConflict: 'user_id,kind,version',
        ignoreDuplicates: true,
      );
    }

    final weight = session.signupMetadata['weight_kg'] as num?;
    if (role == AppRole.trainee && weight != null) {
      await _saveSignupWeight(session.userId, weight);
    }

    final roleRow = await _client.from('roles').select('id').eq('key', role.name).single();
    await _client.from('applications').insert({'user_id': session.userId, 'role_id': roleRow['id']});
  }

  Future<void> _saveSignupWeight(String userId, num weight) async {
    const title = 'Sign-up weight';
    final existing = await _client.from('milestones').select('id').eq('trainee_id', userId).eq('title', title).limit(1);
    if (existing.isNotEmpty) return;

    final field = await _client.from('milestone_fields').select('id').eq('key', 'weight').single();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final milestone =
        await _client.from('milestones').insert({'trainee_id': userId, 'title': title, 'due_date': today}).select('id').single();
    await _client.from('milestone_values').insert({
      'milestone_id': milestone['id'],
      'field_id': field['id'],
      'number_value': weight,
    });
    await _client
        .from('milestones')
        .update({'submitted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', milestone['id']);
  }

  static String _contentType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
