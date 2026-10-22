// verify:render cases — Reservations v2 (reservations_cases.dart): list
// (each filter, empty, stale, loading, error, unpaid, SOS), detail (every
// status + expanders opened + pickup-procedure sheet), edit (chooser,
// every intent, confirm, load states) and the cancel dialogs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/reservations/v2/res_cancel_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_procedure_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_reservations.dart';
import 'render_harness.dart';

Future<void> _tapFirst(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _openExpanders(WidgetTester t) async {
  final lang = Localizations.localeOf(t.element(find.byType(Scaffold).first)).languageCode;
  for (final k in ['paymentDetailsTab', 'v2ResHistory']) {
    await _tapFirst(t, find.text(translations[lang]?[k] ?? k));
  }
}

Future<void> _openProcedure(WidgetTester t) =>
    _tapFirst(t, find.descendant(of: find.byType(ResProcedureV2), matching: find.byType(MgPress)));

List<RenderCase> resRenderCases() {
  final detail = detailCases();
  return [
    for (final e in listCases().entries)
      RenderCase('reservations', 'list', e.key, () => const ReservationsScreenV2(), e.value, loading: e.key == 'loading'),
    for (final e in detail.entries) RenderCase('reservations', 'detail', e.key, e.value.$1, e.value.$2),
    RenderCase('reservations', 'detail', 'done-5-expanded', detail['done-5']!.$1, detail['done-5']!.$2, after: _openExpanders),
    RenderCase('reservations', 'detail', 'ready-procedure-sheet', detail['ready']!.$1, detail['ready']!.$2, after: _openProcedure),
    for (final e in editCases().entries)
      RenderCase('reservations', 'edit', e.key, e.value.$1, e.value.$2, loading: e.key == 'loading'),
    for (final busy in [false, true])
      RenderCase(
          'reservations',
          'dialog',
          busy ? 'cancel-busy' : 'cancel-confirm',
          () => Builder(
              builder: (c) => ResCancelConfirmV2(
                  motoName: busy ? 'BMW R 1200 GS Adventure' : 'Husqvarna 701 SM',
                  dateRange: '16. 10. – 18. 10. 2026',
                  pct: busy ? 100 : 50,
                  refundLine: t(c).tr('currentlyRefund').replaceAll('{pct}', busy ? '100' : '50').replaceAll('{amount}', '6014'),
                  loading: busy,
                  onReason: (_) {},
                  onKeep: () {},
                  onCancel: () {})),
          () => resOverrides(),
          loading: busy),
    RenderCase(
        'reservations',
        'dialog',
        'cancel-done',
        () => Builder(
            builder: (c) => ResCancelResultV2(
                ok: true,
                title: t(c).tr('psCancelDoneTitle'),
                body: t(c).tr('psCancelRefund').replaceAll('{amount}', '6 014 Kč').replaceAll('{pct}', '50'),
                closeLabel: t(c).tr('close'),
                onClose: () {})),
        () => resOverrides()),
    for (final k in ['psCancelNet', 'fxCancelUncertain', 'pdCancelForbidden'])
      RenderCase(
          'reservations',
          'dialog',
          'cancel-fail-$k',
          () => Builder(
              builder: (c) => ResCancelResultV2(
                  ok: false,
                  title: t(c).tr(k == 'fxCancelUncertain' ? 'psUncertainTitle' : 'psCancelFailTitle'),
                  body: t(c).tr(k),
                  closeLabel: k == 'pdCancelForbidden' ? t(c).tr('close') : t(c).back,
                  onClose: () {},
                  onRetry: k == 'pdCancelForbidden' ? null : () {})),
          () => resOverrides()),
  ];
}
