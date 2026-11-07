import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import '../widgets/res_pickup_procedure.dart';
import 'res_status_v2.dart' show resRangeDays, resRangeShort;

enum _Node { done, current, future, cancelled }

/// "Tvoje cesta" (V22 C10, light): Zaplaceno → Převzetí → Jízda → Vrácení
/// (self-service: Zaplaceno → Šatna → Protokol → Motorka → Vrácení),
/// derived ONLY from today's fields (payment status, handover, display
/// status, completion). The current node pings (the screen's one live
/// loop; static under reduced motion); a cancelled booking shows every
/// node dashed.
class ResJourneyV2 extends StatelessWidget {
  final Reservation res;
  const ResJourneyV2({super.key, required this.res});

  static const _paidStates = {'paid', 'partial_refund', 'refund_pending', 'refunded'};

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final st = res.displayStatus;
    final cancelled = st == ResStatus.cancelled;
    final paid = _paidStates.contains(res.paymentStatus);
    final returned = res.status == 'completed' || res.returnedAt != null || st == ResStatus.dokoncene;
    final pickupSub = res.pickupHm == null || res.pickupAllDayLegacy
        ? tripShortDate(tr, res.startDate)
        : '${tripShortDate(tr, res.startDate)} ${res.pickupHm}';
    final rt = (res.returnTime ?? '').trim();
    final returnSub = '${tripShortDate(tr, res.endDate)}${rt.length >= 5 ? ' ${rt.substring(0, 5)}' : ''}';
    // Samoobsluha (Reservation board): Zaplaceno · Šatna · Protokol ·
    // Motorka · Vrácení — šatna jen s výbavou k vyzvednutí; jinak (obsluha,
    // přistavení) Zaplaceno · Převzetí · Jízda · Vrácení. Jen ze stávajících
    // polí rezervace (šatna = první zavření, protokol = podpis, motorka =
    // vydání); krok „Doklady" by potřeboval nový dotaz → rozhodnutí majitele.
    final kiosk = ResPickupProcedure.visibleFor(res) || (res.isSelfService && returned && res.pickupMethod != 'delivery');
    final List<(String, String?, bool)> raw = kiosk
        ? [
            (tr.tr('v2ResJPaid'), null, paid),
            if (ResPickupProcedure.needsLocker(res, null))
              (tr.tr('v2UxRpJLocker'), null, res.gearCollectedAt != null),
            (tr.tr('v2UxRpJProtocol'), null, res.protocolSigned),
            (tr.tr('v2UxRpJBike'), null, res.isHandedOver),
            (tr.tr('v2ResJReturn'), returnSub, returned),
          ]
        : [
            (tr.tr('v2ResJPaid'), null, paid),
            (tr.tr('v2ResJPickup'), null, res.isHandedOver),
            (tr.tr('v2ResJRide'), null, returned),
            (tr.tr('v2ResJReturn'), returnSub, returned),
          ];
    // Čas vyzvednutí pod prvním krokem po zaplacení (board „Šatna · pá 12:00").
    final withSub = [
      for (var i = 0; i < raw.length; i++) (raw[i].$1, i == 1 ? pickupSub : raw[i].$2, raw[i].$3),
    ];
    // Kroky jdou za sebou: hotový pozdější krok znamená hotové i ty před ním
    // (starší rezervace bez času šatny nesvítí „teď" před hotovým protokolem).
    final done = [for (final n in withSub) n.$3];
    for (var i = done.length - 2; i >= 0; i--) {
      done[i] = done[i] || done[i + 1];
    }
    final firstOpen = done.indexOf(false);
    _Node stateOf(int i) {
      if (cancelled) return _Node.cancelled;
      if (done[i]) return _Node.done;
      return i == firstOpen ? _Node.current : _Node.future;
    }

