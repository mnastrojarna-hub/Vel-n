import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_guard.dart';
import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import 'messages_provider.dart';

/// Thread chat detail — mirrors s-messages-thread from templates-done-pages.js
/// + renderThreadChat() from messages-ui.js.
/// Realtime messages with reply bar.
class ThreadDetailScreen extends ConsumerStatefulWidget {
  final String threadId;
  const ThreadDetailScreen({super.key, required this.threadId});

  @override
  ConsumerState<ThreadDetailScreen> createState() => _ThreadDetailState();
}

class _ThreadDetailState extends ConsumerState<ThreadDetailScreen> {
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Mark as read on open
    markThreadRead(widget.threadId);
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _replyCtrl.clear();

    final err = await sendMessage(widget.threadId, text);

    if (mounted) {
      setState(() => _sending = false);
      if (err != null) {
        // Restore text on failure so user doesn't lose their message
        _replyCtrl.text = text;
        showMotoGoToast(context, icon: '⚠️', title: t(context).tr('error'), message: t(context).tr('messageSendFailed'));
      } else {
        // Scroll to bottom after successful send
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: StreamBuilder triggers rebuild on every messages change,
    // then re-fetch thread with all messages to get updated list.
    return StreamBuilder(
      stream: MotoGoSupabase.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('thread_id', widget.threadId)
          .handleError((e) { handleAuthError(e); }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          handleAuthError(snapshot.error!);
        }
        // Use stream snapshot to force FutureBuilder key change → re-fetch
        final streamKey = snapshot.data?.length ?? 0;
        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey('thread_$streamKey'),
          future: MotoGoSupabase.client
              .from('message_threads')
              .select('*, messages(*)')
              .eq('id', widget.threadId)
              .maybeSingle(),
          builder: (context, threadSnap) {
            final thread = threadSnap.data != null
                ? MessageThread.fromJson(threadSnap.data!)
                : null;
            // Mark new messages as read on each refresh
            if (thread != null && thread.messages.any((m) => m.direction == 'admin' && m.readAt == null)) {
              markThreadRead(widget.threadId);
            }

            return Scaffold(
              backgroundColor: MotoGoColors.bg,
              appBar: AppBar(
                leading: GestureDetector(
                  onTap: () => context.pop(),
                  child: Center(
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
                    ),
                  ),
                ),
                title: Text(thread?.subject ?? 'Konverzace',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                backgroundColor: MotoGoColors.dark,
                bottom: thread != null ? PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      thread.isClosed ? 'Uzavřeno' : 'Aktivní',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
                ) : null,
              ),
              body: Column(
                children: [
                  // Messages list
                  Expanded(
                    child: thread == null || thread.messages.isEmpty
                        ? const Center(child: Text('Napište první zprávu', style: TextStyle(fontSize: 13, color: MotoGoColors.g400)))
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: thread.messages.length,
                            itemBuilder: (_, i) => _MessageBubble(message: thread.messages[i]),
                          ),
                  ),

                  // Reply bar (hidden if closed)
                  if (thread == null || !thread.isClosed)
                    Container(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: MotoGoColors.green.withValues(alpha: 0.3), width: 2)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _replyCtrl,
                            decoration: InputDecoration(
                              hintText: 'Napište zprávu...',
                              hintStyle: const TextStyle(fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: MotoGoColors.g200)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: MotoGoColors.g200)),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _send,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(50)),
                            child: Text(_sending ? '⏳' : 'Odeslat',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isCustomer;
    final time = '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    final date = '${message.createdAt.day}. ${message.createdAt.month}.';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isMe ? MotoGoColors.green : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 3)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.content ?? '', style: const TextStyle(fontSize: 13, color: MotoGoColors.black, height: 1.5)),
            const SizedBox(height: 4),
            Text('$date $time', style: TextStyle(fontSize: 10, color: MotoGoColors.black.withValues(alpha: 0.4)), textAlign: TextAlign.right),
          ],
        ),
      ),
    );
  }
}
