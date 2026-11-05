import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_cta.dart';
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
/// payment handoff, confirm page); this view adds only a visual mode: a
/// chooser of intents and one focused intent at a time. Picking an intent
/// calls the SAME tab closure as today's tab buttons (only when the tab
/// changes); hidden sections stay mounted (offstage) so nothing typed or
/// chosen is lost — as on today's single scroll.
class ResEditV2View extends StatefulWidget {
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
  final VoidCallback? onSave;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSelectExtend;
  final VoidCallback onSelectShorten;
  final VoidCallback onSelectMove;
  final VoidCallback onSelectSwap;

  /// Intent to open first (null = chooser) — used by tests / deep links.
  final ResEditIntent? initialIntent;

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
    required this.onSave,
    required this.saving,
    required this.onBack,
    required this.onSelectExtend,
    required this.onSelectShorten,
    required this.onSelectMove,
    required this.onSelectSwap,
    this.initialIntent,
  });

  @override
  State<ResEditV2View> createState() => _ResEditV2ViewState();
}

class _ResEditV2ViewState extends State<ResEditV2View> {
  late ResEditIntent? _intent = widget.initialIntent;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Switch chooser ↔ intent; the page starts at the top again.
  void _go(ResEditIntent? i) {
    setState(() => _intent = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  List<ResEditIntent> get _intents => [
        ResEditIntent.extend,
        ResEditIntent.shorten,
        if (widget.canMove) ResEditIntent.move,
        if (widget.canSwap) ResEditIntent.swap,
        if (!widget.isActive || widget.returnTimeAvailable) ResEditIntent.time,
        ResEditIntent.place,
        if (!widget.isActive) ResEditIntent.moto,
        if (!widget.isActive) ResEditIntent.gear,
      ];

  void _pick(ResEditIntent i) {
    final tab = resEditTabOf(i);
    // Stejné zavření jako dnešní tlačítka záložek — jen když se záložka mění
    // (sekce času / místa / motorky / výbavy patří k záložce Prodloužit).
    if (tab == null) {
      if (widget.tab == 'move' || widget.tab == 'swap') widget.onSelectExtend();
    } else if (tab != widget.tab) {
      switch (tab) {
        case 'extend':
          widget.onSelectExtend();
        case 'shorten':
          widget.onSelectShorten();
        case 'move':
          widget.onSelectMove();
        case 'swap':
          widget.onSelectSwap();
      }
    }
    _go(i);
  }

  bool _shows(Set<ResEditIntent> on) => _intent != null && on.contains(_intent);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = widget.sections;
    final i = _intent;
    final dateIntent = {ResEditIntent.extend, ResEditIntent.shorten, ResEditIntent.move};
    final showPrice = widget.calc.hasChanges && widget.tab != 'move' && widget.tab != 'swap';
    final focusDock = i != null && i != ResEditIntent.swap && widget.saveLabel != null;
    final chooserDock = i == null && widget.saveLabel != null && widget.onSave != null;
    Widget keep(bool visible, Widget? child) => child == null
        ? const SizedBox.shrink()
        : Visibility(visible: visible, maintainState: true, child: child);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (i == null) MgEnter(child: ResEditChooserV2(intents: _intents, onPick: _pick)),
      keep(_shows({ResEditIntent.swap}), s.swap),
      keep(_shows(dateIntent), s.calendar),
      if (_shows({ResEditIntent.move}) && widget.tab == 'move') ResEditNoteV2(tr.tr('moveFreeNote'), ok: true),
      if (_shows({ResEditIntent.shorten}) && widget.tab == 'shorten') ...[
        ResEditNoteV2('${tr.tr('stornoConditions')} ${tr.tr('stornoRules')}', warn: true),
        if (widget.stornoPct != null) ResStornoWarningV2(pct: widget.stornoPct!),
      ],
      keep(_shows({ResEditIntent.place}),
          s.pickupPlace == null ? null : ResEditGroupV2(title: tr.tr('pickupMotorcycle'), child: s.pickupPlace!)),
      keep(_shows({ResEditIntent.place}),
          s.returnPlace == null ? null : ResEditGroupV2(title: tr.tr('returnMotorcycle'), child: s.returnPlace!)),
      keep(
        _shows({ResEditIntent.time}),
        s.pickupTime == null
            ? null
            : ResEditGroupV2(
                title: tr.tr('pickupMotorcycle'),
                child: ResPickupTimeV2(
                  picker: s.pickupTime!,
                  legacyLine: s.pickupLegacyLine,
                  selfServiceHint: s.pickupSelfServiceHint,
                ),
              ),
      ),
      keep(_shows({ResEditIntent.time}),
          s.returnTime == null ? null : ResEditGroupV2(title: tr.tr('returnMotorcycle'), child: s.returnTime!)),
      keep(_shows({ResEditIntent.moto}), s.moto),
      keep(_shows({ResEditIntent.gear}), s.extras),
      if (i != ResEditIntent.swap && showPrice) ResEditPriceV2(booking: widget.booking, calc: widget.calc),
      if (i != null && i != ResEditIntent.swap && widget.missingSizes.isNotEmpty)
        ResMissingSizesV2(missing: widget.missingSizes),
    ]);

    final dock = (focusDock || chooserDock)
        ? MgDock(
            child: MgFabAvoid(
              child: MgCta(
                label: widget.saveLabel!,
                onTap: widget.onSave,
                enabled: widget.onSave != null,
                busy: widget.saving,
                loop: widget.onSave != null,
                arrow: true,
              ),
            ),
          )
        : null;

    return PopScope(
      canPop: i == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _intent != null) _go(null);
      },
      // Scaffold jako dosud: klávesnice (adresa přistavení) zmenší obsah.
      child: Scaffold(
        backgroundColor: MgColors.canvas,
        body: Column(children: [
          ResEditHeaderV2(
            booking: widget.booking,
            isActive: widget.isActive,
            title: i == null ? tr.tr('v2ResEditWhat') : resEditIntentTitle(tr, i),
            onBack: i == null ? widget.onBack : () => _go(null),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
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