    final nodes = [for (final n in withSub) (n.$1, n.$2)];
    // Termín a délka jednou, tady (Reservation board „pá 16. 10. – ne 18. 10.
    // · 3 dny"); zalomí se pod nadpis, když se vedle nevejde.
    final range = Text(
      cancelled ? '${tr.cancelled} · ${resRangeShort(tr, res)}' : resRangeDays(tr, res),
      style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: cancelled ? MgColors.err : MgColors.lead)),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [MgEyebrowDark(tr.tr('v2ResJourney')), range],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        Widget cell(int i, bool vertical) => MgReveal(
              index: i,
              child: _NodeCell(
                vertical: vertical,
                label: nodes[i].$1,
                sub: nodes[i].$2,
                state: stateOf(i),
                left: i == 0 ? null : _lineColor(stateOf(i)),
                right: i == nodes.length - 1 ? null : _lineColor(stateOf(i + 1)),
                a11yState: cancelled
                    ? tr.cancelled
                    : done[i]
                        ? tr.tr('v2ResJDone')
                        : (i == firstOpen ? tr.tr('v2ResJNow') : tr.tr('v2ResJWaiting')),
              ),
            );
        // Celá slova („Повернення", „Devolución" ve čtvrtině 320 dp s velkým
        // písmem) zmenšená nejvýš na 80 %; když se ani tak nevejdou, cesta
        // se vykreslí svisle (r2: dřív zmenšení až na 70 %).
        // Datum a čas pod krokem („po 9. 11. 23:59") se taky musí vejít celý
        // (nejvýš 2 řádky, nikdy rozdělené slovo) — jinak svisle (klíčová
        // informace se nikdy neořízne).
        final cellW = c.maxWidth / nodes.length;
        bool subFits(String? s) =>
            s == null ||
            (mgWordsFit(context, s, _NodeCell.subStyle, cellW - 1) &&
                mgLinesFit(context, s, _NodeCell.subStyle, cellW - 1, 2, dir: Directionality.of(context)));
        final across = !c.maxWidth.isFinite ||
            nodes.every((n) =>
                mgWordsFit(context, n.$1, _NodeCell.labelStyle, cellW - 1, minScale: _NodeCell.minScale) &&
                subFits(n.$2));
        if (!across) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < nodes.length; i++) cell(i, true),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < nodes.length; i++) Expanded(child: cell(i, false)),
        ]);
      }),
    ]);
  }
}

Color _lineColor(_Node s) => s == _Node.done || s == _Node.current ? MgColors.routeGreen : MgColors.line;

class _NodeCell extends StatelessWidget {
  final String label;
  final String? sub;
  final _Node state;
  final Color? left;
  final Color? right;
  final String a11yState;
  final bool vertical;
  const _NodeCell({
    required this.vertical,
    required this.label,
    required this.sub,
    required this.state,
    required this.left,
    required this.right,
    required this.a11yState,
  });

  @override
  Widget build(BuildContext context) {
    Widget disc;
    switch (state) {
      case _Node.done:
        disc = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MgColors.neon,
            shape: BoxShape.circle,
            border: Border.all(color: MgColors.routeGreen, width: 1.5),
          ),
          child: const Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onNeon, stroke: 2.8)),
        );
      case _Node.current:
        disc = MgPing(
          size: 28,
          color: MgColors.neonA(0.7),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: MgColors.ink,
              shape: BoxShape.circle,
              border: Border.all(color: MgColors.neon, width: 3),
            ),
          ),
        );
      case _Node.future:
        disc = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MgColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: MgColors.line, width: 2),
          ),
        );
      case _Node.cancelled:
        disc = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MgColors.well,
            shape: BoxShape.circle,
            border: Border.all(color: MgColors.disabled, width: 1.5),
          ),
          child: const Center(child: MgIcon(MgIcons.close, size: 12, color: MgColors.disabled)),
        );
    }
    final strong = state == _Node.done || state == _Node.current;
    final labelText = Text(label,
        textAlign: vertical ? TextAlign.start : TextAlign.center,
        maxLines: 2,
        style: labelStyle.copyWith(color: strong ? MgColors.ink : MgColors.meta));
    final subText = sub == null
        ? null
        : Text(sub!,
            textAlign: vertical ? TextAlign.start : TextAlign.center,
            maxLines: 2,
            style: subStyle);
    if (vertical) {
      // Svislá cesta: kolečko + spojnice vlevo, popisek vpravo.
      return Semantics(
        label: '$label, $a11yState${sub == null ? '' : ', $sub'}',
        excludeSemantics: true,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 28,
              child: Column(children: [
                disc,
                Expanded(child: Container(width: 2, constraints: const BoxConstraints(minHeight: 8), color: right ?? Colors.transparent)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(minScale: minScale, child: labelText),
                  if (subText != null) ...[const SizedBox(height: 2), subText],
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    return Semantics(
      label: '$label, $a11yState${sub == null ? '' : ', $sub'}',
      excludeSemantics: true,
      child: Column(children: [
        SizedBox(
          height: 28,
          child: Stack(alignment: Alignment.center, children: [
            Row(children: [
              Expanded(child: Container(height: 2, color: left ?? Colors.transparent)),
              Expanded(child: Container(height: 2, color: right ?? Colors.transparent)),
            ]),
            disc,
          ]),
        ),
        const SizedBox(height: 6),
        MgWordFit(minScale: minScale, alignment: Alignment.topCenter, child: labelText),
        if (subText != null) ...[const SizedBox(height: 2), subText],
      ]),
    );
  }

  static const minScale = 0.8;
  static final labelStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800, height: 1.15);
  static final subStyle = MgType.tab(MgType.micro.copyWith(color: MgColors.link));
}
