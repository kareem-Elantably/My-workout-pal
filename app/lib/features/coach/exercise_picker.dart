import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../auth/validators.dart';

String trackingLabel(BuildContext context, Tracking t) => switch (t) {
      Tracking.weightReps => context.l10n.trackingWeightReps,
      Tracking.reps => context.l10n.trackingReps,
      Tracking.duration => context.l10n.trackingDuration,
      Tracking.distanceDuration => context.l10n.trackingDistance,
    };

/// Search the exercise library (fuzzy), or add a custom exercise.
Future<Exercise?> pickExercise(BuildContext context, {String? initialQuery}) => showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: _ExerciseSearch(initialQuery: initialQuery)),
    );

class _ExerciseSearch extends ConsumerStatefulWidget {
  const _ExerciseSearch({this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<_ExerciseSearch> createState() => _ExerciseSearchState();
}

class _ExerciseSearchState extends ConsumerState<_ExerciseSearch> {
  Timer? _debounce;
  late final _query = TextEditingController(text: widget.initialQuery);
  late Future<List<Exercise>> _results = _search(widget.initialQuery ?? '');

  Future<List<Exercise>> _search(String q) => ref.read(libraryRepositoryProvider).searchExercises(q);

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showDialog<Exercise>(context: context, builder: (_) => NewExerciseDialog(name: _query.text));
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _query,
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.searchExercises),
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _results = _search(q)));
            },
          ),
        ),
        ListTile(leading: const Icon(Icons.add), title: Text(l10n.newExercise), onTap: _create),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _results = _search(_query.text)));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final list = snapshot.data!;
              if (list.isEmpty) return Center(child: Text(l10n.noResults));
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(list[i].name(context)),
                  subtitle: Text([trackingLabel(context, list[i].tracking), ?list[i].equipment].join(' · ')),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class NewExerciseDialog extends ConsumerStatefulWidget {
  const NewExerciseDialog({super.key, this.name, this.tracking});

  final String? name;
  final Tracking? tracking;

  @override
  ConsumerState<NewExerciseDialog> createState() => _NewExerciseDialogState();
}

class _NewExerciseDialogState extends ConsumerState<NewExerciseDialog> {
  late final _nameEn = TextEditingController(text: widget.name);
  final _nameAr = TextEditingController();
  late Tracking _tracking = widget.tracking ?? Tracking.weightReps;
  bool _busy = false;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.newExercise),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameEn, decoration: InputDecoration(labelText: l10n.nameEnglish), textInputAction: TextInputAction.next),
            const SizedBox(height: 12),
            TextField(controller: _nameAr, decoration: InputDecoration(labelText: l10n.nameArabicOptional)),
            const SizedBox(height: 12),
            DropdownButtonFormField<Tracking>(
              initialValue: _tracking,
              decoration: InputDecoration(labelText: l10n.loggedAs),
              items: [for (final t in Tracking.values) DropdownMenuItem(value: t, child: Text(trackingLabel(context, t)))],
              onChanged: (t) => setState(() => _tracking = t ?? _tracking),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_nameEn.text.trim().isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    final created = await ref
                        .read(libraryRepositoryProvider)
                        .createExercise(nameEn: _nameEn.text, nameAr: _nameAr.text, tracking: _tracking);
                    if (context.mounted) Navigator.pop(context, created);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Sets, reps (or time / distance), rest and notes for one exercise in a day.
Future<DayExercise?> editDayExercise(BuildContext context, {required Exercise exercise, DayExercise? current, required int sortOrder}) =>
    showModalBottomSheet<DayExercise>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayExerciseForm(exercise: exercise, current: current, sortOrder: sortOrder),
    );

class _DayExerciseForm extends StatefulWidget {
  const _DayExerciseForm({required this.exercise, required this.current, required this.sortOrder});

  final Exercise exercise;
  final DayExercise? current;
  final int sortOrder;

  @override
  State<_DayExerciseForm> createState() => _DayExerciseFormState();
}

