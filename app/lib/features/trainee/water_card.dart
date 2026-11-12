import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../auth/validators.dart';

const glassMl = 250;

final waterProvider = FutureProvider.autoDispose.family<int, DateTime>(
  (ref, day) => ref.watch(nutritionRepositoryProvider).waterOn(ref.watch(myIdProvider), day),
);

String litres(int ml) => formatNum(ml / 1000, decimals: 2);

/// Today's water: one tap per glass, against the daily goal. Tap the
/// amount to type an exact figure, the goal to change it.
class WaterCard extends ConsumerStatefulWidget {
  const WaterCard({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends ConsumerState<WaterCard> {
  /// What's on screen after taps, ahead of the database.
  int? _ml;
  Future<void> _saving = Future.value();

  @override
  void didUpdateWidget(WaterCard old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _ml = null;
  }

  void _set(int ml) {
    final value = ml.clamp(0, 20000);
    setState(() => _ml = value);
    final me = ref.read(myIdProvider);
    final repo = ref.read(nutritionRepositoryProvider);
    // One save at a time, in tap order, so quick taps all count.
    _saving = _saving.then((_) => repo.setWater(me, widget.day, value)).catchError((Object e) {
      if (mounted) {
        showError(context, e);
        setState(() => _ml = null);
        ref.invalidate(waterProvider(widget.day));
      }
    });
  }

  /// Adds to what's on screen now, so taps between frames all count.
  void _change(int delta) => _set((_ml ?? ref.read(waterProvider(widget.day)).value ?? 0) + delta);

  Future<void> _typeAmount(int current) async {
    final l10n = context.l10n;
    final text = await promptText(context,
        title: l10n.waterAmountPrompt, initial: litres(current), keyboardType: const TextInputType.numberWithOptions(decimal: true));
    if (text == null || !mounted) return;
    final value = parseNumber(text);
    if (value == null || value < 0 || value > 20) {
      showMessage(context, l10n.invalidWater);
      return;
    }
    _set((value * 1000).round());
  }

  Future<void> _changeGoal(int goal) async {
    final l10n = context.l10n;
    final text = await promptText(context,
        title: l10n.waterGoalPrompt, initial: litres(goal), keyboardType: const TextInputType.numberWithOptions(decimal: true));
    if (text == null || !mounted) return;
    final value = parseNumber(text);
    if (value == null || value < 0.5 || value > 10) {
      showMessage(context, l10n.invalidWaterGoal);
      return;
    }
    try {
      await ref.read(sessionRepositoryProvider).updateProfile(ref.read(myIdProvider), {'water_goal_ml': (value * 1000).round()});
      await ref.read(sessionProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final goal = session is SignedIn ? session.data.profile?.waterGoalMl ?? 2500 : 2500;
    final saved = ref.watch(waterProvider(widget.day));
    final ml = _ml ?? saved.value;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.water_drop, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.water, style: theme.textTheme.titleMedium)),
              TextButton(onPressed: () => _changeGoal(goal), child: Text(l10n.waterGoal(litres(goal)))),
            ]),
            if (ml == null)
              const LinearProgressIndicator()
            else ...[
              InkWell(
                onTap: () => _typeAmount(ml),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    ml >= goal ? '${l10n.waterLitres(litres(ml))} · ${l10n.waterGoalReached}' : l10n.waterLitres(litres(ml)),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (ml / goal).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 12),
              Row(children: [
                IconButton.outlined(
                  tooltip: l10n.removeGlass,
                  onPressed: ml == 0 ? null : () => _change(-glassMl),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _change(glassMl),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addGlass),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
