import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../messages_provider.dart';
import 'messages_parts_v2.dart';

/// Conversation thread in the v2 look (PLAN §2.5.2, seam view of
/// `ThreadDetailScreen`): dark app bar with an Aktivní / Uzavřeno chip,
/// bubbles (customer right ink, team left white), sticky input bar with a
/// round send button; a closed thread shows a banner instead of the input.
/// Loading / error / gone = the screen's existing state widget ([state]).
class ThreadViewV2 extends StatelessWidget {
  final MessageThread? thread;
  final Widget? state;
  final bool sending;
  final TextEditingController replyCtrl;
  final ScrollController scrollCtrl;
  final VoidCallback onBack;
  final VoidCallback onSend;

  const ThreadViewV2({
    super.key,
    required this.thread,
    required this.state,
    required this.sending,
    required this.replyCtrl,
    required this.scrollCtrl,
    required this.onBack,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final th = thread;
    final closed = th?.isClosed ?? false;
    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: Column(children: [
        MgAppBar(
          title: th?.subject ?? tr.tr('conversation'),
          onBack: onBack,
          actions: [if (th != null) _StatusChip(closed: closed, label: closed ? tr.tr('closed') : tr.tr('active'))],
        ),
        Expanded(
          child: state ??
              (th == null || th.messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: MsgEmptyV2(icon: MgIcons.chat, text: tr.tr('writeFirstMessage')),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      itemCount: th.messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Bubble(message: th.messages[i]),
                    )),
        ),
        if (state == null && closed) _ClosedBar(text: tr.tr('v2MsgThreadClosed')),
        if (state == null && !closed)
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: MgColors.surface,
              border: Border(top: BorderSide(color: MgColors.line)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: replyCtrl,
                  style: MgType.body.copyWith(color: MgColors.ink),
                  decoration: mgInputDecoration(context, hint: tr.tr('writeMessageHint')),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: tr.tr('send'),
                excludeSemantics: true,
                child: MgPress(
                  scale: 0.92,
                  onTap: onSend,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: MgColors.ink, shape: BoxShape.circle, boxShadow: MgShadows.icon),
                    child: Center(
                      child: sending
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.neon))
                          : const MgIcon(MgIcons.send, size: 20, color: MgColors.neon),
                    ),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool closed;
  final String label;
  const _StatusChip({required this.closed, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: closed ? MgColors.white(0.08) : MgColors.neonA(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: closed ? MgColors.white(0.25) : MgColors.neonA(0.45)),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label.toUpperCase(),
              style: MgType.micro.copyWith(
                  fontWeight: FontWeight.w800, height: 1, letterSpacing: 0.4,
                  color: closed ? MgColors.onDarkLead : MgColors.neonText)),
        ),
      );
}

class _ClosedBar extends StatelessWidget {
  final String text;
  const _ClosedBar({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: const BoxDecoration(
          color: MgColors.well,
          border: Border(top: BorderSide(color: MgColors.line)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const MgIcon(MgIcons.lock, size: 20, color: MgColors.lead),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead))),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  final Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final me = message.isCustomer;
    final c = message.createdAt;
    final stamp = '${c.day}. ${c.month}. ${c.hour}:${c.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: MgEnter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: me ? MgColors.ink : MgColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(me ? 18 : 6),
                bottomRight: Radius.circular(me ? 6 : 18),
              ),
              border: me ? null : Border.all(color: MgColors.line),
              boxShadow: me ? MgShadows.icon : MgShadows.card,
            ),
            child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              Text(message.content ?? '', style: MgType.body.copyWith(color: me ? MgColors.onDark : MgColors.ink)),
              const SizedBox(height: 4),
              Text(stamp, style: MgType.tab(MgType.micro.copyWith(color: me ? MgColors.onDarkSecondary : MgColors.meta))),
            ]),
          ),
        ),
      ),
    );
  }
}