class _DayExerciseFormState extends State<_DayExerciseForm> {
  final _form = GlobalKey<FormState>();
  late final c = widget.current;
  late final _sets = TextEditingController(text: '${c?.sets ?? 3}');
  late final _repsMin = TextEditingController(text: formatNum(c?.repsMin ?? (widget.exercise.tracking.usesReps ? 10 : null)));
  late final _repsMax = TextEditingController(text: formatNum(c?.repsMax));
  late final _duration = TextEditingController(text: formatNum(c?.durationSeconds));
  late final _distance = TextEditingController(text: formatNum(c?.distanceM));
  late final _rest = TextEditingController(text: formatNum(c?.restSeconds ?? 90));
  late final _tempo = TextEditingController(text: c?.tempo);
  late final _superset = TextEditingController(text: c?.supersetGroup);
  late final _video1 = TextEditingController(text: c?.videoUrl1);
  late final _video2 = TextEditingController(text: c?.videoUrl2);
  late final _notes = TextEditingController(text: c?.coachNotes);

  @override
  void dispose() {
    for (final t in [_sets, _repsMin, _repsMax, _duration, _distance, _rest, _tempo, _superset, _video1, _video2, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  int? _i(TextEditingController t) => parseNumber(t.text)?.round();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = widget.exercise.tracking;
    Widget num(TextEditingController c, String label, {bool required = false}) => Expanded(
          child: TextFormField(
            controller: c,
            decoration: InputDecoration(labelText: label),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (v) => validateNumber(context, v, required: required, min: required ? 1 : 0),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(widget.exercise.name(context), style: Theme.of(context).textTheme.titleLarge),
            Text(trackingLabel(context, t), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(children: [
              num(_sets, l10n.sets, required: true),
              const SizedBox(width: 12),
              if (t.usesReps) ...[
                num(_repsMin, l10n.repsFrom, required: true),
                const SizedBox(width: 12),
                num(_repsMax, l10n.repsTo),
              ] else if (t == Tracking.duration)
                num(_duration, l10n.durationSeconds, required: true)
              else ...[
                num(_distance, l10n.distanceMeters),
                const SizedBox(width: 12),
                num(_duration, l10n.durationSeconds),
              ],
            ]),
            const SizedBox(height: 12),
            Row(children: [
              num(_rest, l10n.restSecondsLabel),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _tempo, decoration: InputDecoration(labelText: l10n.tempoLabel))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _superset, decoration: InputDecoration(labelText: l10n.supersetLabel))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _video1, decoration: InputDecoration(labelText: l10n.videoLink), keyboardType: TextInputType.url),
            const SizedBox(height: 12),
            TextFormField(controller: _video2, decoration: InputDecoration(labelText: l10n.videoLink2), keyboardType: TextInputType.url),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, decoration: InputDecoration(labelText: l10n.coachNotes), maxLines: 2),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                final repsMin = t.usesReps ? _i(_repsMin) : null;
                final repsMax = t.usesReps ? _i(_repsMax) : null;
                if (repsMax != null && repsMin != null && repsMax < repsMin) {
                  showMessage(context, l10n.repsRangeInvalid);
                  return;
                }
                if (t == Tracking.distanceDuration && _i(_distance) == null && _i(_duration) == null) {
                  showMessage(context, l10n.distanceOrTimeRequired);
                  return;
                }
                Navigator.pop(
                  context,
                  DayExercise(
                    id: c?.id ?? '',
                    exercise: widget.exercise,
                    sortOrder: c?.sortOrder ?? widget.sortOrder,
                    sets: _i(_sets)!,
                    repsMin: repsMin,
                    repsMax: repsMax,
                    durationSeconds: t.usesDuration ? _i(_duration) : null,
                    distanceM: t.usesDistance ? parseNumber(_distance.text) : null,
                    restSeconds: _i(_rest),
                    tempo: _tempo.text,
                    supersetGroup: _superset.text,
                    videoUrl1: _video1.text,
                    videoUrl2: _video2.text,
                    coachNotes: _notes.text,
                  ),
                );
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
