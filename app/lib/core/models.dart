import 'package:flutter/widgets.dart';

/// Roles the app has screens for. The database may hold more (roles are
/// data); unknown ones are ignored by the app.
enum AppRole {
  trainee,
  coach,
  admin;

  static AppRole? fromKey(String? key) {
    for (final role in values) {
      if (role.name == key) return role;
    }
    return null;
  }
}

enum ApplicationStatus {
  pending,
  approved,
  rejected;

  static ApplicationStatus fromKey(String key) => values.byName(key);
}

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.gender,
    required this.locale,
    this.dateOfBirth,
    this.heightCm,
    this.phone,
  });

  final String id;
  final String fullName;
  final String gender;
  final String locale;
  final DateTime? dateOfBirth;
  final num? heightCm;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        gender: json['gender'] as String,
        locale: json['locale'] as String? ?? 'ar',
        dateOfBirth: json['date_of_birth'] == null ? null : DateTime.parse(json['date_of_birth'] as String),
        heightCm: json['height_cm'] as num?,
        phone: json['phone'] as String?,
      );
}

class Application {
  const Application({required this.id, required this.role, required this.status, required this.submittedAt});

  final String id;
  final AppRole? role;
  final ApplicationStatus status;
  final DateTime submittedAt;

  factory Application.fromJson(Map<String, dynamic> json) => Application(
        id: json['id'] as String,
        role: AppRole.fromKey((json['role'] as Map<String, dynamic>?)?['key'] as String?),
        status: ApplicationStatus.fromKey(json['status'] as String),
        submittedAt: DateTime.parse(json['submitted_at'] as String),
      );
}

/// Everything the router needs to know about the signed-in user.
class SessionData {
  const SessionData({
    required this.userId,
    required this.email,
    required this.profile,
    required this.roles,
    required this.applications,
    required this.signupRole,
    this.signupMetadata = const {},
  });

  final String userId;
  final String? email;
  final Profile? profile;
  final Set<AppRole> roles;

  /// Newest first.
  final List<Application> applications;

  /// The entry point the user signed up through (trainee or coach).
  final AppRole signupRole;

  /// Sign-up form values kept in the auth metadata until onboarding is
  /// submitted (weight, consents), so they survive email confirmation.
  final Map<String, dynamic> signupMetadata;

  Application? latestApplicationFor(AppRole role) {
    for (final application in applications) {
      if (application.role == role) return application;
    }
    return null;
  }
}

class QuestionSection {
  const QuestionSection({required this.id, required this.key, required this.titleEn, required this.titleAr});

  final int id;
  final String key;
  final String titleEn;
  final String titleAr;

  factory QuestionSection.fromJson(Map<String, dynamic> json) => QuestionSection(
        id: json['id'] as int,
        key: json['key'] as String,
        titleEn: json['title_en'] as String,
        titleAr: json['title_ar'] as String,
      );
}

enum AnswerType { text, number, boolean, date, singleChoice, multiChoice, timeList }

AnswerType _answerType(String key) => switch (key) {
      'text' => AnswerType.text,
      'number' => AnswerType.number,
      'boolean' => AnswerType.boolean,
      'date' => AnswerType.date,
      'single_choice' => AnswerType.singleChoice,
      'multi_choice' => AnswerType.multiChoice,
      'time_list' => AnswerType.timeList,
      _ => throw ArgumentError('Unknown answer type: $key'),
    };

class QuestionOption {
  const QuestionOption({required this.value, required this.labelEn, required this.labelAr});

  final String value;
  final String labelEn;
  final String labelAr;

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
        value: json['value'] as String,
        labelEn: json['label_en'] as String,
        labelAr: json['label_ar'] as String,
      );
}

class Question {
  const Question({
    required this.id,
    required this.key,
    required this.sectionId,
    required this.textEn,
    required this.textAr,
    required this.type,
    required this.isRequired,
    this.hintEn,
    this.hintAr,
    this.min,
    this.max,
    this.options = const [],
  });

  final String id;
  final String key;
  final int? sectionId;
  final String textEn;
  final String textAr;
  final AnswerType type;
  final bool isRequired;
  final String? hintEn;
  final String? hintAr;
  final num? min;
  final num? max;
  final List<QuestionOption> options;

  factory Question.fromJson(Map<String, dynamic> json) {
    final options = (json['question_options'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
    return Question(
      id: json['id'] as String,
      key: json['key'] as String,
      sectionId: json['section_id'] as int?,
      textEn: json['text_en'] as String,
      textAr: json['text_ar'] as String,
      type: _answerType(json['answer_type'] as String),
      isRequired: json['is_required'] as bool,
      hintEn: json['hint_en'] as String?,
      hintAr: json['hint_ar'] as String?,
      min: json['min_value'] as num?,
      max: json['max_value'] as num?,
      options: options.map(QuestionOption.fromJson).toList(),
    );
  }
}

/// One step of the sign-up form: a section and its questions, in order.
class QuestionStep {
  const QuestionStep({required this.section, required this.questions});

  final QuestionSection? section;
  final List<Question> questions;
}

/// Picks the Arabic or English variant of database text for the UI locale.
String localized(BuildContext context, String en, String ar) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
