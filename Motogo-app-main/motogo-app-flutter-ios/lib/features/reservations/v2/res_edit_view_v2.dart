import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_fold_header.dart';
import '../../../core/v2/chrome/mg_hide_on_scroll.dart' show MgBarsHost;
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_segmented.dart';
import '../reservation_edit_price_calc.dart';
import '../reservation_models.dart';
import 'res_edit_chooser_v2.dart';
import 'res_edit_header_v2.dart';
import 'res_edit_notes_v2.dart';
import 'res_edit_price_v2.dart';

/// The section widgets of today's edit screen, built by its State with the
/// SAME arguments and closures as the old tree (null = today's condition
/// hides it for the current tab).
class ResEditV2Sections {
  final Widget? swap;
  final Widget? calendar;
  final Widget? pickupPlace;
  final Widget? pickupTime;
  final bool pickupLegacyLine;
  final bool pickupSelfServiceHint;
  final Widget? returnPlace;
  final Widget? returnTime;
  final Widget? moto;
  final Widget? extras;
  const ResEditV2Sections({
    this.swap,
    this.calendar,
    this.pickupPlace,
    this.pickupTime,
    this.pickupLegacyLine = false,
    this.pickupSelfServiceHint = false,
    this.returnPlace,
    this.returnTime,
    this.moto,
    this.extras,
  });
}

/// Reservation edit, v2 look (PLAN §2.4.3, seam S). The old `_EditState`
/// keeps everything (load, normalisation, price calc, save / move / swap,
/// payment handoff, confirm page); this view draws the OLD single scroll in
/// the v2 look (owner 2026-11-07 "jen upgrade vzhledu"): the tab row
/// (Prodloužit / Zkrátit / Posunout if [canMove] / Výměna if [canSwap]) as
/// an `MgSegmented` wired to the SAME tab closures, opening on [tab]
/// ('extend', or 'swap' for `?tab=swap`), then every section of that tab
/// open in the old order — calendar, pickup (place + time + legacy line +
/// self-service hint), return (place + time), moto, extras, storno notes,
/// price overview, missing sizes — and the always-present save CTA in the
/// dock (disabled while [onSave] is null; the swap tab has its own button).
class ResEditV2View extends StatelessWidget {
  final Reservation booking;
  final String tab;
  final bool isActive;
  final bool canMove;
  final bool canSwap;
  final bool returnTimeAvailable;
  final EditPriceCalc calc;
  final ResEditV2Sections sections;
  final int? stornoPct;
  final List<String> missingSizes;
  final String? saveLabel;

  /// Card surcharge of the change ("4 296 Kč") — the dock CTA then reads
  /// "ZAPLATIT DOPLATEK · 4 296 Kč" (amount never uppercased or broken).
  final String? savePrice;

  /// "Původně 12 027 Kč → nově 16 323 Kč" over the CTA (existing totals).
  final String? saveContext;
  final VoidCallback? onSave;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSelectExtend;
  final VoidCallback onSelectShorten;
  final VoidCallback onSelectMove;
  final VoidCallback onSelectSwap;

  const ResEditV2View({
    super.key,
    required this.booking,
    required this.tab,
    required this.isActive,
    required this.canMove,
    required this.canSwap,
    required this.returnTimeAvailable,
    required this.calc,
    required this.sections,
    required this.stornoPct,
    required this.missingSizes,
    required this.saveLabel,
    this.savePrice,
    this.saveContext,
    required this.onSave,
    required this.saving,
    required this.onBack,
    required this.onSelectExtend,
    required this.onSelectShorten,
    required this.onSelectMove,
    required this.onSelectSwap,
  });

  void _select(String t) {
    if (t == tab) return;
    switch (t) {
      case 'extend':
        onSelectExtend();
      case 'shorten':
        onSelectShorten();
      case 'move':
        onSelectMove();
      case 'swap':
        onSelectSwap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = sections;
    final showPrice = calc.hasChanges && tab != 'move' && tab != 'swap';
    final pickupTime = s.pickupTime;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: MgSegmented<String>(
          key: const ValueKey('res-edit-tabs'),
          segments: [
            MgSegment(value: 'extend', label: resEditIntentTitle(tr, ResEditIntent.extend)),
            MgSegment(value: 'shorten', label: resEditIntentTitle(tr, ResEditIntent.shorten)),
            if (canMove) MgSegment(value: 'move', label: resEditIntentTitle(tr, ResEditIntent.move)),
            if (canSwap) MgSegment(value: 'swap', label: resEditIntentTitle(tr, ResEditIntent.swap)),
          ],
          value: tab,
          onChanged: _select,
        ),
      ),
      if (s.swap != null) s.swap!,
      if (s.calendar != null) s.calendar!,
      if (tab == 'move') ResEditNoteV2(tr.tr('moveFreeNote'), ok: true),
      if (s.pickupPlace != null || pickupTime != null)
        ResEditGroupV2(
          title: tr.tr('pickupMotorcycle'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.pickupPlace != null) s.pickupPlace!,
            if (pickupTime != null) ...[
              const SizedBox(height: 8),
              ResPickupTimeV2(
                picker: pickupTime,
                legacyLine: s.pickupLegacyLine,
                selfServiceHint: s.pickupSelfServiceHint,
              ),
            ],
          ]),
        ),
      if (s.returnPlace != null || s.returnTime != null)
        ResEditGroupV2(
          title: tr.tr('returnMotorcycle'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.returnPlace != null) s.returnPlace!,
            if (s.returnTime != null) ...[const SizedBox(height: 8), s.returnTime!],
          ]),
        ),
      if (s.moto != null) s.moto!,
      if (s.extras != null) s.extras!,
      if (tab == 'shorten') ...[
        ResEditNoteV2('${tr.tr('stornoConditions')} ${tr.tr('stornoRules')}', warn: true),
        if (stornoPct != null) ResStornoWarningV2(pct: stornoPct!),
      ],
      if (showPrice) ResEditPriceV2(booking: booking, calc: calc),
      // Blocker on the same page as the CTA (old page).
      if (tab != 'swap' && missingSizes.isNotEmpty) ResMissingSizesV2(missing: missingSizes),
    ]);

    final dock = saveLabel == null
        ? null
        : MgDock(
            contextLine: saveContext == null
                ? null
                : Text(saveContext!,
                    key: const ValueKey('res-edit-pay-diff'),
                    style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead))),
            child: MgFabAvoid(
              child: MgCta(
                label: saveLabel!,
                price: savePrice,
                onTap: onSave,
                enabled: onSave != null,
                busy: saving,
                loop: onSave != null,
                arrow: true,
              ),
            ),
          );

    // Scaffold jako dosud: klávesnice (adresa přistavení) zmenší obsah.
    return Scaffold(
      backgroundColor: MgColors.canvas,
      // Hide-on-scroll: the tall header folds while the form scrolls down.
      body: MgBarsHost(
        child: Column(children: [
          MgFoldHeader(
            child: ResEditHeaderV2(
              booking: booking,
              isActive: isActive,
              title: tr.tr('editReservation'),
              onBack: onBack,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: dock == null ? MediaQuery.paddingOf(context).bottom + 24 : 24),
              child: body,
            ),
          ),
          if (dock != null) dock,
        ]),
      ),
    );
  }
}
