import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/state_views.dart';
import '../messages_provider.dart';
import 'messages_parts_v2.dart';

/// Zprávy in the v2 look (PLAN §2.5.2, seam view of `MessagesScreen`): dark
/// compact app bar with the 2-segment switch Oznámení [n] / Konverzace and
/// "Označit vše" (only while there is something unread), white notification
/// cards (expand, unread bar), the "NOVÁ KONVERZACE" dark card with the rank
/// CTA (existing create flow) and thread cards. Loading / error = the
/// existing state widgets. All state lives in the screen.
class MessagesViewV2 extends ConsumerWidget {
  final AsyncValue<List<AdminMessage>> adminAsync;
  final AsyncValue<List<MessageThread>> threadsAsync;
  final bool chatTab;
  final Set<String> expanded;
  final int unread;
  final VoidCallback onBack;
  final ValueChanged<bool> onTab;
  final ValueChanged<AdminMessage> onToggleNote;
  final VoidCallback onMarkAll;
  final VoidCallback onNewThread;
  final ValueChanged<MessageThread> onOpenThread;
  final VoidCallback onRetryAdmin;
  final VoidCallback onRetryThreads;

  const MessagesViewV2({
    super.key,
    required this.adminAsync,
    required this.threadsAsync,
    required this.chatTab,
    required this.expanded,
    required this.unread,
    required this.onBack,
    required this.onTab,
    required this.onToggleNote,
    required this.onMarkAll,
    required this.onNewThread,
    required this.onOpenThread,
    required this.onRetryAdmin,
    required this.onRetryThreads,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final header = MgAppBar(
      title: tr.tr('messagesTitle'),
      onBack: onBack,
      actions: [
        if (!chatTab && unread > 0)
          MgIconButton(icon: MgIcons.checks, semanticLabel: tr.tr('markAllRead'), onTap: onMarkAll),
      ],
      bottom: MsgSegmentsV2(
        left: tr.tr('notificationsTab'),
        right: tr.tr('conversationsTab'),
        rightOn: chatTab,
        badge: unread,
        rank: rank,
        onChanged: onTab,
      ),
    );
    return MgPage(
      header: header,
      overlapHero: false,
      slivers: chatTab ? _threads(context) : _notes(context),
    );
  }

  List<Widget> _notes(BuildContext context) {
    final tr = t(context);
    return adminAsync.when(
      data: (msgs) {
        if (msgs.isEmpty) {
          return [SliverToBoxAdapter(child: MsgEmptyV2(icon: MgIcons.mail, text: tr.tr('noNotifications')))];
        }
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.separated(
              itemCount: msgs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => MgReveal(
                index: i,
                child: MsgNoteCardV2(
                  m: msgs[i],
                  expanded: expanded.contains(msgs[i].id),
                  onTap: () => onToggleNote(msgs[i]),
                ),
              ),
            ),
          ),
        ];
      },
      loading: () => [SliverFillRemaining(child: MgLoadingView(onRetry: onRetryAdmin))],
      error: (e, _) => [
        SliverFillRemaining(
          child: MgErrorView(error: e, what: tr.tr('eoMessagesLoadFail'), onRetry: onRetryAdmin),
        ),
      ],
    );
  }

  List<Widget> _threads(BuildContext context) {
    final tr = t(context);
    return threadsAsync.when(
      data: (threads) => [
        SliverToBoxAdapter(
          child: MgDarkHero(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr.tr('newConversation'), style: MgType.section.copyWith(color: MgColors.onDark)),
              const SizedBox(height: 4),
              Text(tr.tr('writeMotoGo'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              const SizedBox(height: 16),
              MgFabAvoid(
                child: MgCta(label: tr.tr('newConversation').toUpperCase(), onTap: onNewThread, arrow: true),
              ),
            ]),
          ),
        ),
        if (threads.isEmpty)
          SliverToBoxAdapter(child: MsgEmptyV2(icon: MgIcons.chat, text: tr.tr('noConversations')))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.separated(
              itemCount: threads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => MgReveal(
                index: i,
                child: MsgThreadCardV2(thread: threads[i], onTap: () => onOpenThread(threads[i])),
              ),
            ),
          ),
      ],
      loading: () => [SliverFillRemaining(child: MgLoadingView(onRetry: onRetryThreads))],
      error: (e, _) => [
        SliverFillRemaining(
          child: MgErrorView(error: e, what: tr.tr('eoMessagesLoadFail'), onRetry: onRetryThreads),
        ),
      ],
    );
  }
}
