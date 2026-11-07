import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../booking_models.dart';
import 'booking_v2_parts.dart';

/// Express layout of the booking form (Booking board "Máme to připravené",
/// DESIGN_V2 §8, CB-11): display parts only — the sections they open are
/// the form's own widgets, every value comes from the draft / breakdown.

/// ✓ / ! disc of an express row: neon ✓ when the part is ready, amber "!"
/// when something in it still blocks the booking (never colour-only).
class _StateDisc extends StatelessWidget {
  final bool ok;
  const _StateDisc({required this.ok});

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: ok ? MgColors.neon : MgColors.warnBg,
          shape: BoxShape.circle,
          border: Border.all(color: ok ? MgColors.neonLo : MgColors.warnBorder),
        ),
        child: Center(
          child: MgIcon(ok ? MgIcons.check : MgIcons.alert, size: 14, color: ok ? MgColors.onNeon : MgColors.warn, stroke: 2.6),
        ),
      );
}

/// "Změnit ⌄" link with the disclosure chevron (180° over `color`).
class _ChangeLink extends StatelessWidget {
  final bool open;
  const _ChangeLink({required this.open});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(t(context).tr('v2BkChange'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
        const SizedBox(width: 2),
        AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: MgMotion.of(context, MgMotion.color),
          child: MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
        ),
      ]);
}

/// Footer row of the recap card: "✓ TERMÍN A PŘEDÁNÍ … Změnit ⌄" — toggles
/// the date / time / pickup / return cards under the recap.
class BookingHandoverRowV2 extends StatelessWidget {
  final bool open;
  final bool ok;
  final VoidCallback onToggle;
  const BookingHandoverRowV2({super.key, required this.open, required this.ok, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = tr.tr('v2UxCbHandover');
    return Semantics(
      button: true,
      expanded: open,
      label: label,
      excludeSemantics: true,
      onTap: onToggle,
      child: MgPress(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              _StateDisc(ok: ok),
              const SizedBox(width: 10),
              Expanded(
                child: MgWordFit(
                  minScale: 0.75,
                  child: Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.ink)),
                ),
              ),
              const SizedBox(width: 8),
              _ChangeLink(open: open),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Máme to připravené" card: rank chip, Výbava (size mini-chips or
/// "Vlastní výbava") and Navíc (chosen extras · price) rows. Tapping the
/// header or a row toggles the form's own extras section under the card.
class BookingReadyCardV2 extends StatelessWidget {
  final BookingDraft draft;
  final PriceBreakdown bd;
  final bool open;
  final bool gearOk;
  final VoidCallback onToggle;

  const BookingReadyCardV2({
    super.key,
    required this.draft,
    required this.bd,
    required this.open,
    required this.gearOk,
    required this.onToggle,
  });

  List<(String, String)> _sizes() {
    final d = draft;
    final boots = d.extras.where((e) => e.id == 'extra-boty-ridic').firstOrNull?.size;
    return [
      if ((d.helmetSize ?? '').isNotEmpty) (MgIcons.helmet, d.helmetSize!),
      if ((d.glovesSize ?? '').isNotEmpty) (MgIcons.glove, d.glovesSize!),
      if ((d.jacketSize ?? '').isNotEmpty) (MgIcons.jacket, d.jacketSize!),
      if ((d.pantsSize ?? '').isNotEmpty) (MgIcons.pants, d.pantsSize!),
      if ((boots ?? '').isNotEmpty) (MgIcons.boot, boots!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rank = bd.loyaltyLevel >= 1
        ? RankCopy.chip(tr, RankCopy.name(tr, bd.loyaltyLevel, bd.loyaltyRankName), bd.loyaltyPercent)
        : null;
    final extras = [
      for (final e in draft.extras)
        if (e.id != 'extra-boty-ridic') extraLabel(tr.tr, e.id, e.name),
    ];
    final sizes = _sizes();
    Widget gearValue;
    if (draft.ownGear) {
      gearValue = Text(tr.tr('v2UxCbOwnGear'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink));
    } else if (sizes.isEmpty) {
      gearValue = MgWordFit(
        minScale: 0.75,
        child: Text(tr.tr('v2BkBlockSizes'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn)),
      );
    } else {
      gearValue = Wrap(spacing: 6, runSpacing: 6, children: [for (final s in sizes) _SizeMini(icon: s.$1, size: s.$2)]);
    }
    final extrasValue = extras.isEmpty
        ? Text(tr.tr('v2UxCbNoExtras'), style: MgType.body.copyWith(color: MgColors.lead))
        : Text.rich(TextSpan(children: [
            TextSpan(text: extras.join(', '), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            TextSpan(
              text: ' · ${bd.extrasTotal > 0 ? bkNb(bkMoney(bd.extrasTotal)) : tr.tr('free').toLowerCase()}',
              style: MgType.tab(MgType.small.copyWith(color: MgColors.meta)),
            ),
          ]));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: open,
          label: tr.tr('v2UxCbReadyTitle'),
          onTap: onToggle,
          child: MgPress(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MgSpace.card, MgSpace.card, MgSpace.card, 8),
              child: LayoutBuilder(builder: (context, c) {
                final title = tr.tr('v2UxCbReadyTitle');
                final style = MgType.section.copyWith(color: MgColors.ink);
                // "Změnit ⌄" beside the title while the title's longest word
                // still fits there; otherwise it moves to the chip line
                // (pl / large text — never a split word).
                final linkW = bkLineWidth(context, tr.tr('v2BkChange'), MgType.small.copyWith(fontWeight: FontWeight.w800)) + 28;
                final side = bkWordWidth(context, title, style) * 0.8 <= c.maxWidth - 52 - linkW;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const MgIconTileDark(MgIcons.shield, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: MgWordFit(minScale: 0.8, child: Text(title, style: style))),
                    if (side) ...[const SizedBox(width: 8), _ChangeLink(open: open)],
                  ]),
                  // Rank chip on its own line under the title (never faded).
                  if (rank != null || !side)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 52, top: 4),
                      // Each at its own width; the link wraps under the chip
                      // rather than squeezing it.
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (rank != null) MgRankChip(label: rank, onLight: true),
                          if (!side) _ChangeLink(open: open),
                        ],
                      ),
                    ),
                ]);
              }),
            ),
          ),
        ),
        _ReadyRow(label: tr.tr('v2UxCbGear'), ok: gearOk, value: gearValue, onTap: onToggle),
        const Divider(height: 1, thickness: 1, indent: MgSpace.card, endIndent: MgSpace.card, color: MgColors.line),
        _ReadyRow(label: tr.tr('v2UxCbExtras'), ok: true, value: extrasValue, onTap: onToggle),
        const SizedBox(height: 6),
      ]),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  final String label;
  final bool ok;
  final Widget value;
  final VoidCallback onTap;
  const _ReadyRow({required this.label, required this.ok, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => MgPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.card, vertical: 10),
            child: Builder(builder: (context) {
              final style = MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead);
              final text = Text(label, style: style);
              // Label column beside the value while its word fits 84 px
              // (cs / en); longer words (de, fr, uk, large text) sit above.
              final side = bkWordWidth(context, label, style) <= 84;
              return Row(children: [
                _StateDisc(ok: ok),
                const SizedBox(width: 10),
                if (side) ...[
                  SizedBox(width: 84, child: text),
                  const SizedBox(width: 8),
                  Expanded(child: value),
                ] else
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      text,
                      const SizedBox(height: 4),
                      value,
                    ]),
                  ),
                const SizedBox(width: 4),
                MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.meta),
              ]);
            }),
          ),
        ),
      );
}

