import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/admin_repository.dart';

final _earningsProvider = FutureProvider.autoDispose.family<List<EarningsLine>, (DateTime, DateTime, bool, String?)>(
  (ref, args) => ref.watch(adminRepositoryProvider).earnings(args.$1, args.$2, byTrainee: args.$3, coachId: args.$4),
);

/// Earnings in a date range (this month by default). Coaches see their own,
/// by trainee; admins see every coach. Amounts follow the monthly split.
class EarningsView extends ConsumerStatefulWidget {
  const EarningsView({super.key, required this.byTrainee, this.coachId});

  final bool byTrainee;
  final String? coachId;

  @override
  ConsumerState<EarningsView> createState() => _EarningsViewState();
}

class _EarningsViewState extends ConsumerState<EarningsView> {
  late DateTimeRange _range = _month(DateTime.now());

  static DateTimeRange _month(DateTime d) =>
      DateTimeRange(start: DateTime(d.year, d.month), end: DateTime(d.year, d.month + 1, 0));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final money = NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 2);
    final isMonth = _range.start.day == 1 && _range.end == _month(_range.start).end;
    final label = isMonth
        ? DateFormat.yMMMM(locale).format(_range.start)
        : '${DateFormat.yMMMd(locale).format(_range.start)} – ${DateFormat.yMMMd(locale).format(_range.end)}';
    final lines = ref.watch(_earningsProvider((_range.start, _range.end, widget.byTrainee, widget.coachId)));
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: l10n.previousMonth,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _range = _month(DateTime(_range.start.year, _range.start.month - 1))),
        ),
        TextButton(
          onPressed: () async {
            final picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2100), initialDateRange: _range);
            if (picked != null) setState(() => _range = picked);
          },
          child: Text(label),
        ),
        IconButton(
          tooltip: l10n.nextMonth,
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _range = _month(DateTime(_range.start.year, _range.start.month + 1))),
        ),
      ]),
      Expanded(
        child: AsyncBody(
          value: lines,
          onRetry: () => ref.invalidate(_earningsProvider((_range.start, _range.end, widget.byTrainee, widget.coachId))),
          builder: (list) {
            final total = list.fold<num>(0, (sum, l) => sum + l.amount);
            return ListView(children: [
              Card(
                margin: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  title: Text(l10n.totalEarnings),
                  trailing: Text(l10n.amountEgp(money.format(total)), style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noEarnings)),
              for (final line in list)
                ListTile(title: Text(line.name), trailing: Text(l10n.amountEgp(money.format(line.amount)))),
            ]);
          },
        ),
      ),
    ]);
  }
}
