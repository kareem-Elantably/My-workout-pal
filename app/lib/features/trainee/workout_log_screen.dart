import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import 'today_tab.dart';

/// Values of one set row while logging.
class _SetRow {
  _SetRow({this.reps, this.weight, this.durationSeconds, this.distanceM, this.loggedId});

  int? reps;
  num? weight;
  int? durationSeconds;
  num? distanceM;

  /// Set when saved; a saved set shows as ticked.
  String? loggedId;

  bool get done => loggedId != null;
}

/// Logging one workout day on a date: every set is pre-filled from last
/// time (or the plan's target), so a normal set is one tap on the tick.
class WorkoutLogScreen extends ConsumerStatefulWidget {
  const WorkoutLogScreen({super.key, required this.workoutDayId, required this.date});

  final String workoutDayId;
  final DateTime date;

  @override
  ConsumerState<WorkoutLogScreen> createState() => _WorkoutLogScreenState();
}

class _WorkoutLogScreenState extends ConsumerState<WorkoutLogScreen> {
  late Future<void> _loading = _load();
  WorkoutDay? _day;
  WorkoutSession? _session;
  final Map<String, List<_SetRow>> _rows = {};
  bool _busy = false;
  Timer? _restTimer;
  int _restLeft = 0;

  bool get _editable => !widget.date.isBefore(today().subtract(const Duration(days: 7)));

  @override
  void dispose() {
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final me = ref.read(myIdProvider);
    final repo = ref.read(workoutRepositoryProvider);
    final plan = await repo.activePlan(me);
    _day = plan?.versions.expand((v) => v.days).where((d) => d.id == widget.workoutDayId).firstOrNull;
    if (_day == null) return;
    final session = await repo.sessionOn(me, widget.date);
    // A session for this date on another day is replaced only if the user agrees.
    _session = session?.workoutDayId == widget.workoutDayId ? session : null;
    final last = await Future.wait([for (final e in _day!.exercises) repo.lastValues(me, e.exercise.id)]);
    for (var i = 0; i < _day!.exercises.length; i++) {
      final exercise = _day!.exercises[i];
      final logged = {for (final s in _session?.sets ?? const <SetLog>[]) if (s.dayExerciseId == exercise.id) s.setNumber: s};
      final count = [exercise.sets, ...logged.keys].reduce((a, b) => a > b ? a : b);
      _rows[exercise.id] = [
        for (var n = 1; n <= count; n++)
          () {
            final saved = logged[n];
            // Same set number last time, else last time's final set.
            final previous = last[i][n] ?? (last[i].isEmpty ? null : last[i][last[i].keys.reduce((a, b) => a > b ? a : b)]);
            return _SetRow(
              reps: saved?.reps ?? previous?.reps ?? exercise.repsMax ?? exercise.repsMin,
              weight: saved?.weightKg ?? previous?.weightKg ?? 0,
              durationSeconds: saved?.durationSeconds ?? previous?.durationSeconds ?? exercise.durationSeconds,
              distanceM: saved?.distanceM ?? previous?.distanceM ?? exercise.distanceM,
              loggedId: saved?.id,
            );
          }(),
      ];
    }
  }

  Future<String?> _ensureSession() async {
    if (_session != null) return _session!.id;
    final me = ref.read(myIdProvider);
    final repo = ref.read(workoutRepositoryProvider);
    final existing = await repo.sessionOn(me, widget.date);
    if (existing != null && existing.workoutDayId != widget.workoutDayId) {
      if (!mounted || !await confirm(context, context.l10n.replaceWorkoutConfirm, action: context.l10n.replace)) return null;
      await repo.deleteSession(existing.id);
    }
    _session = existing?.workoutDayId == widget.workoutDayId ? existing : await repo.startSession(me, widget.workoutDayId, widget.date);
    return _session!.id;
  }