/// Gear size mini-chip: line icon + size (well, 1 px line).
class _SizeMini extends StatelessWidget {
  final String icon;
  final String size;
  const _SizeMini({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(MgRadius.mapChip),
          border: Border.all(color: MgColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 14, color: MgColors.ink),
          const SizedBox(width: 4),
          Text(size, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
        ]),
      );
}

/// Half-width pill button (board "Kód nebo poukaz" / "Poznámka"): white,
/// 1 px line, icon + label 13/800, 48 tall.
class BookingChipButtonV2 extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const BookingChipButtonV2({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.card,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MgIcon(icon, size: 18, color: MgColors.link),
              const SizedBox(width: 8),
              Flexible(
                child: MgWordFit(
                  minScale: 0.75,
                  child: Text(label, style: MgType.small.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.ink)),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Row of the two express pills: "Kód nebo poukaz" ([onPromo] = the promo
/// section's own dialog) and the note pill passed in by the form view.
class BookingExpressChipsV2 extends StatelessWidget {
  final VoidCallback onPromo;
  final Widget? note;
  const BookingExpressChipsV2({super.key, required this.onPromo, this.note});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(child: BookingChipButtonV2(icon: MgIcons.tag, label: t(context).tr('v2UxCbPromoChip'), onTap: onPromo)),
          if (note != null) ...[const SizedBox(width: MgSpace.s8), Expanded(child: note!)],
        ]),
      );
}
