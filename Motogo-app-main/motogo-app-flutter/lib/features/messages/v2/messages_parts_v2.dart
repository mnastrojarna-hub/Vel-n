import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../messages_provider.dart';

/// "d. m. H:MM" — today's date format of the message lists.
String msgDate(DateTime d) => '${d.day}. ${d.month}. ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// Line icon + tile colours of an admin message type (replaces the emoji).
(String, Color, Color) msgTypeIcon(String? type) => switch (type) {
      'sos_response' || 'sos_auto' => (MgIcons.firstAid, MgColors.errBg, MgColors.err),
      'accident_response' => (MgIcons.warn, MgColors.warnBg, MgColors.warn),
      'replacement' => (MgIcons.wrench, MgColors.well, MgColors.link),
      'tow' => (MgIcons.truck, MgColors.well, MgColors.link),
      'info' => (MgIcons.info, MgColors.well, MgColors.link),
      'thanks' => (MgIcons.heart, MgColors.well, MgColors.link),
      'voucher' => (MgIcons.gift, MgColors.panel, MgColors.neon),
      'door_codes' => (MgIcons.key, MgColors.panel, MgColors.neon),
      _ => (MgIcons.mail, MgColors.well, MgColors.link),
    };

/// Two-segment switch in the dark header (web `.km-sw`): sliding thumb in
/// the rank CTA material, red count on the first segment.
class MsgSegmentsV2 extends StatelessWidget {
  final String left;
  final String right;
  final bool rightOn;
  final int badge;
  final RankTokens rank;
  final ValueChanged<bool> onChanged;
  const MsgSegmentsV2({
    super.key,
    required this.left,
    required this.right,
    required this.rightOn,
    required this.badge,
    required this.rank,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool on, bool isRight, int count) => Expanded(
          child: Semantics(
            selected: on,
            button: true,
            label: count > 0 ? '$label, $count' : label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(isRight),
              child: Stack(clipBehavior: Clip.none, children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: AnimatedDefaultTextStyle(
                      duration: MgMotion.of(context, MgMotion.color),
                      style: DefaultTextStyle.of(context).style.merge(MgType.ctaCompact.copyWith(
                          letterSpacing: 0, color: on ? rank.ctaLabel : MgColors.onDarkLead)),
                      child: Text(label, textAlign: TextAlign.center, maxLines: 2),
                    ),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -8,
                    right: 2,
                    child: MgPop(
                      trigger: count,
                      playOnMount: true,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: MgColors.sos,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: MgColors.panel, width: 2),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(count > 9 ? '9+' : '$count',
                              style: MgType.tab(MgType.micro.copyWith(height: 1, color: MgColors.onDark))),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.neonA(0.2)),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: MgMotion.of(context, MgMotion.thumb),
          curve: MgMotion.out,
          alignment: rightOn ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: rank.ctaGradient,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rank.ctaEdge.first),
                boxShadow: rank.softGlow(blur: 12, dy: 4),
              ),
            ),
          ),
        ),
        Row(children: [seg(left, !rightOn, false, badge), seg(right, rightOn, true, 0)]),
      ]),
    );
  }
}

/// White notification card (`.nc`): unread = green bar + red dot (one ping),
/// 3 lines collapsed, full text expanded.
class MsgNoteCardV2 extends StatelessWidget {
  final AdminMessage m;
  final bool expanded;
  final VoidCallback onTap;
  const MsgNoteCardV2({super.key, required this.m, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (icon, bg, fg) = msgTypeIcon(m.type);
    final body = m.messageFor(tr.lang);
    final title = m.titleFor(tr.lang) ?? tr.tr('messageFromMotoGo');
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        expanded: expanded,
        child: MgPress(
          scale: 0.985,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: m.read ? MgColors.line : MgColors.link.withValues(alpha: 0.3)),
              boxShadow: MgShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!m.read) Container(width: 4, color: MgColors.routeGreen),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(m.read ? 16 : 12, 16, 16, 16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: bg == MgColors.panel ? MgColors.panel : MgColors.line),
                        ),
                        child: Center(child: MgIcon(icon, size: 22, color: fg)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Text(title,
                                  style: MgType.title.copyWith(
                                      fontWeight: m.read ? FontWeight.w700 : FontWeight.w800, color: MgColors.ink)),
                            ),
                            if (!m.read) ...[
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: MgPop(
                                  playOnMount: true,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(color: MgColors.sosDot, shape: BoxShape.circle),
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          if (body != null) ...[
                            const SizedBox(height: 4),
                            AnimatedSize(
                              duration: MgMotion.of(context, MgMotion.pop),
                              alignment: Alignment.topCenter,
                              child: Text(body,
                                  maxLines: expanded ? null : 3,
                                  overflow: expanded ? null : TextOverflow.ellipsis,
                                  style: MgType.body.copyWith(color: MgColors.body2)),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(children: [
                            Expanded(child: Text(msgDate(m.createdAt), style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta)))),
                            AnimatedRotation(
                              turns: expanded ? 0.5 : 0,
                              duration: MgMotion.of(context, MgMotion.pop),
                              child: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.meta),
                            ),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// White thread card (`.th`): SOS threads get the red first-aid tile.
class MsgThreadCardV2 extends StatelessWidget {
  final MessageThread thread;
  final VoidCallback onTap;
  const MsgThreadCardV2({super.key, required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final isSos = thread.subject?.startsWith('SOS:') ?? false;
    final preview = thread.lastMessage?.content ?? '';
    final date = thread.lastMessageAt ?? thread.createdAt;
    final unread = thread.unreadCount;
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        child: MgPress(
          scale: 0.985,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: unread > 0 ? MgColors.link.withValues(alpha: 0.3) : MgColors.line),
              boxShadow: MgShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (unread > 0) Container(width: 4, color: MgColors.routeGreen),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(unread > 0 ? 12 : 16, 16, 16, 16),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSos ? MgColors.errBg : MgColors.well,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSos ? MgColors.errBorder : MgColors.line),
                        ),
                        child: Center(
                          child: MgIcon(isSos ? MgIcons.firstAid : MgIcons.chat,
                              size: 22, color: isSos ? MgColors.err : MgColors.link),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(thread.subject ?? tr.tr('conversation'),
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                          if (preview.isNotEmpty)
                            Text(preview.length > 60 ? '${preview.substring(0, 60)}...' : preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MgType.small.copyWith(color: MgColors.lead)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(msgDate(date), style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                        if (unread > 0) ...[
                          const SizedBox(height: 6),
                          MgPop(
                            trigger: unread,
                            playOnMount: true,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(color: MgColors.routeGreen, borderRadius: BorderRadius.circular(999)),
                              child: Center(
                                widthFactor: 1,
                                child: Text('$unread',
                                    style: MgType.tab(MgType.micro.copyWith(height: 1, color: MgColors.onDark))),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state of a list (icon disc + text).
class MsgEmptyV2 extends StatelessWidget {
  final String icon;
  final String text;
  const MsgEmptyV2({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: MgColors.well, shape: BoxShape.circle, border: Border.all(color: MgColors.line)),
            child: Center(child: MgIcon(icon, size: 30, color: MgColors.link)),
          ),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: MgType.title.copyWith(color: MgColors.ink)),
        ]),
      );
}
