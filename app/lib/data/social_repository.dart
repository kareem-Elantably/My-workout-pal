import 'package:supabase_flutter/supabase_flutter.dart';

/// Chat, notifications, notes and reminders: everything between people or
/// on the user's own account.

class Conversation {
  const Conversation({required this.id, required this.otherId, required this.otherName, this.unread = 0});

  final String id;
  final String otherId;
  final String otherName;
  final int unread;
}

class ChatMessage {
  const ChatMessage({required this.id, required this.senderId, required this.body, required this.createdAt, this.readAt});

  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.title,
    this.body,
    this.readAt,
  });

  final String id;
  final String type;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type_key'] as String,
        title: json['title'] as String?,
        body: json['body'] as String?,
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      );
}

class Note {
  const Note({required this.id, required this.body, required this.updatedAt, this.aboutUserId});

  final String id;
  final String body;
  final String? aboutUserId;
  final DateTime updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        body: json['body'] as String,
        aboutUserId: json['about_user_id'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class Reminder {
  const Reminder({
    required this.kind,
    required this.time,
    required this.weekdays,
    required this.enabled,
    required this.isDefault,
    this.mealSlot,
    this.label,
  });

  final String kind;
  final int? mealSlot;
  final String? label;

  /// "HH:mm", or null when there's no time yet (then it's off).
  final String? time;
  final List<int> weekdays;
  final bool enabled;
  final bool isDefault;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        kind: json['kind'] as String,
        mealSlot: json['meal_slot'] as int?,
        label: json['label'] as String?,
        time: (json['at_time'] as String?)?.substring(0, 5),
        weekdays: (json['weekdays'] as List? ?? const [0, 1, 2, 3, 4, 5, 6]).cast<int>(),
        enabled: json['enabled'] as bool? ?? false,
        isDefault: json['is_default'] as bool? ?? true,
      );
}

class SocialRepository {
  SocialRepository(this._client);

  final SupabaseClient _client;

  String get _me => _client.auth.currentUser!.id;

  // --- chat ---------------------------------------------------------------

  Future<List<Conversation>> conversations() async {
    final rows = await _client.from('conversations').select(
        'id, coach:profiles!conversations_coach_id_fkey(id, full_name), trainee:profiles!conversations_trainee_id_fkey(id, full_name)');
    final unread = await _client.from('messages').select('conversation_id').isFilter('read_at', null).neq('sender_id', _me);
    final counts = <String, int>{};
    for (final row in unread) {
      counts.update(row['conversation_id'] as String, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final row in rows)
        () {
          final coach = row['coach'] as Map<String, dynamic>?;
          final trainee = row['trainee'] as Map<String, dynamic>?;
          final other = coach?['id'] == _me ? trainee : coach;
          return Conversation(
            id: row['id'] as String,
            otherId: other?['id'] as String? ?? '',
            otherName: other?['full_name'] as String? ?? '',
            unread: counts[row['id']] ?? 0,
          );
        }(),
    ];
  }

  Future<String?> conversationWith(String otherUserId) async {
    final row = await _client
        .from('conversations')
        .select('id')
        .or('and(coach_id.eq.$_me,trainee_id.eq.$otherUserId),and(coach_id.eq.$otherUserId,trainee_id.eq.$_me)')
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Live list of messages, oldest first (Supabase Realtime). The stream's
  /// `order` is newest-first by default, so the order is fixed here.
  Stream<List<ChatMessage>> messages(String conversationId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(ChatMessage.fromJson).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  Future<void> send(String conversationId, String body) =>
      _client.from('messages').insert({'conversation_id': conversationId, 'sender_id': _me, 'body': body.trim()});

  Future<void> markRead(String conversationId) => _client
      .from('messages')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('conversation_id', conversationId)
      .neq('sender_id', _me)
      .isFilter('read_at', null);

  // --- notifications ------------------------------------------------------

  /// The inbox; chat messages show in the chat instead.
  Future<List<AppNotification>> inbox() async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('recipient_id', _me)
        .neq('type_key', 'chat_message')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<void> markNotificationsRead() => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('recipient_id', _me)
      .isFilter('read_at', null);

  Future<int> unreadNotifications() async {
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('recipient_id', _me)
        .neq('type_key', 'chat_message')
        .isFilter('read_at', null);
    return rows.length;
  }

  /// A coach to their own trainee, or an admin to anyone (enforced by RLS).
  Future<void> sendCustom(String recipientId, String title, String? body) => _client.from('notifications').insert({
        'recipient_id': recipientId,
        'type_key': 'custom',
        'title': title.trim(),
        'body': body == null || body.trim().isEmpty ? null : body.trim(),
        'sent_by': _me,
      });

  Future<void> registerDeviceToken(String token, String platform) =>
      _client.rpc('register_device_token', params: {'p_token': token, 'p_platform': platform});

  // --- notes --------------------------------------------------------------

  Future<List<Note>> notes({String? aboutUserId}) async {
    var query = _client.from('notes').select().eq('author_id', _me);
    query = aboutUserId == null ? query.isFilter('about_user_id', null) : query.eq('about_user_id', aboutUserId);
    final rows = await query.order('updated_at', ascending: false);
    return rows.map(Note.fromJson).toList();
  }

  Future<void> saveNote({String? id, required String body, String? aboutUserId}) => id == null
      ? _client.from('notes').insert({'author_id': _me, 'about_user_id': aboutUserId, 'body': body.trim()})
      : _client.from('notes').update({'body': body.trim()}).eq('id', id);

  Future<void> deleteNote(String id) => _client.from('notes').delete().eq('id', id);

  // --- reminders ----------------------------------------------------------

  Future<List<Reminder>> reminders() async {
    final rows = await _client.rpc('my_reminders') as List;
    return rows.cast<Map<String, dynamic>>().map(Reminder.fromJson).toList();
  }

  Future<void> saveReminder({required String kind, int? mealSlot, required String time, required bool enabled}) async {
    var query = _client.from('reminder_settings').select('id').eq('user_id', _me).eq('kind', kind);
    query = mealSlot == null ? query.isFilter('meal_slot', null) : query.eq('meal_slot', mealSlot);
    final existing = await query.maybeSingle();
    final row = {'user_id': _me, 'kind': kind, 'meal_slot': mealSlot, 'at_time': time, 'enabled': enabled};
    existing == null
        ? await _client.from('reminder_settings').insert(row)
        : await _client.from('reminder_settings').update(row).eq('id', existing['id']);
  }

  // --- account ------------------------------------------------------------

  /// Deletes files and the account (Edge Function), then signs out locally.
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    await _client.auth.signOut();
  }

  Future<List<Map<String, dynamic>>> mySubscriptions() async =>
      await _client.from('subscription_status').select().eq('trainee_id', _me).order('ends_on', ascending: false);
}
