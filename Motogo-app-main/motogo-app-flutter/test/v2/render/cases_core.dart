// verify:render cases — shared state templates (T1 screen in every tone,
// T2 sheet, T3 banners), v2 looks of the existing state widgets / dialogs
// / snackbars, the T6 confirm dialogs used by the recorder, the toast.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/states/mg_state_sheet.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/core/v2/widgets/mg_toast.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/core/widgets/state_views.dart';

import 'render_harness.dart';

Widget _t1(MgTone tone) => Builder(builder: (context) {
      final tr = t(context);
      return MgStateScreen(
        tone: tone,
        title: tr.tr('v2CalError'),
        why: tr.tr('v2CalBusyInRange').replaceAll('{date}', '24. 10.'),
        summary: tone == MgTone.ok || tone == MgTone.pending ? Text(tr.tr('v2CalNote')) : null,
        stepsTitle: tr.tr(tone == MgTone.ok ? 'v2StNext' : 'v2StFix'),
        steps: [tr.tr('v2CalPickEnd'), tr.tr('v2CalNote')],
        tech: 'code: card_declined · ref pi_123 · 2026-10-16 12:00',
        primary: MgStateAction(tr.tr('v2StWrite'), () {}),
        secondary: MgStateAction(tr.tr('v2ShowMore'), () {}),
        onClose: () {},
      );
    });

/// A button that runs [open] with a context below the app.
Widget launcher(void Function(BuildContext) open) =>
    Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('OPEN'))));

Future<void> tapOpen(WidgetTester t) async {
  await t.tap(find.text('OPEN'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

List<RenderCase> coreCases() => [
      for (final tone in MgTone.values)
        RenderCase('core', 'state_t1', tone.name, () => _t1(tone), () => const [], scaffold: false),
      RenderCase(
        'core',
        'state_t2',
        'sheet_err',
        () => launcher((context) => showMgStateSheet<void>(
              context,
              tone: MgTone.err,
              title: t(context).tr('v2CalError'),
              why: t(context).tr('v2CalNote'),
              chips: [MgStateChip(t(context).trArgs('v2StAttempt', {'n': 2, 'max': 3})), MgStateChip(t(context).tr('v2StNoCharge'), MgTone.ok)],
              steps: [t(context).tr('v2CalPickEnd')],
              tech: 'stripe: card_declined',
              primary: MgStateAction(t(context).tr('retry'), () {}),
              secondary: MgStateAction(t(context).tr('close'), null),
            )),
        () => const [],
        after: tapOpen,
      ),
      RenderCase(
        'core',
        'state_t3',
        'banners',
        () => Builder(
            builder: (context) => ListView(children: [
                  for (final dark in [false, true])
                    for (final tone in MgTone.values)
                      Container(
                        color: dark ? const Color(0xFF0E2A1C) : null,
                        padding: const EdgeInsets.all(8),
                        child: MgStateBanner(
                          tone: tone,
                          dark: dark,
                          title: t(context).tr('v2CalError'),
                          text: t(context).tr('v2CalNote'),
                          actions: [MgBtnText(label: t(context).tr('retry'), onTap: () {}, dark: dark)],
                        ),
                      ),
                ])),
        () => const [],
      ),
      RenderCase(
        'core',
        'legacy_states',
        'error_stale_back',
        () => Column(children: [
          Expanded(child: MgErrorView(error: Exception('SocketException: Failed host lookup'), onRetry: () {}, onBack: () {})),
          MgStaleNote(onRetry: () {}),
          MgBackArrow(onTap: () {}),
        ]),
        () => const [],
      ),
      RenderCase('core', 'legacy_states', 'scaffold_loading',
          () => MgStateScaffold(title: 'Zprávy', onBack: () {}, child: const MgLoadingView()), () => const [],
          scaffold: false, loading: true),
      RenderCase('core', 'legacy_states', 'loading_slow',
          () => MgStateScaffold(title: 'Zprávy', onBack: () {}, child: const MgLoadingView()), () => const [],
          scaffold: false, loading: true, after: (t) => t.pump(const Duration(seconds: 16))),
      RenderCase('core', 'dialog', 'discard', () => launcher((c) => confirmDiscard(c)), () => const [], after: tapOpen),
      RenderCase(
          'core',
          'dialog',
          'error_1action',
          () => launcher((c) => showErrorDialog(c,
              title: t(c).tr('v2CalError'), body: FriendlyError.of(Exception('timeout')).compose(t(c), t(c).tr('v2CalError')),
              actions: [('retry', t(c).tr('eoRetry'))])),
          () => const [],
          after: tapOpen),
      RenderCase(
          'core',
          'dialog',
          'error_2actions',
          () => launcher((c) => showErrorDialog(c,
              title: t(c).tr('v2CalError'), body: t(c).tr('v2CalNote'),
              actions: [('retry', t(c).tr('eoRetry')), ('call', t(c).tr('eoCall'))])),
          () => const [],
          after: tapOpen),
      RenderCase(
          'core',
          'dialog',
          'confirm_stop_ride',
          () => launcher((c) => showMgConfirm(c,
              title: t(c).tr('v2RtRecStopQ'), body: t(c).tr('v2RtRecStopBody'),
              safeLabel: t(c).tr('v2RtRecContinue'), actionLabel: t(c).tr('v2RtRecStopSave'))),
          () => const [],
          after: tapOpen),
      RenderCase(
          'core',
          'dialog',
          'confirm_home_stop',
          () => launcher((c) => showMgConfirm(c,
              title: t(c).tr('v2HomeRecStopQ'), body: t(c).tr('v2HomeRecStopBody'),
              safeLabel: t(c).tr('v2HomeRecContinue'), actionLabel: t(c).tr('v2HomeRecStopSave'), destructive: true)),
          () => const [],
          after: tapOpen),
      RenderCase('core', 'snack', 'error_snack',
          () => launcher((c) => showErrorSnack(c, t(c).tr('v2CalError'), Exception('SocketException'), onRetry: () {})),
          () => const [], after: tapOpen),
      RenderCase('core', 'snack', 'toast',
          () => launcher((c) => showMgToast(c, t(c).tr('v2CalNote'), actionLabel: t(c).tr('eoRetry'), onAction: () {})),
          () => const [], after: tapOpen),
    ];
