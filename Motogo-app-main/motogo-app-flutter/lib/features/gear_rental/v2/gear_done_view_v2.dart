import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../gear_done_screen.dart';
import '../gear_order_ui.dart';

/// v2 děkovací stránka výpůjčky výbavy (T1 výsledek): ověřování platby,
/// „Hotovo, výbava je tvoje!“ se souhrnem, nahrání dokladu totožnosti,
/// další kroky, „Zobrazit rezervaci“ / „Zpět na úvod“; ostatní stavy webu.
class GearDoneViewV2 extends StatelessWidget {
  final GearDoneStage stage;
  final GearDoneInfo? info;
  final GearDoneActions actions;
  const GearDoneViewV2({super.key, required this.stage, required this.info, required this.actions});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final i = info;
    final summary = i == null ? null : GearDoneSummaryV2(info: i);
    final show = MgStateAction(tr.tr('groShowBooking'), actions.showBooking);
    final home = MgStateAction(tr.tr('groOkHome'), actions.home);
    final Widget screen = switch (stage) {
      GearDoneStage.wait => MgStateScreen(
          key: const ValueKey('gear-done-wait'),
          tone: MgTone.pending,
          title: tr.tr('groOkWait'),
          support: false,
          loop: false,
        ),
      GearDoneStage.paid => MgStateScreen(
          key: const ValueKey('gear-done-paid'),
          tone: MgTone.ok,
          title: tr.tr('groOkTitle'),
          why: tr.tr('groOkLead'),
          summary: summary,
          support: false,
          primary: show,
          secondary: home,
          onClose: actions.home,
          children: [
            if (i!.docsNeeded) GearDocsCardV2(self: i.self, onUpload: actions.uploadDocs),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${tr.tr(i.self ? 'groOkNextSelf' : 'groOkNextStaffed')} ${tr.tr(i.self ? 'groOkReturnSelf' : 'groOkReturn')}',
                key: const ValueKey('gear-done-next'),
                style: MgType.small.copyWith(color: MgColors.body2),
              ),
            ),
          ],
        ),
      GearDoneStage.pay => MgStateScreen(
          key: const ValueKey('gear-done-pay'),
          tone: MgTone.warn,
          title: tr.tr('groResTitle'),
          why: tr.tr('groResLead'),
          summary: summary,
          support: false,
          primary: MgStateAction(tr.trArgs('groResPay', {'amount': gearMoney(i!.toPay)}), actions.pay),
          secondary: home,
          onClose: actions.home,
        ),
      _ => MgStateScreen(
          key: ValueKey('gear-done-${stage.name}'),
          tone: switch (stage) {
            GearDoneStage.pending => MgTone.pending,
            GearDoneStage.completed => MgTone.info,
            _ => MgTone.warn,
          },
          title: tr.tr(switch (stage) {
            GearDoneStage.pending => 'groOkPending',
            GearDoneStage.cancelled => 'groResCancelled',
            GearDoneStage.completed => 'groResCompleted',
            _ => 'groResNf',
          }),
          summary: summary,
          support: stage != GearDoneStage.completed,
          primary: i != null ? show : home,
          secondary: i != null ? home : null,
          onClose: actions.home,
          loop: false,
        ),
    };
    return ColoredBox(color: MgColors.canvas, child: screen);
  }
}

/// Souhrn výpůjčky (číslo, pobočka, termín · čas, kusy, poukaz, celkem).
class GearDoneSummaryV2 extends StatelessWidget {
  final GearDoneInfo info;
  const GearDoneSummaryV2({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    final i = info;
    final small = MgType.small.copyWith(color: MgColors.body2);
    Widget row(String icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIcon(icon, size: 16, color: MgColors.link),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: small.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
          ]),
        );
    final period = i.start == null
        ? null
        : '${gearPeriod(tr, i.start!, i.end ?? i.start!)}'
            '${i.days > 0 ? ' (${i.days} ${tr.daysWord(i.days)})' : ''}'
            '${i.pickupTime != null ? ' · ${i.pickupTime}' : ''}';
    return Column(key: const ValueKey('gear-done-summary'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (i.number.isNotEmpty)
        Row(children: [
          Expanded(child: Text(tr.tr('groOkOrder'), style: small)),
          Text(i.number, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
        ]),
      if (i.branchLine.isNotEmpty) row(MgIcons.pin, i.branchLine),
      if (period != null) row(MgIcons.calendarCheck, period),
      for (final (label, sizes) in i.lines((x) => gearLc(lang, x)))
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 22),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: label, style: small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            if (sizes.isNotEmpty) TextSpan(text: '  $sizes', style: small.copyWith(color: MgColors.lead)),
          ])),
        ),
      if (i.voucher > 0 || i.showTotal) const Divider(height: 18, color: MgColors.line),
      if (i.voucher > 0)
        Row(children: [
          Expanded(child: Text(tr.trArgs('groVoucherLine', {'code': ''}).trim(), style: small)),
          Text('−${gearMoney(i.voucher)}', style: MgType.tab(small.copyWith(fontWeight: FontWeight.w800))),
        ]),
      if (i.showTotal)
        Row(children: [
          Expanded(
            child: Text(tr.tr(i.voucher > 0 && !i.paid ? 'groToPay' : 'groTotal'),
                style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
          ),
          Text(gearMoney(i.toPay), style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
        ]),
    ]);
  }
}

/// Karta „Nahraj doklad totožnosti“ (OP z obou stran nebo pas, 18+).
class GearDocsCardV2 extends StatelessWidget {
  final bool self;
  final VoidCallback onUpload;
  const GearDocsCardV2({super.key, required this.self, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      key: const ValueKey('gear-done-docs'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(MgSpace.card),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.warnBorder),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgIcon(MgIcons.idCard, size: 20, color: MgColors.warn),
          const SizedBox(width: 8),
          Expanded(child: Text(tr.tr('groDocsTitle'), style: MgType.title.copyWith(color: MgColors.ink))),
        ]),
        const SizedBox(height: 6),
        Text('${tr.tr('groDocsLead')} ${tr.tr(self ? 'groDocsSelf' : 'groDocsStaffed')}',
            style: MgType.small.copyWith(color: MgColors.body2)),
        const SizedBox(height: 12),
        MgBtnInk(key: const ValueKey('gear-done-docs-upload'), label: tr.tr('groDocsUpload'), icon: MgIcons.camera, onTap: onUpload),
        const SizedBox(height: 8),
        Text(tr.tr('groDocsLater'), style: MgType.meta.copyWith(color: MgColors.meta)),
      ]),
    );
  }
}
