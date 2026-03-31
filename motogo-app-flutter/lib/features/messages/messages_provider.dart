import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';

/// Message thread from message_threads table.
class MessageThread {
  final String id;
  final String? subject;
  final String channel;
  final String status; // open, closed
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final List<Message> messages;

  MessageThread({
    required this.id, this.subject, required this.channel,
    required this.status, this.lastMessageAt, required this.createdAt,
    this.messages = const [],
  });

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List?)
        ?.map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return MessageThread(
      id: json['id'] as String,
      subject: json['subject'] as String?,
      channel: json['channel'] as String? ?? 'app',
      status: json['status'] as String? ?? 'open',
      lastMessageAt: json['last_message_at'] != null ? DateTime.parse(json['last_message_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      messages: msgs,
    );
  }

  bool get isClosed => status == 'closed';
  int get unreadCount => messages.where((m) => m.direction == 'admin' && m.readAt == null).length;
  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;
}

/// Single message from messages table.
class Message {
  final String id;
  final String? content;
  final String direction; // customer, admin
  final DateTime? readAt;
  final DateTime createdAt;

  Message({required this.id, this.content, required this.direction, this.readAt, required this.createdAt});

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    content: json['content'] as String?,
    direction: json['direction'] as String? ?? 'admin',
    readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  bool get isCustomer => direction == 'customer';
}

/// Admin notification message from admin_messages table.
class AdminMessage {
  final String id;
  final String? title;
  final String? message;
  final String? type; // sos_response, info, voucher, replacement, tow, thanks
  final bool read;
  final DateTime createdAt;

  AdminMessage({required this.id, this.title, this.message, this.type, this.read = false, required this.createdAt});

  factory AdminMessage.fromJson(Map<String, dynamic> json) => AdminMessage(
    id: json['id'] as String,
    title: json['title'] as String?,
    message: json['message'] as String?,
    type: json['type'] as String?,
    read: json['read'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  String get icon => switch (type) {
    'sos_response' || 'sos_auto' => '🚑',
    'accident_response' => '⚠️',
    'replacement' => '🛠️',
    'tow' => '🚚',
    'info' => 'ℹ️',
    'thanks' => '🙏',
    'voucher' => '🎁',
    _ => '📩',
  };
}

/// Threads with realtime — mirrors apiFetchMyThreads + realtime subscription.
final threadsProvider = StreamProvider<List<MessageThread>>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) { yield []; return; }

  yield await _fetchThreads(user.id);

  await for (final _ in MotoGoSupabase.client
      .from('message_threads')
      .stream(primaryKey: ['id'])
      .eq('customer_id', user.id)) {
    yield await _fetchThreads(user.id);
  }
});

Future<List<MessageThread>> _fetchThreads(String userId) async {
  final res = await MotoGoSupabase.client
      .from('message_threads')
      .select('*, messages(*)')
      .eq('customer_id', userId)
      .order('last_message_at', ascending: false);
  return (res as List).map((e) => MessageThread.fromJson(e)).toList();
}

/// Admin messages (notifications) — mirrors apiFetchAdminMessages.
final adminMessagesProvider = StreamProvider<List<AdminMessage>>((ref) async* {
  final user = MotoGoSupabase.currentUser;
  if (user == null) { yield []; return; }

  yield await _fetchAdminMessages(user.id);

  await for (final _ in MotoGoSupabase.client
      .from('admin_messages')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)) {
    yield await _fetchAdminMessages(user.id);
  }
});

Future<List<AdminMessage>> _fetchAdminMessages(String userId) async {
  final res = await MotoGoSupabase.client
      .from('admin_messages')
      .select()
      .eq('user_id', userId)
      .order('created_at', ascending: false);
  return (res as List).map((e) => AdminMessage.fromJson(e)).toList();
}

/// Unread message count — mirrors get_unread_thread_message_count RPC.
final unreadCountProvider = FutureProvider<int>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return 0;
  try {
    final res = await MotoGoSupabase.client.rpc('get_unread_thread_message_count', params: {'p_customer_id': user.id});
    return (res as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
});

/// Send customer message — INSERT into messages with direction='customer'.
Future<void> sendMessage(String threadId, String content) async {
  await MotoGoSupabase.client.from('messages').insert({
    'thread_id': threadId,
    'content': content,
    'direction': 'customer',
  });
  // Update thread last_message_at
  await MotoGoSupabase.client.from('message_threads').update({
    'last_message_at': DateTime.now().toIso8601String(),
  }).eq('id', threadId);
}

/// Mark thread messages as read — mirrors mark_thread_messages_read RPC.
Future<void> markThreadRead(String threadId) async {
  try {
    await MotoGoSupabase.client.rpc('mark_thread_messages_read', params: {'p_thread_id': threadId});
  } catch (_) {}
}

/// Create new thread — mirrors _createNewThreadWithSubject.
Future<String?> createThread(String subject) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return null;
  final res = await MotoGoSupabase.client.from('message_threads').insert({
    'customer_id': user.id,
    'channel': 'app',
    'status': 'open',
    'subject': subject,
    'last_message_at': DateTime.now().toIso8601String(),
  }).select('id').single();
  return res['id'] as String;
}
