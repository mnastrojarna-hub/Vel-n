import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feature_flags.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../documents/docs_gate_provider.dart';
import '../../messages/messages_provider.dart' show adminUnreadCountProvider;
import 'profile_v2_parts.dart';

/// "Můj účet" tiles 2 × 3 (V21 §1.2): Zprávy (+ red count), Moje doklady
/// (status), Faktury, Dokumenty a smlouvy, Platební metody (the SAME push as
/// today, passed in), Pobočky; full-width E-shop card only with
/// `eshop_visible`. Statuses come from providers the shell already keeps
/// loaded — no new requests.
class ProfileTilesV2 extends ConsumerWidget {
  final VoidCallback onPaymentMethods;
  const ProfileTilesV2({super.key, required this.onPaymentMethods});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final unread = ref.watch(adminUnreadCountProvider);
    final docs = ref.watch(docsFabStatusProvider).valueOrNull;
    final eshop = ref.watch(eshopVisibleProvider).valueOrNull ?? false;

    String? docsSub;
    var docsTone = _Tone.meta;
    if (docs != null) {
      if (docs.isComplete) {
        docsSub = tr.tr('verified');
        docsTone = _Tone.ok;
      } else {
        final gate = docs.gate;
        final items = (gate != null && !gate.ok)
            ? docsGateMissingLabels(context, gate, docsOnly: true)
            : [
                if (!docs.hasIdOrPassport) tr.tr('idOrPassport'),
                if (!docs.hasLicense) tr.tr('driversLicense').toLowerCase(),
              ];
        docsSub = items.isEmpty ? tr.tr('docsNotVerified') : '${tr.tr('missing')}: ${items.join(', ')}';
        docsTone = _Tone.warn;
      }
    }

    final tiles = <Widget>[
      _Tile(
        icon: MgIcons.chat,
        label: tr.tr('messagesTitle'),
        sub: unread > 0 ? pfPlural(tr, 'v2PfMsgNew', unread) : tr.tr('v2PfMsgNone'),
        badge: unread,
        onTap: () => context.push(Routes.messages),
      ),
      _Tile(
        icon: MgIcons.idCard,
        label: tr.tr('documents'),
        sub: docsSub,
        tone: docsTone,
        onTap: () => context.push(Routes.docs),
      ),
      _Tile(
        icon: MgIcons.receipt,
        label: tr.tr('invoicesTitle'),
        sub: tr.tr('v2PfTileInvoicesSub'),
        onTap: () => context.push(Routes.invoices),
      ),
      _Tile(
        icon: MgIcons.docs,
        label: tr.tr('contracts'),
        sub: tr.tr('v2PfTileContractsSub'),
        onTap: () => context.push(Routes.contracts),
      ),
      _Tile(
        icon: MgIcons.card,
        label: tr.tr('paymentMethods'),
        sub: tr.tr('v2PfTilePaySub'),
        onTap: onPaymentMethods,
      ),
      _Tile(
        icon: MgIcons.pin,
        label: tr.tr('branchesLabel'),
        sub: tr.tr('v2PfTileBranchesSub'),
        onTap: () => context.push(Routes.branchesInfo),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < tiles.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: MgReveal(index: r, sessionKey: 'pf-tiles', child: tiles[r])),
              const SizedBox(width: 10),
              Expanded(child: MgReveal(index: r + 1, sessionKey: 'pf-tiles', child: tiles[r + 1])),
            ]),
          ),
        ],
        if (eshop) ...[
          const SizedBox(height: 10),
          MgReveal(
            index: 5,
            sessionKey: 'pf-tiles',
            child: _Tile(
              icon: MgIcons.bag,
              label: tr.tr('eshopMenu'),
              sub: tr.tr('v2PfShopSub'),
              wide: true,
              onTap: () => context.push(Routes.shop),
            ),
          ),
        ],
      ]),
    );
  }
}

enum _Tone { meta, ok, warn }

class _Tile extends StatelessWidget {
  final String icon;
  final String label;
  final String? sub;
  final _Tone tone;
  final int badge;
  final bool wide;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
    this.tone = _Tone.meta,
    this.badge = 0,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = switch (tone) {
      _Tone.ok => MgColors.link,
      _Tone.warn => MgColors.warn,
      _Tone.meta => MgColors.lead,
    };
    final iconBox = Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MgColors.line),
        ),
        child: Center(child: MgIcon(icon, size: 24, color: MgColors.link)),
      ),
      if (badge > 0)
        Positioned(
          top: -6,
          right: -8,
          child: MgPop(
            trigger: badge,
            playOnMount: true,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: MgColors.sos,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MgColors.surface, width: 2),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(badge > 9 ? '9+' : '$badge',
                    style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, height: 1, color: MgColors.onDark))),
              ),
            ),
          ),
        ),
    ]);
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: MgType.ctaCompact.copyWith(letterSpacing: 0, height: 1.25, color: MgColors.ink)),
      if (sub != null) ...[
        const SizedBox(height: 2),
        Row(children: [
          Flexible(child: Text(sub!, style: MgType.meta.copyWith(color: subColor))),
          if (tone == _Tone.ok) ...[
            const SizedBox(width: 4),
            const MgIcon(MgIcons.check, size: 14, color: MgColors.link, stroke: 2.6),
          ],
        ]),
      ],
    ]);
    final body = wide
        ? Row(children: [
            iconBox,
            const SizedBox(width: 12),
            Expanded(child: texts),
            const MgIcon(MgIcons.chevronRight, size: 16, color: MgColors.meta),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            iconBox,
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsetsDirectional.only(end: 20), child: texts),
          ]);
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        label: badge > 0 ? '$label, $badge' : label,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: wide ? 72 : 112),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.card,
            ),
            child: wide
                ? body
                : Stack(children: [
                    body,
                    const PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: MgIcon(MgIcons.chevronRight, size: 16, color: MgColors.meta),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
