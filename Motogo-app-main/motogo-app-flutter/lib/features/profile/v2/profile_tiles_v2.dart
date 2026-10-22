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
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/catalog_provider.dart' show branchesProvider, motorcyclesProvider;
import '../../documents/docs_gate_provider.dart';
import '../../messages/messages_provider.dart' show adminUnreadCountProvider;
import 'profile_fit.dart';
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
    // Pobočky z DB (už načtený katalog — nic se kvůli dlaždici nestahuje);
    // statický text jen než / když se katalog nenačte.
    final branchNames = ref.exists(motorcyclesProvider)
        ? [
            for (final b in ref.watch(branchesProvider))
              if ((b['name'] as String?)?.trim().isNotEmpty ?? false) (b['name'] as String).trim(),
          ]
        : const <String>[];

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

    final specs = <_TileSpec>[
      (
        icon: MgIcons.chat,
        label: tr.tr('messagesTitle'),
        sub: unread > 0 ? pfPlural(tr, 'v2PfMsgNew', unread) : tr.tr('v2PfMsgNone'),
        tone: _Tone.meta,
        badge: unread,
        onTap: () => context.push(Routes.messages),
      ),
      (
        icon: MgIcons.idCard,
        label: tr.tr('documents'),
        sub: docsSub,
        tone: docsTone,
        badge: 0,
        onTap: () => context.push(Routes.docs),
      ),
      (
        icon: MgIcons.receipt,
        label: tr.tr('invoicesTitle'),
        sub: tr.tr('v2PfTileInvoicesSub'),
        tone: _Tone.meta,
        badge: 0,
        onTap: () => context.push(Routes.invoices),
      ),
      (
        icon: MgIcons.docs,
        label: tr.tr('contracts'),
        sub: tr.tr('v2PfTileContractsSub'),
        tone: _Tone.meta,
        badge: 0,
        onTap: () => context.push(Routes.contracts),
      ),
      (
        icon: MgIcons.card,
        label: tr.tr('paymentMethods'),
        sub: tr.tr('v2PfTilePaySub'),
        tone: _Tone.meta,
        badge: 0,
        onTap: onPaymentMethods,
      ),
      (
        icon: MgIcons.pin,
        label: tr.tr('branchesLabel'),
        sub: branchNames.isEmpty ? tr.tr('v2PfTileBranchesSub') : branchNames.join(' · '),
        tone: _Tone.meta,
        badge: 0,
        onTap: () => context.push(Routes.branchesInfo),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // 2 × 3 grid while every word fits its half (scaled to 0.85 at most);
      // otherwise (de / nl / uk at 320 dp, large text) one wide tile per row
      // — a label never breaks inside a word (verify:render).
      child: LayoutBuilder(builder: (context, box) {
        final grid = specs.every((x) => _Tile.fitsCell(context, x, (box.maxWidth - 10) / 2));
        _Tile tile(_TileSpec x) => _Tile(spec: x, wide: !grid);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (grid)
            for (var r = 0; r < specs.length; r += 2) ...[
              if (r > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: MgReveal(index: r, sessionKey: 'pf-tiles', child: tile(specs[r]))),
                  const SizedBox(width: 10),
                  Expanded(child: MgReveal(index: r + 1, sessionKey: 'pf-tiles', child: tile(specs[r + 1]))),
                ]),
              ),
            ]
          else
            for (var i = 0; i < specs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              MgReveal(index: i, sessionKey: 'pf-tiles', child: tile(specs[i])),
            ],
          if (eshop) ...[
            const SizedBox(height: 10),
            MgReveal(
              index: 5,
              sessionKey: 'pf-tiles',
              child: _Tile(
                spec: (
                  icon: MgIcons.bag,
                  label: tr.tr('eshopMenu'),
                  sub: tr.tr('v2PfShopSub'),
                  tone: _Tone.meta,
                  badge: 0,
                  onTap: () => context.push(Routes.shop),
                ),
                wide: true,
              ),
            ),
          ],
        ]);
      }),
    );
  }
}

typedef _TileSpec = ({String icon, String label, String? sub, _Tone tone, int badge, VoidCallback onTap});

enum _Tone { meta, ok, warn }

class _Tile extends StatelessWidget {
  final _TileSpec spec;
  final bool wide;
  const _Tile({required this.spec, this.wide = false});

  static const _minScale = 0.85;
  static final _labelStyle = MgType.ctaCompact.copyWith(letterSpacing: 0, height: 1.25, color: MgColors.ink);

  /// true when the label and the status of [x] keep whole words in a grid
  /// cell [cell] wide (12 padding + 1 border each side, 20 reserved for the
  /// chevron next to the last line, 18 for the ✓).
  static bool fitsCell(BuildContext context, _TileSpec x, double cell) {
    final w = cell - 26;
    final sub = x.sub;
    if (!pfWordsFit(context, x.label, _labelStyle, sub == null ? w - 20 : w, minScale: _minScale)) return false;
    return sub == null ||
        pfWordsFit(context, sub, MgType.meta, w - 20 - (x.tone == _Tone.ok ? 18 : 0), minScale: _minScale);
  }

  @override
  Widget build(BuildContext context) {
    final x = spec;
    final subColor = switch (x.tone) {
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
        child: Center(child: MgIcon(x.icon, size: 24, color: MgColors.link)),
      ),
      if (x.badge > 0)
        Positioned(
          top: -6,
          right: -8,
          child: MgPop(
            trigger: x.badge,
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
                child: Text(x.badge > 9 ? '9+' : '${x.badge}',
                    style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w800, height: 1, color: MgColors.onDark))),
              ),
            ),
          ),
        ),
    ]);
    // Grid tile: the chevron sits bottom-end → only the LAST text block
    // keeps 20 px free next to it (the label gets the full width).
    final chevronGap = EdgeInsetsDirectional.only(end: wide ? 0 : 20);
    final label = MgWordFit(minScale: _minScale, child: Text(x.label, style: _labelStyle));
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (x.sub == null) Padding(padding: chevronGap, child: label) else label,
      if (x.sub != null) ...[
        const SizedBox(height: 2),
        Padding(
          padding: chevronGap,
          child: Row(children: [
            Flexible(
              child: MgWordFit(
                minScale: _minScale,
                child: Text(x.sub!, style: MgType.meta.copyWith(color: subColor)),
              ),
            ),
            if (x.tone == _Tone.ok) ...[
              const SizedBox(width: 4),
              const MgIcon(MgIcons.check, size: 14, color: MgColors.link, stroke: 2.6),
            ],
          ]),
        ),
      ],
    ]);
    final body = wide
        ? Row(children: [
            iconBox,
            const SizedBox(width: 12),
            Expanded(child: texts),
            const SizedBox(width: 8),
            const MgIcon(MgIcons.chevronRight, size: 16, color: MgColors.meta),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            iconBox,
            const SizedBox(height: 8),
            texts,
          ]);
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        label: x.badge > 0 ? '${x.label}, ${x.badge}' : x.label,
        child: MgPress(
          onTap: x.onTap,
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
