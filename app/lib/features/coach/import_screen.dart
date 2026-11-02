import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/library_repository.dart';
import 'excel_plan.dart';
import 'exercise_picker.dart';

/// What an exercise name from the sheet resolves to.
class _Resolution {
  _Resolution({this.match, this.suggestion});

  /// Exact name or saved alias: linked automatically.
  ExerciseMatch? match;

  /// Close match waiting for "Did you mean ...?".
  ExerciseMatch? suggestion;

  /// Picked or confirmed by the coach.
  Exercise? chosen;
  bool createNew = false;

  bool get resolved => match != null || chosen != null || createNew;
}

String rowErrorText(BuildContext context, RowError e) => switch (e) {
      RowError.missingDay => context.l10n.errMissingDay,
      RowError.missingDayName => context.l10n.errMissingDayName,
      RowError.missingOrder => context.l10n.errMissingOrder,
      RowError.missingExercise => context.l10n.errMissingExercise,
      RowError.badSets => context.l10n.errBadSets,
      RowError.badReps => context.l10n.errBadReps,
    };

/// Excel upload: download the template, fill it in, upload, check the
/// preview (errors highlighted, names matched to the library), import.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.traineeId});

  /// Null imports into a new template.
  final String? traineeId;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _fileName;
  List<PlanRow> _rows = const [];
  final Map<String, _Resolution> _names = {};
  int _cycleLength = 7;
  bool _busy = false;

  bool get _hasErrors => _rows.any((r) => r.errors.isNotEmpty);
  bool get _allResolved => _names.values.every((r) => r.resolved);

  Future<void> _downloadTemplate() async {
    final bytes = Uint8List.fromList(buildTemplate());
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: 'workout-template.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      fileNameOverrides: const ['workout-template.xlsx'],
    ));
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final rows = parseWorkbook(await file.readAsBytes());
      final library = ref.read(libraryRepositoryProvider);
      final names = {for (final r in rows) if (r.exercise != null) r.exercise!};
      final matches = await Future.wait([for (final n in names) library.matchExercise(n)]);
      _names.clear();
      var i = 0;
      for (final name in names) {
        final best = matches[i++].firstOrNull;
        _names[name] = best == null
            ? _Resolution()
            : best.exact
                ? _Resolution(match: best)
                : _Resolution(suggestion: best);
      }
      final maxDay = rows.map((r) => r.dayNumber ?? 0).fold(0, (a, b) => a > b ? a : b);
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _cycleLength = maxDay < 1 ? 7 : maxDay;
      });
    } catch (e) {
      if (mounted) showMessage(context, context.l10n.couldNotReadFile);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final library = ref.read(libraryRepositoryProvider);
      final editor = ref.read(planEditorRepositoryProvider);
      // Resolve every name to an exercise id; confirmed spellings become aliases.
      final ids = <String, String>{};
      for (final entry in _names.entries) {
        final r = entry.value;
        if (r.match != null) {
          ids[entry.key] = r.match!.exerciseId;
        } else if (r.chosen != null) {
          ids[entry.key] = r.chosen!.id;
          await library.saveAlias(r.chosen!.id, entry.key);
        } else {
          final tracking = _rows.firstWhere((row) => row.exercise == entry.key).tracking;
          ids[entry.key] = (await library.createExercise(nameEn: entry.key, tracking: tracking)).id;
        }
      }
      // A new plan, or a new version of the trainee's current plan.
      final current = widget.traineeId == null ? null : await ref.read(workoutRepositoryProvider).activePlan(widget.traineeId!);
      final String versionId;
      final String planId;
      if (current == null) {
        planId = await editor.createWorkoutPlan(
          traineeId: widget.traineeId,
          name: (_fileName ?? 'Plan').replaceAll(RegExp(r'\.xlsx$'), ''),
          cycleLength: _cycleLength,
        );
        versionId = (await ref.read(workoutRepositoryProvider).plan(planId)).latest!.id;
      } else {
        planId = current.id;
        versionId = await editor.addEmptyWorkoutVersion(planId, _cycleLength, sourceFile: _fileName);
      }
      final days = <int, List<PlanRow>>{};
      for (final row in _rows) {
        days.putIfAbsent(row.dayNumber!, () => []).add(row);
      }
      for (final entry in days.entries) {
        final dayId = await editor.addDay(versionId, entry.key, entry.value.first.dayName!);
        final rows = entry.value..sort((a, b) => a.order!.compareTo(b.order!));
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          await editor.saveDayExercise(
            dayId,
            DayExercise(
              id: '',
              exercise: Exercise(id: ids[r.exercise]!, nameEn: r.exercise!, tracking: r.tracking),
              sortOrder: i + 1,
              sets: r.sets!,
              repsMin: r.repsMin,
              repsMax: r.repsMax,
              durationSeconds: r.durationSeconds,
              distanceM: r.distanceM,
              restSeconds: r.restSeconds,
              tempo: r.tempo,
              supersetGroup: r.superset,
              videoUrl1: r.video1,
              videoUrl2: r.video2,
              coachNotes: r.notes,
            ),
          );
        }
      }
      if (mounted) {
        showMessage(context, context.l10n.planImported);
        context.pop(planId);
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
    final theme = Theme.of(context);
    final maxDay = _rows.map((r) => r.dayNumber ?? 0).fold(0, (a, b) => a > b ? a : b);
    return FormScaffold(
      title: l10n.uploadExcel,
      primary: BusyButton(
        label: _rows.isEmpty ? l10n.chooseExcelFile : l10n.importPlan,
        busy: _busy,
        onPressed: _rows.isEmpty
            ? _pick
            : (_hasErrors || !_allResolved)
                ? () => showMessage(context, _hasErrors ? l10n.fixErrorsFirst : l10n.resolveNamesFirst)
                : _import,
      ),
      secondary: _rows.isEmpty
          ? TextButton.icon(icon: const Icon(Icons.download), label: Text(l10n.downloadTemplate), onPressed: _downloadTemplate)
          : TextButton(onPressed: _busy ? null : _pick, child: Text(l10n.chooseAnotherFile)),
      children: [
        if (_rows.isEmpty) ...[
          Text(l10n.uploadExcelHint, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Text(templateColumns.join(' · '), style: theme.textTheme.bodySmall),
        ] else ...[
          Text(_fileName ?? '', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.cycleLength),
            subtitle: Text(l10n.cycleLengthHint),
            trailing: NumberStepper(value: _cycleLength, min: maxDay < 1 ? 1 : maxDay, max: 28, onChanged: (v) => setState(() => _cycleLength = v.toInt())),
          ),
          if (_names.isNotEmpty) SectionTitle(l10n.exerciseNames),
          for (final entry in _names.entries) _NameTile(name: entry.key, resolution: entry.value, onChanged: () => setState(() {})),
          SectionTitle(l10n.preview),
          for (final row in _rows)
            Card(
              color: row.errors.isEmpty ? null : theme.colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                title: Text('${l10n.dayNumber(row.dayNumber ?? 0)} · ${row.dayName ?? '?'} — ${row.exercise ?? '?'}'),
                subtitle: Text(row.errors.isEmpty
                    ? '${row.sets} × ${row.repsMin ?? ''}${row.repsMax == null ? '' : '-${row.repsMax}'}'
                        '${row.durationSeconds == null ? '' : ' ${row.durationSeconds}s'}${row.distanceM == null ? '' : ' ${formatNum(row.distanceM)}m'}'
                    : '${l10n.rowNumber(row.rowNumber)}: ${row.errors.map((e) => rowErrorText(context, e)).join(', ')}'),
              ),
            ),
        ],
      ],
    );
  }
}

