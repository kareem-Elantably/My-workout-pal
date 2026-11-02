import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/milestone_repository.dart';
import '../../data/workout_repository.dart';
import '../auth/validators.dart';
import 'notifications_button.dart';

final milestonesProvider = FutureProvider.autoDispose.family<List<Milestone>, String>(
  (ref, traineeId) => ref.watch(milestoneRepositoryProvider).forTrainee(traineeId),
);

final _loggedExercisesProvider = FutureProvider.autoDispose.family<List<Exercise>, String>(
  (ref, traineeId) => ref.watch(workoutRepositoryProvider).loggedExercises(traineeId),
);

final _exerciseProgressProvider = FutureProvider.autoDispose.family<List<ProgressPoint>, (String, Exercise)>(
  (ref, args) => ref.watch(workoutRepositoryProvider).exerciseProgress(args.$1, args.$2),
);

final _photoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(milestoneRepositoryProvider).photoUrl(path),
);

String milestoneStatusLabel(BuildContext context, MilestoneStatus status) => switch (status) {
      MilestoneStatus.submitted => context.l10n.statusSubmitted,
      MilestoneStatus.due => context.l10n.statusDue,
      MilestoneStatus.missed => context.l10n.statusMissed,
      MilestoneStatus.upcoming => context.l10n.statusUpcoming,
    };

/// Weight over time, exercise progress and the list of check-ins.
class ProgressView extends ConsumerStatefulWidget {
  const ProgressView({super.key, required this.traineeId, this.isCoach = false});

  final String traineeId;
  final bool isCoach;

  @override
  ConsumerState<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends ConsumerState<ProgressView> {
  Exercise? _exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final milestones = ref.watch(milestonesProvider(widget.traineeId));
    final exercises = ref.watch(_loggedExercisesProvider(widget.traineeId));
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return AsyncBody(
      value: milestones,
      onRetry: () => ref.invalidate(milestonesProvider(widget.traineeId)),
      builder: (list) {
        // Weight is the only number field; every submitted number is a weigh-in.
        final weights = [
          for (final m in list.reversed)
            if (m.submittedAt != null)
              for (final v in m.values.values)
                if (v.numberValue != null) ProgressPoint(m.dueDate, v.numberValue!.toDouble()),
        ];
        final exercise = _exercise ?? exercises.value?.firstOrNull;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_loggedExercisesProvider(widget.traineeId));
            return ref.refresh(milestonesProvider(widget.traineeId).future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SectionTitle(l10n.weight),
              weights.length < 2
                  ? Padding(padding: const EdgeInsets.all(16), child: Text(l10n.notEnoughData))
                  : _LineChart(points: weights, unit: l10n.kg),
              SectionTitle(
                l10n.exerciseProgress,
                trailing: exercises.value == null || exercises.value!.isEmpty
                    ? null
                    : DropdownButton<Exercise>(
                        value: exercise,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in exercises.value!)
                            DropdownMenuItem(value: e, child: SizedBox(width: 180, child: Text(e.name(context), overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (e) => setState(() => _exercise = e),
                      ),
              ),
              if (exercise == null)
                Padding(padding: const EdgeInsets.all(16), child: Text(l10n.notEnoughData))
              else
                ref.watch(_exerciseProgressProvider((widget.traineeId, exercise))).when(
                      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                      error: (e, _) => Text(errorMessage(context, e)),
                      data: (points) => points.length < 2
                          ? Padding(padding: const EdgeInsets.all(16), child: Text(l10n.notEnoughData))
                          : _LineChart(
                              points: points,
                              unit: switch (exercise.tracking) {
                                Tracking.weightReps => l10n.kg,
                                Tracking.reps => '×',
                                Tracking.duration => l10n.secondsShort,
                                Tracking.distanceDuration => 'm',
                              },
                            ),
                    ),
              SectionTitle(
                l10n.checkIns,
                trailing: widget.isCoach && list.where((m) => m.submittedAt != null).length >= 2
                    ? TextButton.icon(
                        icon: const Icon(Icons.compare),
                        label: Text(l10n.compare),
                        onPressed: () => context.push('${rolePath(context)}/trainees/${widget.traineeId}/compare'),
                      )
                    : null,
              ),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noCheckIns)),
              for (final m in list)
                ListTile(
                  leading: Icon(switch (m.status(today())) {
                    MilestoneStatus.submitted => Icons.check_circle,
                    MilestoneStatus.due => Icons.radio_button_unchecked,
                    MilestoneStatus.missed => Icons.error_outline,
                    MilestoneStatus.upcoming => Icons.schedule,
                  }),
                  title: Text(m.name.isEmpty ? l10n.checkIn : m.name),
                  subtitle: Text('${format.format(m.dueDate)} · ${milestoneStatusLabel(context, m.status(today()))}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('${rolePath(context)}/milestone/${m.id}?trainee=${widget.traineeId}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points, required this.unit});

  final List<ProgressPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = points.first.date;
    final spots = [for (final p in points) FlSpot(p.date.difference(first).inDays.toDouble(), p.value)];
    final values = points.map((p) => p.value);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.15).clamp(1, double.infinity);
    final change = points.last.value - points.first.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
            child: Text(
              '${formatNum(points.last.value)} $unit  (${change >= 0 ? '+' : ''}${formatNum(change)})',
              style: Theme.of(context).textTheme.titleMedium,
              textDirection: TextDirection.ltr,
            ),
          ),
          SizedBox(
            height: 180,
            // Charts read left to right (time) in both languages.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(),
                  rightTitles: AxisTitles(),
                  bottomTitles: AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: scheme.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.08)),
                  ),
                ],
              )),
            ),
          ),
        ],
      ),
    );
  }
}

