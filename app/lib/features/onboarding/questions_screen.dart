import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../router/redirect.dart';
import 'question_field.dart';

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
    if (_steps.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
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

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final step = _steps[_index];
      await ref.read(onboardingRepositoryProvider).saveAnswers(_session.userId, {
        for (final question in step.questions) question.id: _normalized(_answers[question.id]),
      });
      if (_index == _steps.length - 1) {
        await _finish();
      } else {
        setState(() => _index++);
        _scroll.jumpTo(0);
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

  Future<void> _finish() async {
    final session = _session;
    if (session.signupRole == AppRole.coach) {
      if (mounted) context.go(Routes.certificates);
      return;
    }
    await ref.read(onboardingRepositoryProvider).submitApplication(session, AppRole.trainee);
    await ref.read(sessionProvider.notifier).refresh(); // the router moves on to the waiting screen
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || _steps.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: snapshot.hasError
                ? ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _loading = _load()))
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final step = _steps[_index];
        final section = step.section;
        final isLast = _index == _steps.length - 1;
        final willSubmit = isLast && _session.signupRole == AppRole.trainee;
        return PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _index--);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(section == null ? '' : localized(context, section.titleEn, section.titleAr)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: (_index + 1) / _steps.length),
              ),
            ),
            body: Form(
              key: _formKey,
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                itemCount: step.questions.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 24),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text(l10n.stepOf(_index + 1, _steps.length), style: Theme.of(context).textTheme.labelLarge);
                  }
                  final question = step.questions[i - 1];
                  return QuestionField(
                    key: ValueKey(question.id),
                    question: question,
                    value: _answers[question.id],
                    timeSlots: question.type == AnswerType.timeList ? _mealSlots : null,
                    onChanged: (value) => setState(() => _answers[question.id] = value),
                  );
                },
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    if (_index > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => setState(() => _index--),
                          child: Text(l10n.back),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: BusyButton(label: willSubmit ? l10n.submit : l10n.next, busy: _busy, onPressed: _next),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
