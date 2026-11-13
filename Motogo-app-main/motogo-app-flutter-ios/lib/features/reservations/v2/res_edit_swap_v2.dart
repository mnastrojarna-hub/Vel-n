import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';
import '../../payment/v2/pay_parts_v2.dart' show PayRoundingNoteV2;
import 'res_detail_bits_v2.dart';
import 'res_edit_moto_rows_v2.dart';
import 'res_edit_sections_v2.dart';

/// v2 look of `SwapMotoSection` ("Výměna motorky"): a DUMB view — the
/// section's State keeps every value (date, time, branch, chosen bike,
/// availability, price preview, saving) and hands its own closures in here
/// (date pick, time, branch filter, bike tap, confirm). Same texts (the
/// two formal ones in tykání), same rules: only a free bike is selectable,
/// a trailer booking cannot move to a self-service branch, the CTA is
/// live exactly when the old button was.
class SwapMotoViewV2 extends StatelessWidget {
  final String rangeText;
  final String dateText;
  final VoidCallback onPickDate;
  final Widget timePicker;
  final String currentMotoName;
  final Widget branchFilter;
  final AsyncValue<List<Motorcycle>> motos;
  final List<Motorcycle> Function(List<Motorcycle>) candidates;
  final Map<String, bool> avail;
  final bool availLoading;
  final String? selectedId;
  final bool Function(Motorcycle) trailerBlocked;
  final void Function(Motorcycle m, bool selected) onTapMoto;
  final double? net;
  final bool netLoading;
  final bool saving;
  final bool canConfirm;
  final VoidCallback onConfirm;

  const SwapMotoViewV2({
    super.key,
    required this.rangeText,
    required this.dateText,
    required this.onPickDate,
    required this.timePicker,
    required this.currentMotoName,
    required this.branchFilter,
    required this.motos,
    required this.candidates,
    required this.avail,
    required this.availLoading,
    required this.selectedId,
    required this.trailerBlocked,
    required this.onTapMoto,
    required this.net,
    required this.netLoading,
    required this.saving,
    required this.canConfirm,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final n = net;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: MgStateBanner(tone: MgTone.info, icon: MgIcons.swap, title: tr.tr('v2UxRpSwapNote')),
      ),
      EditCardV2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ResSectionEyebrowV2(tr.tr('swap.pickDate')),
          const SizedBox(height: 6),
          MgWordFit(child: Text(tr.tr('swap.title'), style: MgType.title.copyWith(color: MgColors.ink))),
          const SizedBox(height: 2),
          Text(tr.tr('v2UxRpSwapSub'), style: MgType.small.copyWith(color: MgColors.meta)),
          const SizedBox(height: 8),
          Text(rangeText, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead))),
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: '${tr.tr('swap.pickDate')}, $dateText',
            excludeSemantics: true,
            onTap: onPickDate,
            child: MgPress(
              key: const ValueKey('swap-v2-date'),
              onTap: onPickDate,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.circular(MgRadius.button),
                  border: Border.all(color: MgColors.lineInput, width: 1.5),
                ),
                child: Row(children: [
                  const MgIcon(MgIcons.calendarCheck, size: 20, color: MgColors.link),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(dateText, style: MgType.tab(MgType.section.copyWith(color: MgColors.ink))),
                  ),
                  const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          timePicker,
        ]),
      ),
      EditCardV2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: ResSectionEyebrowV2(tr.tr('swap.pickMoto'))),
            if (availLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)),
          ]),
          const SizedBox(height: 4),
          Text('${tr.tr('currentMoto')}: $currentMotoName', style: MgType.small.copyWith(color: MgColors.meta)),
          const SizedBox(height: 10),
          branchFilter,
          motos.when(
            data: (list) {
              final cands = candidates(list);
              if (cands.isEmpty) {
                // G-643: "no bike to swap to" as a visible state, not grey text.
                return MgStateBanner(
                  key: const ValueKey('swap-v2-no-moto'),
                  tone: MgTone.info,
                  icon: MgIcons.bike,
                  title: tr.tr('swap.noMoto'),
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final m in cands)
                  Builder(builder: (context) {
                    final free = avail[m.id];
                    final blocked = trailerBlocked(m);
                    final selected = selectedId == m.id;
                    return EditMotoRowV2(
                      moto: m,
                      selected: selected,
                      dim: free == false || blocked,
                      status: blocked
                          ? EditMotoStatus.trailer
                          : free == false
                              ? EditMotoStatus.busy
                              : (free == null && availLoading)
                                  ? EditMotoStatus.loading
                                  : free == true
                                      ? EditMotoStatus.free
                                      : EditMotoStatus.none,
                      onTap: free == true && !blocked ? () => onTapMoto(m, selected) : null,
                    );
                  }),
              ]);
            },
            loading: () => const Column(children: [
              MgSkeletonRow(thumb: 56, lines: 2),
              SizedBox(height: 8),
              MgSkeletonRow(thumb: 56, lines: 2),
            ]),
            error: (_, __) => Text(tr.tr('loadingError'), style: MgType.body.copyWith(color: MgColors.err)),
          ),
        ]),
      ),
      if (selectedId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _NetRowV2(net: n, loading: netLoading),
        ),
      if (selectedId != null && !netLoading && (n ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PayRoundingNoteV2(due: n!, roundKey: 'pdRoundSwapHint', waiveKey: 'pdWaiveSwapHint', showLine: false),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: MgBtnInk(
          key: const ValueKey('swap-v2-confirm'),
          label: tr.tr('swap.confirm').toUpperCase(),
          icon: MgIcons.arrowRight,
          neonLabel: true,
          busy: saving,
          onTap: canConfirm ? onConfirm : null,
        ),
      ),
    ]);
  }
}

/// Live price difference (dry-run): surcharge / refund / same, amount right.
class _NetRowV2 extends StatelessWidget {
  final double? net;
  final bool loading;
  const _NetRowV2({required this.net, required this.loading});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final n = net;
    final label = n == null
        ? tr.tr('swap.net.title')
        : n > 0.5
            ? tr.tr('swap.net.surcharge')
            : n < -0.5
                ? tr.tr('v2UxRpSwapRefund')
                : tr.tr('swap.net.same');
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
      ),
      child: Row(children: [
        // G-645: a surcharge must not show the "all fine" tick (old look: add_card
        // / savings / check) → pay for extra, refresh for money back, tick only
        // when the price stays the same.
        MgIcon(
            n == null
                ? MgIcons.card
                : n > 0.5
                    ? MgIcons.pay
                    : (n < -0.5 ? MgIcons.refresh : MgIcons.checkCircle),
            key: const ValueKey('swap-v2-net-icon'),
            size: 20,
            color: n != null && n > 0.5 ? MgColors.warn : MgColors.link),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
        if (loading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link))
        else if (n != null && n.abs() > 0.5)
          Text('${n > 0 ? '+' : '−'}${Money.czk(n.abs())}',
              style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: n < 0 ? MgColors.link : MgColors.ink))),
      ]),
    );
  }
}
