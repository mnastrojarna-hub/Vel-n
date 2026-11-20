import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../booking/booking_ui_helpers.dart' show bookingPriceRow;
import '../gear_done_screen.dart';
import '../gear_order_ui.dart';

/// Starý vzhled děkovací stránky výpůjčky výbavy (stejný obsah jako v2).
class GearDoneView extends StatelessWidget {
  final GearDoneStage stage;
  final GearDoneInfo? info;
  final GearDoneActions actions;
  const GearDoneView({super.key, required this.stage, required this.info, required this.actions});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    final i = info;
    final paid = stage == GearDoneStage.paid;
    final (icon, title) = switch (stage) {
      GearDoneStage.wait => (Icons.hourglass_top, 'groOkWait'),
      GearDoneStage.paid => (Icons.check_circle, 'groOkTitle'),
      GearDoneStage.pay => (Icons.payment, 'groResTitle'),
      GearDoneStage.pending => (Icons.hourglass_top, 'groOkPending'),
      GearDoneStage.cancelled => (Icons.cancel_outlined, 'groResCancelled'),
      GearDoneStage.completed => (Icons.flag_outlined, 'groResCompleted'),
      GearDoneStage.notFound => (Icons.info_outline, 'groResNf'),
    };
    Widget btn(String label, VoidCallback? onTap, {bool primary = true, Key? key}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 48,
            child: primary
                ? ElevatedButton(
                    key: key,
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.green,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    ),
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  )
                : OutlinedButton(
                    key: key,
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MotoGoColors.black,
                      side: const BorderSide(color: MotoGoColors.g300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    ),
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        );
    return Material(
      key: ValueKey('gear-done-${stage.name}'),
      color: MotoGoColors.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(icon, size: 56, color: paid ? MotoGoColors.greenDark : MotoGoColors.g400),
            const SizedBox(height: 10),
            Text(tr.tr(title),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            if (stage == GearDoneStage.wait)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
              ),
            if (paid || stage == GearDoneStage.pay) ...[
              const SizedBox(height: 6),
              Text(tr.tr(paid ? 'groOkLead' : 'groResLead'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: MotoGoColors.g600)),
            ],
            if (i != null && stage != GearDoneStage.wait) ...[
              const SizedBox(height: 14),
              _summary(tr, lang, i),
            ],
            if (paid && i!.docsNeeded) _docs(tr, i, btn),
            if (paid)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${tr.tr(i!.self ? 'groOkNextSelf' : 'groOkNextStaffed')} ${tr.tr(i.self ? 'groOkReturnSelf' : 'groOkReturn')}',
                  key: const ValueKey('gear-done-next'),
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g600),
                ),
              ),
            if (stage == GearDoneStage.pay)
              btn(tr.trArgs('groResPay', {'amount': gearMoney(i!.toPay)}), actions.pay),
            if (stage != GearDoneStage.wait) ...[
              if (i != null) btn(tr.tr('groShowBooking'), actions.showBooking, primary: stage != GearDoneStage.pay),
              btn(tr.tr('groOkHome'), actions.home, primary: false),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _summary(AppTranslations tr, String lang, GearDoneInfo i) {
    final period = i.start == null
        ? null
        : '${gearPeriod(tr, i.start!, i.end ?? i.start!)}'
            '${i.days > 0 ? ' (${i.days} ${tr.daysWord(i.days)})' : ''}'
            '${i.pickupTime != null ? ' · ${i.pickupTime}' : ''}';
    const t12 = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black);
    return Container(
      key: const ValueKey('gear-done-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (i.number.isNotEmpty) bookingPriceRow(tr.tr('groOkOrder'), i.number),
        if (i.branchLine.isNotEmpty) Text(i.branchLine, style: t12),
        if (period != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(period, style: t12)),
        const SizedBox(height: 6),
        for (final (label, sizes) in i.lines((x) => gearLc(lang, x)))
          Text([label, sizes].where((e) => e.isNotEmpty).join('  '),
              style: const TextStyle(fontSize: 12, color: MotoGoColors.g600)),
        if (i.voucher > 0 || i.showTotal) const Divider(color: MotoGoColors.g200),
        if (i.voucher > 0)
          bookingPriceRow(tr.trArgs('groVoucherLine', {'code': ''}).trim(), '−${gearMoney(i.voucher)}',
              color: MotoGoColors.greenDarker),
        if (i.showTotal)
          bookingPriceRow(tr.tr(i.voucher > 0 && !i.paid ? 'groToPay' : 'groTotal'), gearMoney(i.toPay),
              color: MotoGoColors.black),
      ]),
    );
  }

  Widget _docs(AppTranslations tr, GearDoneInfo i, Widget Function(String, VoidCallback?, {bool primary, Key? key}) btn) =>
      Container(
        key: const ValueKey('gear-done-docs'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MotoGoColors.amberBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MotoGoColors.amberBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.tr('groDocsTitle'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 4),
          Text('${tr.tr('groDocsLead')} ${tr.tr(i.self ? 'groDocsSelf' : 'groDocsStaffed')}',
              style: const TextStyle(fontSize: 12, color: MotoGoColors.g600)),
          btn(tr.tr('groDocsUpload'), actions.uploadDocs, key: const ValueKey('gear-done-docs-upload')),
          const SizedBox(height: 6),
          Text(tr.tr('groDocsLater'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g500)),
        ]),
      );
}
