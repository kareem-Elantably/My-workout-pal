import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/models.dart';
import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/admin_repository.dart';
import '../auth/validators.dart';
import '../home/profile_screen.dart';
import '../shared/notifications_button.dart';
import 'application_screen.dart';

final peopleProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).people());
final _coachLoadProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).coachLoad());
final subscriptionsProvider =
    FutureProvider.autoDispose.family<List<SubscriptionRow>, String?>((ref, traineeId) => ref.watch(adminRepositoryProvider).subscriptions(traineeId: traineeId));

/// Everyone, searchable, filtered by role.
class PeopleTab extends ConsumerStatefulWidget {
  const PeopleTab({super.key});

  @override
  ConsumerState<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<PeopleTab> {
  AppRole? _role = AppRole.trainee;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final people = ref.watch(peopleProvider);
    final load = ref.watch(_coachLoadProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: Text(l10n.people), actions: const [NotificationsButton()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.searchPeople),
            onChanged: (q) => setState(() => _query = q.trim().toLowerCase()),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            for (final role in [...AppRole.values, null])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(role == null ? l10n.all : roleLabel(context, role)),
                  selected: _role == role,
                  onSelected: (_) => setState(() => _role = role),
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            value: people,
            onRetry: () => ref.invalidate(peopleProvider),
            builder: (list) {
              final shown = list
                  .where((p) => _role == null || p.roles.contains(_role))
                  .where((p) => _query.isEmpty || p.profile.fullName.toLowerCase().contains(_query) || (p.profile.phone ?? '').contains(_query))
                  .toList();
              return RefreshIndicator(
                onRefresh: () => ref.refresh(peopleProvider.future),
                child: shown.isEmpty
                    ? EmptyList(icon: Icons.person_search, title: l10n.noResults)
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final p = shown[i];
                          return ListTile(
                            leading: CircleAvatar(child: Text(p.profile.fullName.characters.firstOrNull ?? '?')),
                            title: Text(p.profile.fullName),
                            subtitle: Text([
                              if (p.roles.isEmpty) l10n.notApprovedYet else p.roles.map((r) => roleLabel(context, r)).join(', '),
                              if (p.roles.contains(AppRole.coach)) l10n.activeTrainees(load[p.profile.id] ?? 0),
                            ].join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/admin/people/${p.profile.id}'),
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// One person, for the admin: coaches (for trainees), subscriptions, and
/// a custom notification.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final person = ref.watch(peopleProvider).value?.where((p) => p.profile.id == userId).firstOrNull;
    if (person == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final p = person.profile;
    final isTrainee = person.roles.contains(AppRole.trainee);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.fullName),
        actions: [
          IconButton(
            tooltip: l10n.sendNotification,
            icon: const Icon(Icons.campaign_outlined),
            onPressed: () async {
              final title = await promptText(context, title: l10n.sendNotification, label: l10n.notificationTitle);
              if (title == null || title.trim().isEmpty) return;
              try {
                await ref.read(socialRepositoryProvider).sendCustom(userId, title, null);
                if (context.mounted) showMessage(context, l10n.notificationSent);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
        ],
      ),
      floatingActionButton: isTrainee
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_card),
              label: Text(l10n.recordPayment),
              onPressed: () => context.push('/admin/subscriptions/new?trainee=$userId'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          ListTile(
            title: Text([p.gender == 'female' ? l10n.female : l10n.male, ?p.phone].join(' · ')),
            subtitle: Text(person.roles.map((r) => roleLabel(context, r)).join(', ')),
          ),
          if (isTrainee) ...[
            AssignmentsCard(traineeId: userId, canEnd: true),
            SectionTitle(l10n.subscriptions),
            _SubscriptionList(traineeId: userId),
          ],
        ],
      ),
    );
  }
}

class _SubscriptionList extends ConsumerWidget {
  const _SubscriptionList({this.traineeId, this.filter});

  final String? traineeId;
  final String? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final subs = ref.watch(subscriptionsProvider(traineeId));
    return subs.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(subscriptionsProvider(traineeId))),
      data: (list) {
        final shown = filter == null ? list : list.where((s) => s.status == filter).toList();
        if (shown.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noSubscription));
        return Column(children: [
          for (final s in shown)
            Card(
              child: ListTile(
                title: Text(traineeId == null ? (s.traineeName ?? '—') : l10n.amountEgp('${s.amount}')),
                subtitle: Text([
                  if (traineeId == null) l10n.amountEgp('${s.amount}'),
                  '${format.format(s.startsOn)} → ${format.format(s.endsOn)}',
                  l10n.coachName(s.coachName ?? '—'),
                ].join('\n')),
                isThreeLine: true,
                trailing: _StatusChip(row: s),
                onTap: () => context.push('/admin/subscriptions/${s.id}'),
              ),
            ),
        ]);
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.row});

  final SubscriptionRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (row.status) {
      'ending_soon' => (l10n.daysLeft(row.daysLeft), scheme.errorContainer),
      'ended' => (l10n.subscriptionEnded, scheme.surfaceContainerHighest),
      'upcoming' => (l10n.upcoming, scheme.secondaryContainer),
      _ => (l10n.daysLeft(row.daysLeft), scheme.tertiaryContainer),
    };
    return Chip(label: Text(text), backgroundColor: color, visualDensity: VisualDensity.compact);
  }
}

