import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'messages_provider.dart';

/// Messages screen — mirrors s-messages from templates-done-pages.js.
/// Two tabs: Oznámení (admin_messages) + Konverzace (threads).
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends ConsumerState<MessagesScreen> {
  bool _chatTab = false;

  @override
  Widget build(BuildContext context) {
    final adminAsync = ref.watch(adminMessagesProvider);
    final threadsAsync = ref.watch(threadsProvider);

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
        title: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo.png', width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 24, height: 24, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 14, color: Colors.black)))),
          const SizedBox(width: 8),
          Text(t(context).tr('messagesTitle')),
        ]),
        backgroundColor: MotoGoColors.dark,
      ),
      body: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _TabBtn(label: t(context).tr('notificationsTab'), active: !_chatTab, onTap: () => setState(() => _chatTab = false)),
              const SizedBox(width: 4),
              _TabBtn(label: t(context).tr('conversationsTab'), active: _chatTab, onTap: () => setState(() => _chatTab = true)),
            ]),
          ),
          const SizedBox(height: 8),
          // Content
          Expanded(
            child: _chatTab
                ? _buildThreads(context, threadsAsync)
                : _buildNotifications(adminAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications(AsyncValue<List<AdminMessage>> async) {
    return async.when(
      data: (msgs) {
        if (msgs.isEmpty) return _empty('📨', t(context).tr('noNotifications'));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            final date = '${m.createdAt.day}. ${m.createdAt.month}. ${m.createdAt.hour}:${m.createdAt.minute.toString().padLeft(2, '0')}';
            return Container(
              padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                border: m.read ? null : Border.all(color: MotoGoColors.green.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title ?? t(context).tr('messageFromMotoGo'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                  if (m.message != null) Text(m.message!, style: const TextStyle(fontSize: 12, color: MotoGoColors.g600), maxLines: 3),
                  Text(date, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                ])),
              ]),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      error: (_, __) => Center(child: Text(t(context).error, style: const TextStyle(color: MotoGoColors.red))),
    );
  }

  Widget _buildThreads(BuildContext context, AsyncValue<List<MessageThread>> async) {
    return async.when(
      data: (threads) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            // New conversation button
            GestureDetector(
              onTap: () => _newThread(context),
              child: Container(
                padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
                child: Row(children: [
                  const Text('✍️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(context).tr('newConversation'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    Text(t(context).tr('writeMotoGo'), style: const TextStyle(fontSize: 11, color: MotoGoColors.black)),
                  ])),
                  const Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.black)),
                ]),
              ),
            ),
            if (threads.isEmpty) _empty('💬', t(context).tr('noConversations')),
            ...threads.map((t) => _ThreadTile(thread: t, onTap: () => context.push('/messages/${t.id}'))),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      error: (_, __) => Center(child: Text(t(context).error)),
    );
  }

  void _newThread(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t(context).tr('newConversation'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: t(context).tr('conversationTopic'),
                hintStyle: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                filled: true,
                fillColor: MotoGoColors.g100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: const TextStyle(fontSize: 14, color: MotoGoColors.black),
              onSubmitted: (value) async {
                final subject = value.trim();
                if (subject.isEmpty) {
                  showMotoGoToast(context, icon: '⚠️', title: t(context).tr('newConversation'), message: t(context).tr('enterSubject'));
                  return;
                }
                Navigator.pop(ctx);
                final id = await createThread(subject);
                if (id != null && context.mounted) context.push('/messages/$id');
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () async {
                  final subject = controller.text.trim();
                  if (subject.isEmpty) {
                    showMotoGoToast(context, icon: '⚠️', title: t(context).tr('newConversation'), message: t(context).tr('enterSubject'));
                    return;
                  }
                  Navigator.pop(ctx);
                  final id = await createThread(subject);
                  if (id != null && context.mounted) context.push('/messages/$id');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(50)),
                  child: Center(child: Text(t(context).tr('send'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
                ),
              ),
            ),
          ]),
        )),
      ),
    );
  }

  Widget _empty(String icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 36)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
    ]),
  );
}

class _TabBtn extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? MotoGoColors.green : Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: 2),
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: active ? Colors.black : MotoGoColors.black))),
    ),
  ));
}

class _ThreadTile extends StatelessWidget {
  final MessageThread thread; final VoidCallback onTap;
  const _ThreadTile({required this.thread, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isSos = thread.subject?.startsWith('SOS:') ?? false;
    final preview = thread.lastMessage?.content ?? '';
    final date = thread.lastMessageAt ?? thread.createdAt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 8)],
          border: thread.unreadCount > 0 ? const Border(left: BorderSide(color: MotoGoColors.green, width: 4)) : null,
        ),
        child: Row(children: [
          Text(isSos ? '🚑' : '💬', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(thread.subject ?? t(context).tr('conversation'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black), overflow: TextOverflow.ellipsis)),
              if (thread.unreadCount > 0) Container(
                width: 20, height: 20, decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
                child: Center(child: Text('${thread.unreadCount}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
              ),
            ]),
            Text(preview.length > 60 ? '${preview.substring(0, 60)}...' : preview, style: const TextStyle(fontSize: 12, color: MotoGoColors.g400), maxLines: 1),
            Text('${date.day}. ${date.month}. ${date.hour}:${date.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
          ])),
        ]),
      ),
    );
  }
}