/// A private photo through a short-lived link (female image rule applies).
class MilestonePhoto extends ConsumerWidget {
  const MilestonePhoto({super.key, required this.path, this.height = 220});

  final String path;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(_photoUrlProvider(path)).when(
        loading: () => SizedBox(height: height, child: const Center(child: CircularProgressIndicator())),
        error: (_, _) => SizedBox(height: height, child: const Center(child: Icon(Icons.lock_outline))),
        data: (url) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, height: height, fit: BoxFit.cover, width: double.infinity),
        ),
      );
}

/// One check-in. The trainee fills it in and submits; coaches view it.
class MilestoneScreen extends ConsumerStatefulWidget {
  const MilestoneScreen({super.key, required this.milestoneId, required this.traineeId});

  final String milestoneId;
  final String traineeId;

  @override
  ConsumerState<MilestoneScreen> createState() => _MilestoneScreenState();
}

class _MilestoneScreenState extends ConsumerState<MilestoneScreen> {
  final Map<int, TextEditingController> _numbers = {};
  bool _busy = false;

  bool get _isMine => widget.traineeId == ref.read(myIdProvider);

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(Milestone m, MilestoneField field) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: Text(context.l10n.takePhoto), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: Text(context.l10n.chooseFromGallery), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (image == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(milestoneRepositoryProvider).savePhoto(widget.traineeId, m.id, field, await image.readAsBytes());
      ref.invalidate(milestonesProvider(widget.traineeId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(Milestone m) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(milestoneRepositoryProvider);
      for (final entry in _numbers.entries) {
        final value = parseNumber(entry.value.text);
        if (value != null) await repo.saveNumber(m.id, entry.key, value);
      }
      final fresh = (await repo.forTrainee(widget.traineeId)).firstWhere((x) => x.id == m.id);
      if (fresh.missingRequired) {
        if (mounted) showMessage(context, context.l10n.fillRequiredFields);
        ref.invalidate(milestonesProvider(widget.traineeId));
        return;
      }
      await repo.submit(m.id);
      ref.invalidate(milestonesProvider(widget.traineeId));
      if (mounted) {
        showMessage(context, context.l10n.checkInSent);
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
    final milestones = ref.watch(milestonesProvider(widget.traineeId));
    final m = milestones.value?.where((x) => x.id == widget.milestoneId).firstOrNull;
    if (m == null) {
      return Scaffold(appBar: AppBar(), body: milestones.isLoading ? const Center(child: CircularProgressIndicator()) : const SizedBox());
    }
    final editable = _isMine && m.submittedAt == null;
    final fields = m.requested.isNotEmpty
        ? m.requested
        : [for (final v in m.values.values) (MilestoneField(id: v.fieldId, key: '', labelEn: l10n.weight, labelAr: l10n.weight, isImage: v.imagePath != null), false)];
    return FormScaffold(
      title: m.name.isEmpty ? l10n.checkIn : m.name,
      primary: editable
          ? BusyButton(label: l10n.submit, busy: _busy, onPressed: () => _submit(m))
          : FilledButton(onPressed: null, child: Text(milestoneStatusLabel(context, m.status(today())))),
      children: [
        for (final (field, required) in fields) ...[
          Text('${field.label(context)}${required ? ' *' : ''}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (field.isImage)
            switch (m.values[field.id]?.imagePath) {
              final path? => Column(children: [
                  MilestonePhoto(path: path),
                  if (editable) TextButton(onPressed: _busy ? null : () => _pickPhoto(m, field), child: Text(l10n.retakePhoto)),
                ]),
              null when editable => OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(l10n.addPhoto),
                  onPressed: _busy ? null : () => _pickPhoto(m, field),
                ),
              null => ListTile(leading: const Icon(Icons.hide_image_outlined), title: Text(m.submittedAt == null ? l10n.notUploadedYet : l10n.photoNotVisible)),
            }
          else if (editable)
            TextField(
              controller: _numbers.putIfAbsent(
                  field.id, () => TextEditingController(text: formatNum(m.values[field.id]?.numberValue))),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(suffixText: field.key == 'weight' ? l10n.kg : null),
            )
          else
            Text(m.values[field.id]?.numberValue == null ? '—' : '${formatNum(m.values[field.id]!.numberValue)} ${field.key == 'weight' ? l10n.kg : ''}',
                style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

/// Coach: any two check-ins side by side, with the difference highlighted.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key, required this.traineeId});

  final String traineeId;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  Milestone? _a;
  Milestone? _b;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final milestones = ref.watch(milestonesProvider(widget.traineeId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.compare)),
      body: AsyncBody(
        value: milestones,
        onRetry: () => ref.invalidate(milestonesProvider(widget.traineeId)),
        builder: (all) {
          final list = all.where((m) => m.submittedAt != null).toList();
          final a = _a ?? (list.length > 1 ? list.last : null);
          final b = _b ?? list.firstOrNull;
          DropdownButton<Milestone> picker(Milestone? value, ValueChanged<Milestone?> onChanged) => DropdownButton<Milestone>(
                value: value,
                isExpanded: true,
                items: [for (final m in list) DropdownMenuItem(value: m, child: Text(format.format(m.dueDate)))],
                onChanged: onChanged,
              );
          final fieldIds = {...?a?.values.keys, ...?b?.values.keys}.toList()..sort();
          final names = {for (final m in list) for (final r in m.requested) r.$1.id: r.$1};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(child: picker(a, (m) => setState(() => _a = m))),
                const SizedBox(width: 16),
                Expanded(child: picker(b, (m) => setState(() => _b = m))),
              ]),
              const SizedBox(height: 16),
              for (final id in fieldIds) ...[
                Text(names[id]?.label(context) ?? l10n.weight, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in [a, b]) ...[
                      Expanded(
                        child: switch (m?.values[id]) {
                          MilestoneValue(imagePath: final path?) => MilestonePhoto(path: path, height: 260),
                          MilestoneValue(numberValue: final n?) => Text(formatNum(n), style: Theme.of(context).textTheme.headlineSmall),
                          _ => const Text('—'),
                        },
                      ),
                      if (m == a) const SizedBox(width: 12),
                    ],
                  ],
                ),
                if (a?.values[id]?.numberValue != null && b?.values[id]?.numberValue != null)
                  Builder(builder: (context) {
                    final diff = b!.values[id]!.numberValue! - a!.values[id]!.numberValue!;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Chip(
                        label: Text('${diff >= 0 ? '+' : ''}${formatNum(diff)}', textDirection: TextDirection.ltr),
                        backgroundColor: diff == 0
                            ? null
                            : (diff < 0 ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.errorContainer),
                      ),
                    );
                  }),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}
