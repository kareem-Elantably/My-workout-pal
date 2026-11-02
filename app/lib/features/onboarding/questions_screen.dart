import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';
import 'certificates_screen.dart';
import 'question_field.dart';
import 'sign_out_action.dart';

/// The sign-up questions for the user's role, one section per step. Each
/// step is saved when the user moves on, so a closed app resumes where it
/// left off. Coaches continue to certificates; trainees submit at the end.
class QuestionsScreen extends ConsumerStatefulWidget {
  const QuestionsScreen({super.key});

  @override
  ConsumerState<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends ConsumerState<QuestionsScreen> {
  late Future<void> _loading = _load();
  List<QuestionStep> _steps = const [];
  final Map<String, Object?> _answers = {};
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  int _index = 0;
  bool _busy = false;

  SessionData get _session => (ref.read(sessionProvider).requireValue as SignedIn).data;

  bool get _isCoach => _session.signupRole == AppRole.coach;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(onboardingRepositoryProvider);
    final session = _session;
    final results = await Future.wait([
      repository.loadSteps(session.signupRole),
      repository.loadAnswers(session.userId),
    ]);
    _steps = results[0] as List<QuestionStep>;
    _answers.addAll(results[1] as Map<String, Object?>);
    if (_steps.isEmpty && !_isCoach && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submitTrainee());
    }
  }

  Question? _questionByKey(String key) {
    for (final step in _steps) {
      for (final question in step.questions) {
        if (question.key == key) return question;
      }
    }
    return null;
  }

  /// One time picker per meal once the meals-per-day answer is known.
  int? get _mealSlots {
    final mealsQuestion = _questionByKey('meals_per_day');
    final meals = mealsQuestion == null ? null : _answers[mealsQuestion.id];
    return meals is num ? meals.toInt().clamp(1, 8) : null;
  }

  void _previous() {
    setState(() => _index--);
    _scroll.jumpTo(0);
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final step = _steps[_index];
      await ref.read(onboardingRepositoryProvider).saveAnswers(_session.userId, {
        for (final question in step.questions) question.id: _normalized(_answers[question.id]),
      });
      if (_index < _steps.length - 1) {
        setState(() => _index++);
        _scroll.jumpTo(0);
      } else if (_isCoach) {
        if (mounted) await context.push(Routes.certificates); // back returns to the last step
      } else {
        await _submitTrainee();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Incomplete time lists are not saved (each entry must be a time).
  Object? _normalized(Object? value) {
    if (value is List && (value.isEmpty || value.contains(''))) return null;
    return value;
  }

  Future<void> _submitTrainee() async {
    await ref.read(onboardingRepositoryProvider).submitApplication(_session, AppRole.trainee);
    await ref.read(sessionProvider.notifier).refresh(); // the router moves on to the waiting screen
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && _steps.isEmpty && _isCoach) {
          return const CertificatesScreen(); // no coach questions: straight to certificates
        }
        if (snapshot.connectionState != ConnectionState.done || _steps.isEmpty) {
          return Scaffold(
            appBar: AppBar(actions: const [SignOutAction()]),
            body: snapshot.hasError
                ? ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _loading = _load()))
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final step = _steps[_index];
        final section = step.section;
        final isLast = _index == _steps.length - 1;
        return PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _previous();
          },
          child: FormScaffold(
            title: section == null ? '' : localized(context, section.titleEn, section.titleAr),
            formKey: _formKey,
            scrollController: _scroll,
            progress: (_index + 1) / _steps.length,
            automaticallyImplyLeading: false,
            actions: const [SignOutAction()],
            leading: _index == 0
                ? null
                : OutlinedButton(onPressed: _busy ? null : _previous, child: Text(l10n.back)),
            primary: BusyButton(
              label: isLast && !_isCoach ? l10n.submit : l10n.next,
              busy: _busy,
              onPressed: _next,
            ),
            children: [
              Text(l10n.stepOf(_index + 1, _steps.length), style: Theme.of(context).textTheme.labelLarge),
              for (final question in step.questions) ...[
                const SizedBox(height: 24),
                QuestionField(
                  key: ValueKey(question.id),
                  question: question,
                  value: _answers[question.id],
                  timeSlots: question.type == AnswerType.timeList ? _mealSlots : null,
                  onChanged: (value) => setState(() => _answers[question.id] = value),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
