import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/gestures/mg_swipe.dart';
import '../../../core/v2/gestures/mg_swipe_switcher.dart';
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
import '../../reservations/v2/page_swipe_v2.dart';
import 'messages_parts_v2.dart';

/// Cards built eagerly inside the swiping body; the rest is a lazy sliver.
const kMsgSwipeHead = 12;

/// Zprávy in the v2 look (PLAN §2.5.2, seam view of `MessagesScreen`): dark
/// compact app bar with the 2-segment switch Oznámení [n] / Konverzace and
/// "Označit vše" (only while there is something unread), white notification
/// cards (expand, unread bar), the "NOVÁ KONVERZACE" dark card with the rank
/// CTA (existing create flow) and thread cards. Loading / error = the
/// existing state widgets. All state lives in the screen. A horizontal
/// swipe over the content switches Oznámení ↔ Konverzace (design G4 b —
/// the switch's tap twin; the thumb follows the finger), pull-to-refresh =
/// the tab's existing retry.
class MessagesViewV2 extends ConsumerStatefulWidget {
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
  ConsumerState<MessagesViewV2> createState() => _MessagesViewV2State();
}

class _MessagesViewV2State extends ConsumerState<MessagesViewV2> {
  final _drag = ValueNotifier<double>(0);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  bool get chatTab => widget.chatTab;

  /// Pull-to-refresh = the visible tab's existing retry (invalidate).
  Future<void> _refresh() async {
    (chatTab ? widget.onRetryThreads : widget.onRetryAdmin)();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final unread = widget.unread;
    final onBack = widget.onBack;
    final onMarkAll = widget.onMarkAll;
    final onTab = widget.onTab;
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
        dragProgress: _drag,
      ),
    );
    final (Widget? box, Widget? sliver) = chatTab ? _threads(context) : _notes(context);
    // Header, segment, empty space and the lazy rest of a long list switch
    // the tab too (page-wide swipe); the body below follows the finger.
    return V2PageSwipe(
      onStep: (dir) {
        if ((dir > 0) == chatTab) return false;
        onTab(dir > 0);
        return true;
      },
      child: MgPage(
        header: header,
        overlapHero: false,
        onRefresh: _refresh,
        sections: [
          if (box != null)
            MgSwipeSegments<bool>(
              values: const [false, true],
              value: chatTab,
              onChanged: onTab,
              progress: _drag,
              child: ConstrainedBox(
                // I krátký obsah má pod sebou plochu pro tah.
                constraints: const BoxConstraints(minHeight: 360),
                child: MgSwipeSwitcher(switchKey: chatTab, direction: chatTab ? 1 : -1, child: box),
              ),
            ),
        ],
        slivers: [if (sliver != null) sliver],
      ),
    );
  }

  /// (swipeable box, or a full-height state sliver).
  (Widget?, Widget?) _notes(BuildContext context) {
    final tr = t(context);
    return widget.adminAsync.when(
      data: (msgs) {
        if (msgs.isEmpty) {
          return (MsgEmptyV2(icon: MgIcons.mail, text: tr.tr('noNotifications')), null);
        }
        Widget note(int i) {
          final card = MsgNoteCardV2(
            key: ValueKey(msgs[i].id),
            m: msgs[i],
            expanded: widget.expanded.contains(msgs[i].id),
            onTap: () => widget.onToggleNote(msgs[i]),
          );
          // Only the first screenful reveals, once per app session — a
          // card scrolled back into view never blinks again.
          return i < 6 ? MgReveal(index: i, sessionKey: 'msg-notes', child: card) : card;
        }

        // First screenfuls in the swiping body, the rest lazily (unbounded
        // history never builds / repaints at once).
        final head = msgs.length < kMsgSwipeHead ? msgs.length : kMsgSwipeHead;
        return (
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < head; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                note(i),
              ],
            ]),
          ),
          msgs.length > head
              ? SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  sliver: SliverList.separated(
                    itemCount: msgs.length - head,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => note(head + i),
                  ),
                )
              : null
        );
      },
      loading: () => (null, SliverFillRemaining(child: MgLoadingView(onRetry: widget.onRetryAdmin))),
      error: (e, _) => (
        null,
        SliverFillRemaining(
          child: MgErrorView(error: e, what: tr.tr('eoMessagesLoadFail'), onRetry: widget.onRetryAdmin),
        )
      ),
    );
  }

  (Widget?, Widget?) _threads(BuildContext context) {
    final tr = t(context);
    final onNewThread = widget.onNewThread;
    return widget.threadsAsync.when(
      data: (threads) => (
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgDarkHero(
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
          if (threads.isEmpty)
            MsgEmptyV2(icon: MgIcons.chat, text: tr.tr('noConversations'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < threads.length && i < kMsgSwipeHead; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _thread(threads, i),
                ],
              ]),
            ),
        ]),
        threads.length > kMsgSwipeHead
            ? SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverList.separated(
                  itemCount: threads.length - kMsgSwipeHead,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _thread(threads, kMsgSwipeHead + i),
                ),
              )
            : null
      ),
      loading: () => (null, SliverFillRemaining(child: MgLoadingView(onRetry: widget.onRetryThreads))),
      error: (e, _) => (
        null,
        SliverFillRemaining(
          child: MgErrorView(error: e, what: tr.tr('eoMessagesLoadFail'), onRetry: widget.onRetryThreads),
        )
      ),
    );
  }

  Widget _thread(List<MessageThread> threads, int i) => MgReveal(
        key: ValueKey(threads[i].id),
        index: i < 6 ? i : 0,
        child: MsgThreadCardV2(thread: threads[i], onTap: () => widget.onOpenThread(threads[i])),
      );
}