  Future<void> _toggle(DayExercise exercise, int index) async {
    final row = _rows[exercise.id]![index];
    setState(() => _busy = true);
    try {
      final repo = ref.read(workoutRepositoryProvider);
      if (row.done) {
        await repo.deleteSet(row.loggedId!);
        row.loggedId = null;
      } else {
        final sessionId = await _ensureSession();
        if (sessionId == null) return;
        final t = exercise.exercise.tracking;
        final saved = await repo.saveSet(
          sessionId: sessionId,
          dayExercise: exercise,
          setNumber: index + 1,
          reps: t.usesReps ? row.reps ?? 0 : null,
          weightKg: t.usesWeight ? row.weight ?? 0 : null,
          durationSeconds: t.usesDuration ? row.durationSeconds ?? 0 : null,
          distanceM: t.usesDistance ? row.distanceM ?? 0 : null,
        );
        row.loggedId = saved.id;
        _startRest(exercise.restSeconds);
      }
      ref.invalidate(todayDataProvider(widget.date));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Changing a saved set saves the new values.
  Future<void> _edit(DayExercise exercise, int index, void Function(_SetRow row) change) async {
    final row = _rows[exercise.id]![index];
    setState(() => change(row));
    if (!row.done) return;
    try {
      final t = exercise.exercise.tracking;
      await ref.read(workoutRepositoryProvider).saveSet(
            sessionId: _session!.id,
            dayExercise: exercise,
            setNumber: index + 1,
            reps: t.usesReps ? row.reps ?? 0 : null,
            weightKg: t.usesWeight ? row.weight ?? 0 : null,
            durationSeconds: t.usesDuration ? row.durationSeconds ?? 0 : null,
            distanceM: t.usesDistance ? row.distanceM ?? 0 : null,
          );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _startRest(int? seconds) {
    _restTimer?.cancel();
    if (seconds == null || seconds <= 0) return;
    setState(() => _restLeft = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _restLeft--);
      if (_restLeft <= 0) timer.cancel();
    });
  }

  Future<void> _finish() async {
    if (_session == null) {
      showMessage(context, context.l10n.logOneSetFirst);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(workoutRepositoryProvider).finishSession(_session!.id, note: _session!.note);
      ref.invalidate(todayDataProvider(widget.date));
      if (mounted) {
        showMessage(context, context.l10n.workoutSaved);
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
    return FutureBuilder(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || _day == null) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorRetry(error: snapshot.error ?? l10n.somethingWentWrong, onRetry: () => setState(() => _loading = _load())),
          );
        }
        final day = _day!;
        return FormScaffold(
          title: '${l10n.dayNumber(day.dayNumber)} · ${day.name}',
          primary: _editable
              ? BusyButton(label: l10n.finishWorkout, busy: _busy, onPressed: _finish)
              : FilledButton(onPressed: null, child: Text(l10n.olderThanAWeek)),
          secondary: _restLeft > 0
              ? Text(l10n.restTimer('${_restLeft ~/ 60}:${(_restLeft % 60).toString().padLeft(2, '0')}'),
                  style: Theme.of(context).textTheme.titleMedium)
              : null,
          children: [
            for (final exercise in day.exercises)
              _ExerciseCard(
                exercise: exercise,
                rows: _rows[exercise.id]!,
                enabled: _editable && !_busy,
                onToggle: (i) => _toggle(exercise, i),
                onEdit: (i, change) => _edit(exercise, i, change),
                onAddSet: () => setState(() {
                  final rows = _rows[exercise.id]!;
                  final last = rows.isEmpty ? null : rows.last;
                  rows.add(_SetRow(reps: last?.reps, weight: last?.weight, durationSeconds: last?.durationSeconds, distanceM: last?.distanceM));
                }),
              ),
          ],
        );
      },
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.rows,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
    required this.onAddSet,
  });

  final DayExercise exercise;
  final List<_SetRow> rows;
  final bool enabled;
  final ValueChanged<int> onToggle;
  final void Function(int index, void Function(_SetRow row) change) onEdit;
  final VoidCallback onAddSet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = exercise.exercise.tracking;
    final details = [
      exercise.target(),
      if (exercise.restSeconds != null) l10n.restSeconds(exercise.restSeconds!),
      if (exercise.tempo != null) l10n.tempo(exercise.tempo!),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (exercise.supersetGroup != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Chip(label: Text(l10n.superset(exercise.supersetGroup!)), visualDensity: VisualDensity.compact),
                  ),
                Expanded(child: Text(exercise.exercise.name(context), style: theme.textTheme.titleMedium)),
              ],
            ),
            Text(details.join(' · '), style: theme.textTheme.bodySmall),
            if (exercise.coachNotes != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('💬 ${exercise.coachNotes}', style: theme.textTheme.bodyMedium),
              ),
            if (exercise.videoUrl1 != null || exercise.videoUrl2 != null)
              Wrap(spacing: 8, children: [
                for (final url in [exercise.videoUrl1, exercise.videoUrl2].whereType<String>())
                  ActionChip(
                    avatar: const Icon(Icons.play_circle_outline),
                    label: Text(l10n.watchVideo),
                    onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  ),
              ]),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 28, child: Text('${i + 1}', style: theme.textTheme.titleSmall)),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (t.usesWeight)
                            NumberStepper(
                              value: rows[i].weight ?? 0,
                              step: 2.5,
                              decimals: 1,
                              suffix: ' ${l10n.kg}',
                              onChanged: (v) => onEdit(i, (r) => r.weight = v),
                            ),
                          if (t.usesReps)
                            NumberStepper(
                              value: rows[i].reps ?? 0,
                              suffix: ' ×',
                              onChanged: (v) => onEdit(i, (r) => r.reps = v.toInt()),
                            ),
                          if (t == Tracking.duration)
                            NumberStepper(
                              value: rows[i].durationSeconds ?? 0,
                              step: 5,
                              suffix: ' ${l10n.secondsShort}',
                              onChanged: (v) => onEdit(i, (r) => r.durationSeconds = v.toInt()),
                            ),
                          if (t == Tracking.distanceDuration) ...[
                            NumberStepper(
                              value: (rows[i].distanceM ?? 0) / 1000,
                              step: 0.1,
                              decimals: 1,
                              suffix: ' ${l10n.km}',
                              onChanged: (v) => onEdit(i, (r) => r.distanceM = v * 1000),
                            ),
                            NumberStepper(
                              value: (rows[i].durationSeconds ?? 0) ~/ 60,
                              suffix: ' ${l10n.minutesShort}',
                              onChanged: (v) => onEdit(i, (r) => r.durationSeconds = v.toInt() * 60),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton.filled(
                      tooltip: rows[i].done ? l10n.undoSet : l10n.logSet,
                      isSelected: rows[i].done,
                      icon: const Icon(Icons.check),
                      style: rows[i].done ? null : IconButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerHighest, foregroundColor: theme.colorScheme.onSurfaceVariant),
                      onPressed: enabled ? () => onToggle(i) : null,
                    ),
                  ],
                ),
              ),
            if (enabled)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(onPressed: onAddSet, icon: const Icon(Icons.add), label: Text(l10n.addSet)),
              ),
          ],
        ),
      ),
    );
  }
}
