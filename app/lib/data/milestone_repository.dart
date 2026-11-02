import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';
import '../core/plan_models.dart';

class MilestoneField {
  const MilestoneField({required this.id, required this.key, required this.labelEn, required this.labelAr, required this.isImage});

  final int id;
  final String key;
  final String labelEn;
  final String labelAr;
  final bool isImage;

  String label(BuildContext context) => localized(context, labelEn, labelAr);

  factory MilestoneField.fromJson(Map<String, dynamic> json) => MilestoneField(
        id: json['id'] as int,
        key: json['key'] as String,
        labelEn: json['label_en'] as String,
        labelAr: json['label_ar'] as String,
        isImage: json['kind'] == 'image',
      );
}

class MilestoneValue {
  const MilestoneValue({required this.fieldId, this.numberValue, this.imagePath});

  final int fieldId;
  final num? numberValue;
  final String? imagePath;
}

enum MilestoneStatus { submitted, due, missed, upcoming }

class Milestone {
  const Milestone({
    required this.id,
    required this.dueDate,
    required this.requested,
    required this.values,
    this.title,
    this.scheduleName,
    this.submittedAt,
  });

  final String id;
  final String? title;
  final String? scheduleName;
  final DateTime dueDate;
  final DateTime? submittedAt;

  /// Fields asked for, with whether each is required.
  final List<(MilestoneField, bool)> requested;
  final Map<int, MilestoneValue> values;

  String get name => title ?? scheduleName ?? '';

  MilestoneStatus status(DateTime today) {
    if (submittedAt != null) return MilestoneStatus.submitted;
    final due = dateOnly(dueDate);
    if (due.isAfter(today)) return MilestoneStatus.upcoming;
    return due == today ? MilestoneStatus.due : MilestoneStatus.missed;
  }

  bool get missingRequired => requested.any((r) => r.$2 && !values.containsKey(r.$1.id));

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
        id: json['id'] as String,
        title: json['title'] as String?,
        scheduleName: (json['schedule'] as Map<String, dynamic>?)?['name'] as String?,
        dueDate: DateTime.parse(json['due_date'] as String),
        submittedAt: json['submitted_at'] == null ? null : DateTime.parse(json['submitted_at'] as String),
        requested: [
          for (final r in (json['milestone_request_fields'] as List? ?? const []).cast<Map<String, dynamic>>())
            (MilestoneField.fromJson(r['field'] as Map<String, dynamic>), r['is_required'] as bool),
        ]..sort((a, b) => a.$1.id.compareTo(b.$1.id)),
        values: {
          for (final v in (json['milestone_values'] as List? ?? const []).cast<Map<String, dynamic>>())
            v['field_id'] as int: MilestoneValue(
              fieldId: v['field_id'] as int,
              numberValue: v['number_value'] as num?,
              imagePath: v['image_path'] as String?,
            ),
        },
      );
}

class MilestoneSchedule {
  const MilestoneSchedule({
    required this.id,
    required this.name,
    required this.everyNDays,
    required this.startsOn,
    required this.isActive,
    required this.fields,
  });

  final String id;
  final String name;
  final int everyNDays;
  final DateTime startsOn;
  final bool isActive;
  final List<(MilestoneField, bool)> fields;

  factory MilestoneSchedule.fromJson(Map<String, dynamic> json) => MilestoneSchedule(
        id: json['id'] as String,
        name: json['name'] as String,
        everyNDays: json['every_n_days'] as int,
        startsOn: DateTime.parse(json['starts_on'] as String),
        isActive: json['is_active'] as bool,
        fields: [
          for (final f in (json['milestone_schedule_fields'] as List? ?? const []).cast<Map<String, dynamic>>())
            (MilestoneField.fromJson(f['field'] as Map<String, dynamic>), f['is_required'] as bool),
        ],
      );
}

class MilestoneRepository {
  MilestoneRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'milestone-images';

  Future<List<MilestoneField>> fields() async {
    final rows = await _client.from('milestone_fields').select().order('sort_order');
    return rows.map(MilestoneField.fromJson).toList();
  }

  Future<List<Milestone>> forTrainee(String traineeId) async {
    final rows = await _client
        .from('milestones')
        .select('id, title, due_date, submitted_at, schedule:milestone_schedules(name), '
            'milestone_request_fields(is_required, field:milestone_fields(*)), '
            'milestone_values(field_id, number_value, image_path)')
        .eq('trainee_id', traineeId)
        .order('due_date', ascending: false);
    return rows.map(Milestone.fromJson).toList();
  }

  Future<void> saveNumber(String milestoneId, int fieldId, num value) => _client
      .from('milestone_values')
      .upsert({'milestone_id': milestoneId, 'field_id': fieldId, 'number_value': value, 'image_path': null},
          onConflict: 'milestone_id,field_id');

  /// Uploads a photo to the private bucket (path starts with the trainee's
  /// id, which the storage policy checks) and links it to the milestone.
  Future<void> savePhoto(String traineeId, String milestoneId, MilestoneField field, Uint8List bytes) async {
    final path = '$traineeId/${milestoneId}_${field.key}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    await _client.from('milestone_values').upsert(
        {'milestone_id': milestoneId, 'field_id': field.id, 'number_value': null, 'image_path': path},
        onConflict: 'milestone_id,field_id');
  }

  /// Short-lived link; the storage policy applies the female image rule.
  Future<String> photoUrl(String path) => _client.storage.from(_bucket).createSignedUrl(path, 3600);

  Future<void> submit(String milestoneId) => _client
      .from('milestones')
      .update({'submitted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', milestoneId);

  // --- coach side ---------------------------------------------------------

  Future<void> addOneOff({
    required String traineeId,
    required String title,
    required DateTime dueDate,
    required Map<int, bool> fields,
  }) async {
    final row = await _client
        .from('milestones')
        .insert({'trainee_id': traineeId, 'title': title, 'due_date': isoDate(dueDate)})
        .select('id')
        .single();
    await _client.from('milestone_request_fields').insert([
      for (final f in fields.entries) {'milestone_id': row['id'], 'field_id': f.key, 'is_required': f.value},
    ]);
  }

  Future<void> deleteMilestone(String id) => _client.from('milestones').delete().eq('id', id);

  Future<List<MilestoneSchedule>> schedules(String traineeId) async {
    final rows = await _client
        .from('milestone_schedules')
        .select('*, milestone_schedule_fields(is_required, field:milestone_fields(*))')
        .eq('trainee_id', traineeId)
        .order('created_at');
    return rows.map(MilestoneSchedule.fromJson).toList();
  }

  Future<void> addSchedule({
    required String traineeId,
    required String name,
    required int everyNDays,
    required DateTime startsOn,
    required Map<int, bool> fields,
  }) async {
    final row = await _client
        .from('milestone_schedules')
        .insert({'trainee_id': traineeId, 'name': name, 'every_n_days': everyNDays, 'starts_on': isoDate(startsOn)})
        .select('id')
        .single();
    await _client.from('milestone_schedule_fields').insert([
      for (final f in fields.entries) {'schedule_id': row['id'], 'field_id': f.key, 'is_required': f.value},
    ]);
  }

  Future<void> setScheduleActive(String id, bool active) =>
      _client.from('milestone_schedules').update({'is_active': active}).eq('id', id);

  Future<void> deleteSchedule(String id) => _client.from('milestone_schedules').delete().eq('id', id);
}
