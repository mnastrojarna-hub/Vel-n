import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
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
      appBar: AppBar(title: const Text('📩 Zprávy'), backgroundColor: MotoGoColors.dark),
      body: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _TabBtn(label: 'Oznámení', active: !_chatTab, onTap: () => setState(() => _chatTab = false)),
              const SizedBox(width: 4),
              _TabBtn(label: 'Konverzace', active: _chatTab, onTap: () => setState(() => _chatTab = true)),
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
        if (msgs.isEmpty) return _empty('📨', 'Žádná oznámení');
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            final date = '${m.createdAt.day}. ${m.createdAt.month}. ${m.createdAt.hour}:${m.createdAt.minute.toString().padLeft(2, '0')}';
            return Container(
              padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title ?? 'Zpráva z Moto Go', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                  if (m.message != null) Text(m.message!, style: const TextStyle(fontSize: 12, color: MotoGoColors.g600), maxLines: 3),
                  Text(date, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                ])),
              ]),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      error: (_, __) => const Center(child: Text('Chyba', style: TextStyle(color: MotoGoColors.red))),
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
                child: const Row(children: [
                  Text('✍️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nová konverzace', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    Text('Napsat MotoGo24', style: TextStyle(fontSize: 11, color: MotoGoColors.black)),
                  ])),
                  Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.black)),
                ]),
              ),
            ),
            if (threads.isEmpty) _empty('💬', 'Žádné konverzace'),
            ...threads.map((t) => _ThreadTile(thread: t, onTap: () => context.push('/messages/${t.id}'))),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      error: (_, __) => const Center(child: Text('Chyba')),
    );
  }

  void _newThread(BuildContext context) {
    final subjects = ['Dotaz k rezervaci', 'Problém s motorkou', 'Platba a fakturace', 'Příslušenství a výbava', 'Storno / změna termínu', 'Pochvala / poděkování', 'Jiný dotaz'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Nová konverzace', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...subjects.map((s) => GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              final id = await createThread(s);
              if (id != null && context.mounted) context.push('/messages/$id');
            },
            child: Container(
              padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
              child: Row(children: [
                Expanded(child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
                const Text('›', style: TextStyle(color: MotoGoColors.g400)),
              ]),
            ),
          )),
        ]),
      )),
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
      child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: active ? Colors.white : MotoGoColors.black))),
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
              Expanded(child: Text(thread.subject ?? 'Konverzace', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black), overflow: TextOverflow.ellipsis)),
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