class _NameTile extends StatelessWidget {
  const _NameTile({required this.name, required this.resolution, required this.onChanged});

  final String name;
  final _Resolution resolution;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = resolution;
    final String status;
    final IconData icon;
    if (r.match != null) {
      status = l10n.linkedTo(r.match!.nameEn);
      icon = Icons.link;
    } else if (r.chosen != null) {
      status = l10n.linkedTo(r.chosen!.nameEn);
      icon = Icons.check_circle_outline;
    } else if (r.createNew) {
      status = l10n.willCreateExercise;
      icon = Icons.add_circle_outline;
    } else if (r.suggestion != null) {
      status = l10n.didYouMean(r.suggestion!.nameEn);
      icon = Icons.help_outline;
    } else {
      status = l10n.noMatch;
      icon = Icons.error_outline;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text(status),
      trailing: r.match != null
          ? null
          : Wrap(spacing: 4, children: [
              if (r.suggestion != null && r.chosen == null && !r.createNew)
                FilledButton.tonal(
                  onPressed: () {
                    r.chosen = Exercise(id: r.suggestion!.exerciseId, nameEn: r.suggestion!.nameEn, tracking: Tracking.weightReps);
                    onChanged();
                  },
                  child: Text(l10n.yes),
                ),
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'pick') {
                    final picked = await pickExercise(context, initialQuery: name);
                    if (picked != null) {
                      r
                        ..chosen = picked
                        ..createNew = false;
                    }
                  } else {
                    r
                      ..createNew = true
                      ..chosen = null;
                  }
                  onChanged();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'pick', child: Text(l10n.chooseExercise)),
                  PopupMenuItem(value: 'new', child: Text(l10n.createAsNew)),
                ],
              ),
            ]),
    );
  }
}