/// All subscriptions, ending soon first.
class SubscriptionsTab extends StatefulWidget {
  const SubscriptionsTab({super.key});

  @override
  State<SubscriptionsTab> createState() => _SubscriptionsTabState();
}

class _SubscriptionsTabState extends State<SubscriptionsTab> {
  String? _filter = 'ending_soon';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filters = {'ending_soon': l10n.endingSoon, 'active': l10n.active, 'upcoming': l10n.upcoming, 'ended': l10n.subscriptionEnded, null: l10n.all};
    return Scaffold(
      appBar: AppBar(title: Text(l10n.subscriptions), actions: const [NotificationsButton()]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_card),
        label: Text(l10n.recordPayment),
        onPressed: () => context.push('/admin/subscriptions/new'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Wrap(spacing: 8, children: [
            for (final f in filters.entries)
              ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
          ]),
          const SizedBox(height: 8),
          _SubscriptionList(filter: _filter),
        ],
      ),
    );
  }
}

/// Record a payment (or edit one): trainee, coach credited, amount, dates.
class SubscriptionEditorScreen extends ConsumerStatefulWidget {
  const SubscriptionEditorScreen({super.key, this.subscriptionId, this.traineeId});

  final String? subscriptionId;
  final String? traineeId;

  @override
  ConsumerState<SubscriptionEditorScreen> createState() => _SubscriptionEditorScreenState();
}

class _SubscriptionEditorScreenState extends ConsumerState<SubscriptionEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _traineeId;
  String? _coachId;
  DateTime _start = today();
  int _months = 3;
  DateTime? _customEnd;
  bool _busy = false;
  bool _loaded = false;

  DateTime get _end => _customEnd ?? DateTime(_start.year, _start.month + _months, _start.day).subtract(const Duration(days: 1));

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _fill(List<SubscriptionRow> all) {
    if (_loaded) return;
    _loaded = true;
    _traineeId = widget.traineeId;
    final existing = all.where((s) => s.id == widget.subscriptionId).firstOrNull;
    if (existing != null) {
      _traineeId = existing.traineeId;
      _coachId = existing.coachId;
      _amount.text = formatNum(existing.amount);
      _note.text = existing.note ?? '';
      _start = existing.startsOn;
      _customEnd = existing.endsOn;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _traineeId == null || _coachId == null) {
      showMessage(context, context.l10n.fillRequiredFields);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).saveSubscription(
            id: widget.subscriptionId,
            traineeId: _traineeId!,
            coachId: _coachId!,
            amount: parseNumber(_amount.text)!,
            startsOn: _start,
            endsOn: _end,
            note: _note.text,
          );
      ref.invalidate(subscriptionsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final people = ref.watch(peopleProvider).value ?? const [];
    final all = ref.watch(subscriptionsProvider(null)).value;
    if (all != null) _fill(all);
    final trainees = people.where((p) => p.roles.contains(AppRole.trainee)).toList();
    final coaches = people.where((p) => p.roles.contains(AppRole.coach)).toList();
    return FormScaffold(
      title: widget.subscriptionId == null ? l10n.recordPayment : l10n.editSubscription,
      formKey: _form,
      primary: BusyButton(label: l10n.save, busy: _busy, onPressed: _save),
      secondary: widget.subscriptionId == null
          ? null
          : TextButton(
              onPressed: () async {
                if (!await confirm(context, l10n.deleteSubscriptionConfirm, action: l10n.delete)) return;
                await ref.read(adminRepositoryProvider).deleteSubscription(widget.subscriptionId!);
                ref.invalidate(subscriptionsProvider);
                if (context.mounted) context.pop();
              },
              child: Text(l10n.delete),
            ),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _traineeId,
          decoration: InputDecoration(labelText: l10n.roleTrainee),
          items: [for (final t in trainees) DropdownMenuItem(value: t.profile.id, child: Text(t.profile.fullName))],
          onChanged: (id) => setState(() => _traineeId = id),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _coachId,
          decoration: InputDecoration(labelText: l10n.coachCredited, helperText: l10n.coachCreditedHint),
          items: [for (final c in coaches) DropdownMenuItem(value: c.profile.id, child: Text(c.profile.fullName))],
          onChanged: (id) => setState(() => _coachId = id),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amount,
          decoration: InputDecoration(labelText: l10n.amountLabel, suffixText: 'EGP'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) => validateNumber(context, v, required: true, min: 0, max: 10000000),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.startsOn),
          trailing: Text(format.format(_start)),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2024), lastDate: DateTime(2100));
            if (picked != null) setState(() => _start = picked);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.months),
          trailing: NumberStepper(value: _months, min: 1, max: 24, onChanged: (v) => setState(() {
                _months = v.toInt();
                _customEnd = null;
              })),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.endsOn),
          trailing: Text(format.format(_end)),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: _end, firstDate: _start, lastDate: DateTime(2100));
            if (picked != null) setState(() => _customEnd = picked);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(controller: _note, decoration: InputDecoration(labelText: l10n.noteOptional)),
      ],
    );
  }
}
