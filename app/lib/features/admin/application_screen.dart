import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/admin_repository.dart';
import '../../data/onboarding_repository.dart';
import '../home/profile_screen.dart';
import 'admin_home.dart';

typedef _Applicant = (AppRole role, String userId);

final _answersProvider = FutureProvider.autoDispose.family<(List<QuestionStep>, Map<String, Object?>), _Applicant>(
  (ref, applicant) async {
    final repository = ref.watch(onboardingRepositoryProvider);
    final results = await Future.wait([repository.loadSteps(applicant.$1), repository.loadAnswers(applicant.$2)]);
    return (results[0] as List<QuestionStep>, results[1] as Map<String, Object?>);
  },
);

final _certificatesProvider = FutureProvider.autoDispose.family<List<Certificate>, String>(
  (ref, coachId) => ref.watch(onboardingRepositoryProvider).loadCertificates(coachId),
);

final _assignmentsProvider = FutureProvider.autoDispose.family<List<Assignment>, String>(
  (ref, traineeId) => ref.watch(adminRepositoryProvider).activeAssignments(traineeId),
);

final _coachesProvider = FutureProvider.autoDispose<List<CoachOption>>(
  (ref) => ref.watch(adminRepositoryProvider).coaches(),
);

/// Review one sign-up: answers (and certificates for coaches), assign
/// coaches for trainees, then approve or reject.
class ApplicationScreen extends ConsumerStatefulWidget {
  const ApplicationScreen({super.key, required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends ConsumerState<ApplicationScreen> {
  bool _busy = false;

  Future<void> _review(PendingApplication item, ApplicationStatus status) async {
    if (status == ApplicationStatus.rejected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(context.l10n.rejectConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.reject)),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).review(item.application.id, status);
      ref.invalidate(pendingApplicationsProvider);
      if (mounted) {
        showMessage(context, status == ApplicationStatus.approved ? context.l10n.approved : context.l10n.rejected);
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = ref.watch(pendingApplicationsProvider);
    final item = pending.value?.where((p) => p.application.id == widget.applicationId).firstOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: pending.isLoading ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
      );
    }
    final role = item.application.role ?? AppRole.trainee;
    final applicant = item.applicant;
    final isTrainee = role == AppRole.trainee;
    final hasCoach = !isTrainee || (ref.watch(_assignmentsProvider(applicant.id)).value?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(title: Text(applicant.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ApplicantCard(applicant: applicant, role: role),
          if (isTrainee) _AssignmentsCard(traineeId: applicant.id),
          if (!isTrainee) _CertificatesCard(coachId: applicant.id),
          _AnswersCard(applicant: (role, applicant.id)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasCoach)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l10n.approveNeedsCoach)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _review(item, ApplicationStatus.rejected),
                      child: Text(l10n.reject),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: BusyButton(
                      label: l10n.approve,
                      busy: _busy,
                      onPressed: hasCoach ? () => _review(item, ApplicationStatus.approved) : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              ...children,
            ],
          ),
        ),
      );
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.applicant, required this.role});

  final Profile applicant;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dob = applicant.dateOfBirth;
    final age = dob == null ? null : DateTime.now().difference(dob).inDays ~/ 365;
    return _Section(
      title: roleLabel(context, role),
      children: [
        ListTile(
          title: Text(applicant.gender == 'female' ? l10n.female : l10n.male),
          subtitle: Text([
            if (age != null) '$age',
            if (applicant.heightCm != null) '${applicant.heightCm} cm',
          ].join(' · ')),
        ),
        if (applicant.phone != null)
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: Text(applicant.phone!, textDirection: TextDirection.ltr),
            onTap: () => launchUrl(Uri(scheme: 'tel', path: applicant.phone)),
          ),
      ],
    );
  }
}

class _AssignmentsCard extends ConsumerWidget {
  const _AssignmentsCard({required this.traineeId});

  final String traineeId;

  Future<void> _assign(BuildContext context, WidgetRef ref, String scopeKey) async {
    final coaches = await ref.read(_coachesProvider.future);
    if (!context.mounted) return;
    final coach = await showDialog<CoachOption>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.assignCoach(_scopeLabel(context, scopeKey))),
        children: [
          for (final coach in coaches)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, coach), child: Text(coach.fullName)),
        ],
      ),
    );
    if (coach == null) return;
    try {
      await ref.read(adminRepositoryProvider).assignCoach(traineeId: traineeId, coachId: coach.id, scopeKey: scopeKey);
      ref.invalidate(_assignmentsProvider(traineeId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static String _scopeLabel(BuildContext context, String key) =>
      key == 'nutrition' ? context.l10n.scopeNutrition : context.l10n.scopeWorkout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(_assignmentsProvider(traineeId));
    return _Section(
      title: context.l10n.assignedCoaches,
      children: assignments.when(
        loading: () => [const LinearProgressIndicator()],
        error: (error, _) => [ListTile(title: Text(errorMessage(context, error)))],
        data: (list) => [
          for (final scope in const ['workout', 'nutrition'])
            switch (list.where((a) => a.scopeKey == scope).firstOrNull) {
              final assignment? => ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(assignment.coachName),
                  subtitle: Text(_scopeLabel(context, scope)),
                ),
              null => ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(context.l10n.assignCoach(_scopeLabel(context, scope))),
                  onTap: () => _assign(context, ref, scope),
                ),
            },
        ],
      ),
    );
  }
}

class _CertificatesCard extends ConsumerWidget {
  const _CertificatesCard({required this.coachId});

  final String coachId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificates = ref.watch(_certificatesProvider(coachId));
    return _Section(
      title: context.l10n.certificates,
      children: certificates.when(
        loading: () => [const LinearProgressIndicator()],
        error: (error, _) => [ListTile(title: Text(errorMessage(context, error)))],
        data: (list) => [
          for (final certificate in list)
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(certificate.title),
              subtitle: certificate.issuer == null ? null : Text(certificate.issuer!),
              trailing: TextButton(
                child: Text(context.l10n.open),
                onPressed: () async {
                  try {
                    final url = await ref.read(adminRepositoryProvider).certificateUrl(certificate);
                    await launchUrl(Uri.parse(url));
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswersCard extends ConsumerWidget {
  const _AnswersCard({required this.applicant});

  final _Applicant applicant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(_answersProvider(applicant));
    return answers.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => ListTile(title: Text(errorMessage(context, error))),
      data: (result) {
        final (steps, values) = result;
        return Column(
          children: [
            for (final step in steps)
              _Section(
                title: step.section == null
                    ? context.l10n.answers
                    : localized(context, step.section!.titleEn, step.section!.titleAr),
                children: [
                  for (final question in step.questions)
                    ListTile(
                      title: Text(localized(context, question.textEn, question.textAr)),
                      subtitle: Text(formatAnswer(context, question, values[question.id])),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// An answer as the admin reads it: option labels, yes/no, joined lists.
String formatAnswer(BuildContext context, Question question, Object? value) {
  if (value == null) return context.l10n.noAnswer;
  String optionLabel(Object? v) {
    final option = question.options.where((o) => o.value == v).firstOrNull;
    return option == null ? '$v' : localized(context, option.labelEn, option.labelAr);
  }

  return switch (question.type) {
    AnswerType.boolean => value == true ? context.l10n.yes : context.l10n.no,
    AnswerType.singleChoice => optionLabel(value),
    AnswerType.multiChoice => (value as List).map(optionLabel).join('، '),
    AnswerType.timeList => (value as List).join('  '),
    AnswerType.number => value is num && value == value.roundToDouble() ? '${value.toInt()}' : '$value',
    _ => '$value',
  };
}
