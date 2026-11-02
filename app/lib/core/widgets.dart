import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'plan_models.dart';
import 'ui.dart';

/// Loading / error / data for a provider, with pull-to-refresh on data.
class AsyncBody<T> extends ConsumerWidget {
  const AsyncBody({super.key, required this.value, required this.onRetry, required this.builder});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(error: error, onRetry: onRetry),
        data: builder,
      );
}

/// +/- stepper for gym logging: tap to step, hold to keep stepping.
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.max = 9999,
    this.suffix,
    this.decimals = 0,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final num step;
  final num min;
  final num max;
  final String? suffix;
  final int decimals;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  Timer? _repeat;

  void _change(num delta) {
    final next = (widget.value + delta).clamp(widget.min, widget.max);
    widget.onChanged(widget.decimals == 0 ? next.round() : num.parse(next.toStringAsFixed(widget.decimals)));
  }

  void _startRepeat(num delta) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) => _change(delta));
  }

  void _stopRepeat() => _repeat?.cancel();

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  Widget _button(IconData icon, num delta) => GestureDetector(
        onLongPressStart: (_) => _startRepeat(delta),
        onLongPressEnd: (_) => _stopRepeat(),
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18),
          onPressed: () => _change(delta),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove, -widget.step),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Text(
              '${formatNum(widget.value, decimals: widget.decimals == 0 ? 1 : widget.decimals)}${widget.suffix ?? ''}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
              textDirection: TextDirection.ltr,
            ),
          ),
          _button(Icons.add, widget.step),
        ],
      );
}

/// "Today", "Yesterday" or a date, with arrows to move within [first]..[last].
class DateBar extends StatelessWidget {
  const DateBar({super.key, required this.day, required this.first, required this.last, required this.onChanged});

  final DateTime day;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final diff = last.difference(day).inDays;
    final label = diff == 0
        ? l10n.today
        : diff == 1
            ? l10n.yesterday
            : DateFormat.MMMEd(Localizations.localeOf(context).toString()).format(day);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l10n.previousDay,
          icon: const Icon(Icons.chevron_left),
          onPressed: day.isAfter(first) ? () => onChanged(day.subtract(const Duration(days: 1))) : null,
        ),
        SizedBox(width: 140, child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          tooltip: l10n.nextDay,
          icon: const Icon(Icons.chevron_right),
          onPressed: day.isBefore(last) ? () => onChanged(day.add(const Duration(days: 1))) : null,
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
            ?trailing,
          ],
        ),
      );
}

/// Macros in one line: "520 kcal · P 42 · C 50 · F 14".
class MacrosLine extends StatelessWidget {
  const MacrosLine(this.macros, {super.key, this.style});

  final Macros macros;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Text(
      '${formatNum(macros.kcal.round())} ${l10n.kcal} · ${l10n.proteinShort} ${formatNum(macros.protein.round())} · '
      '${l10n.carbsShort} ${formatNum(macros.carbs.round())} · ${l10n.fatShort} ${formatNum(macros.fat.round())}',
      style: style ?? Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// Asks for a line of text (rename, add a day, ...). Null when cancelled.
Future<String?> promptText(BuildContext context, {required String title, String? initial, String? label, bool multiline = false}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
        onSubmitted: multiline ? null : (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(context.l10n.save)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message, {String? action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action ?? context.l10n.yes)),
        ],
      ),
    ) ??
    false;

/// Empty state inside a scrollable (keeps pull-to-refresh working).
class EmptyList extends StatelessWidget {
  const EmptyList({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListView(children: [
        MessageView(icon: icon, title: title, body: body, actions: [?action]),
      ]);
}
