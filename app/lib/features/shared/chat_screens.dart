import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/social_repository.dart';
import 'notifications_button.dart';

final conversationsProvider =
    FutureProvider.autoDispose<List<Conversation>>((ref) => ref.watch(socialRepositoryProvider).conversations());

final _messagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>(
  (ref, conversationId) => ref.watch(socialRepositoryProvider).messages(conversationId),
);

/// Conversations with coaches (trainee) or trainees (coach). With a single
/// conversation the list is skipped. Text only: no attachments.
class ChatListTab extends ConsumerWidget {
  const ChatListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final conversations = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chat)),
      body: AsyncBody(
        value: conversations,
        onRetry: () => ref.invalidate(conversationsProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(conversationsProvider.future),
          child: list.isEmpty
              ? EmptyList(icon: Icons.chat_bubble_outline, title: l10n.noConversations)
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(c.otherName.characters.firstOrNull ?? '?')),
                      title: Text(c.otherName),
                      trailing: c.unread > 0 ? Badge(label: Text('${c.unread}')) : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('${rolePath(context)}/chat/${c.id}?name=${Uri.encodeComponent(c.otherName)}');
                        ref.invalidate(conversationsProvider);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, this.title});

  final String conversationId;
  final String? title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(socialRepositoryProvider).send(widget.conversationId, body);
      _text.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = ref.watch(myIdProvider);
    final messages = ref.watch(_messagesProvider(widget.conversationId));
    // Everything shown is read.
    ref.listen(_messagesProvider(widget.conversationId), (_, next) {
      if (next.value?.any((m) => m.senderId != me && m.readAt == null) ?? false) {
        ref.read(socialRepositoryProvider).markRead(widget.conversationId).catchError((_) {});
      }
    });
    final time = DateFormat.jm(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? l10n.chat)),
      body: Column(
        children: [
          Expanded(
            child: AsyncBody(
              value: messages,
              onRetry: () => ref.invalidate(_messagesProvider(widget.conversationId)),
              builder: (list) {
                if (list.isEmpty) return MessageView(icon: Icons.waving_hand_outlined, title: l10n.sayHello);
                final rows = chatRows(list);
                return ListView.builder(
                      // Newest at the bottom, next to the text field, and it
                      // stays there as new messages arrive.
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[rows.length - 1 - i];
                        if (row is DateTime) return _DayChip(day: row);
                        final m = row as ChatMessage;
                        final mine = m.senderId == me;
                        final scheme = Theme.of(context).colorScheme;
                        return Align(
                          alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                            decoration: BoxDecoration(
                              color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(m.body, style: Theme.of(context).textTheme.bodyLarge),
                                Text(
                                  '${time.format(m.createdAt.toLocal())}${mine && m.readAt != null ? ' ✓✓' : ''}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: l10n.typeMessage, isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: l10n.send,
                    icon: _sending
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Messages oldest first, with the day (a [DateTime]) before each day's
/// first message.
List<Object> chatRows(List<ChatMessage> messages) {
  final rows = <Object>[];
  DateTime? day;
  for (final m in messages) {
    final local = m.createdAt.toLocal();
    final d = DateTime(local.year, local.month, local.day);
    if (d != day) rows.add(day = d);
    rows.add(m);
  }
  return rows;
}

/// "Today", "Yesterday", the weekday this week, else the date.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final daysAgo = DateTime(now.year, now.month, now.day).difference(day).inDays;
    final label = switch (daysAgo) {
      0 => l10n.today,
      1 => l10n.yesterday,
      < 7 => DateFormat.EEEE(locale).format(day),
      _ when day.year == now.year => DateFormat.MMMMd(locale).format(day),
      _ => DateFormat.yMMMMd(locale).format(day),
    };
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
