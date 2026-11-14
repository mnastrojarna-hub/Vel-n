// auth_sos_misc (ASM-09…25, 29, 30): SOS start order + seams, nonstop dock
// = the existing callMotoGo, type sheet swipe-down, report sheet stays
// non-dismissible and says what is missing, fault choice reveals the
// actions, in-flight label, fail sheet ids, replacement "show more",
// scanner choice / result / help.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart' show callMotoGo;
import 'package:motogo_app/features/documents/v2/scan_choice_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_states_v2.dart';
import 'package:motogo_app/features/sos/sos_feedback.dart';
import 'package:motogo_app/features/sos/sos_report_screen.dart';
import 'package:motogo_app/features/sos/sos_report_sheet.dart';
import 'package:motogo_app/features/sos/v2/sos_header_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_immobile_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_replacement_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_sheets_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_feedback_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_start_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_auth_sos_misc.dart' show asmBase, asmIncident, asmMotos;
import '../support/asm_harness.dart';
import '../support/v2_harness.dart';

void _n() {}

void main() {
  setUpAll(loadMontserrat);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SOS start: flag ON = v2 view; order banner → AI → 112/155/158 → rows; dial = tile number', (t) async {
    await pumpAsmRouted(t, const SosReportScreen(), overrides: asmBase(active: true));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(SosStartViewV2), findsOneWidget);
    final dialed = <String>[];
    await pumpV2(
        t,
        SosStartViewV2(
            active: AsyncValue.data(asmIncident()),
            onBack: _n,
            onAccident: _n,
            onBreakdown: _n,
            onShareLocation: _n,
            onAi: _n,
            onOpenIncident: _n,
            onDial: dialed.add),
        scaffold: false,
        overrides: asmBase());
    await t.pump(const Duration(milliseconds: 100));
    double y(Finder f) => t.getTopLeft(f.first).dy;
    // lookonly-fix: the OLD order — banner → AI agent → 112 / 155 / 158 → rows.
    expect(y(find.text('Aktivní SOS incident')), lessThan(y(find.text('AI Servisní agent'))));
    expect(y(find.text('AI Servisní agent')), lessThan(y(find.text('112'))));
    expect(y(find.text('112')), lessThan(y(find.text('Nehoda / Krádež'))));
    await t.tap(find.text('155'));
    expect(dialed, ['155']);
  });

  testWidgets('nonstop dock: whole pill = existing callMotoGo, never covered (no FAB)', (t) async {
    await pumpV2(t, const SosDockV2(), overrides: asmBase());
    await t.pump();
    final press = t.widget<MgPress>(find.ancestor(of: find.text('+420 774 256 271'), matching: find.byType(MgPress)).first);
    expect(press.onTap, callMotoGo);
    expect(find.bySemanticsLabel(RegExp('Nonstop linka MotoGo24, \\+420 774 256 271')), findsOneWidget);
  });

  testWidgets('type sheet: row closes the sheet and runs its action once; swipe-down closes', (t) async {
    var hits = 0;
    await pumpV2(
        t,
        Builder(
            builder: (c) => TextButton(
                onPressed: () => showSosTypeSheetV2(c, title: 'Typ nehody', choices: [
                      (icon: MgIcons.target, tint: SosTint.ok, label: 'Lehká nehoda', onTap: () => hits++),
                    ]),
                child: const Text('open'))),
        overrides: asmBase());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lehká nehoda'));
    await t.pumpAndSettle();
    expect(hits, 1);
    expect(find.text('Typ nehody'), findsNothing);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.fling(find.text('Typ nehody'), const Offset(0, 400), 1500);
    await t.pumpAndSettle();
    expect(find.text('Typ nehody'), findsNothing);
    expect(hits, 1);
  });

  testWidgets('report sheet v2: drag does not dismiss; says what is missing until it can be sent', (t) async {
    await pumpV2(
        t,
        Builder(builder: (c) => TextButton(onPressed: () => collectSosReport(c, 'Lehká nehoda'), child: const Text('open'))),
        overrides: asmBase());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(SosReportSheetV2), findsOneWidget);
    expect(find.text('Chybí: Popis problému · Fotodokumentace'), findsOneWidget);
    expect(t.widget<MgBtnSos>(find.byType(MgBtnSos)).onTap, isNull);
    await t.fling(find.text('Lehká nehoda').first, const Offset(0, 500), 2000);
    await t.pumpAndSettle();
    expect(find.byType(SosReportSheetV2), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Prasklé zrcátko');
    await t.pump();
    expect(find.text('Chybí: Fotodokumentace'), findsOneWidget);
  });

  testWidgets('immobile: hint until a fault is chosen, then the actions; pressed action shows "Odesílám…"', (t) async {
    var repl = 0;
    Widget view(bool? fault, bool submitting) => SosImmobileViewV2(
        fault: fault,
        submitting: submitting,
        onFault: (_) {},
        onBack: _n,
        onReplacement: () => repl++,
        onTow: _n,
        onShare: _n);
    await pumpV2(t, view(null, false), scaffold: false, overrides: asmBase(), reducedMotion: true);
    await t.pump();
    expect(find.textContaining('Nejdřív vyber zavinění'), findsOneWidget);
    expect(find.text('NÁHRADNÍ MOTORKA – ZDARMA'), findsNothing);
    await pumpV2(t, view(false, false), scaffold: false, overrides: asmBase(), reducedMotion: true);
    await t.pump();
    expect(find.textContaining('Nejdřív vyber zavinění'), findsNothing);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await t.pump();
    await t.tap(find.text('NÁHRADNÍ MOTORKA – ZDARMA'));
    await t.pump();
    expect(repl, 1);
    await pumpV2(t, view(false, true), scaffold: false, overrides: asmBase(), reducedMotion: true);
    await t.pump();
    expect(find.text('Odesílám na centrálu…'), findsOneWidget);
  });

  testWidgets('fail sheet: same ids as the old dialog; SosCallButton = red v2 button', (t) async {
    String? got = 'x';
    await pumpV2(
        t,
        Builder(
            builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () async => got = await showSosFailSheetV2(c, title: 'Hlášení se neodeslalo', body: 'Server neodpovídá.'),
                      child: const Text('open')),
                  const SosCallButton(),
                ])),
        overrides: asmBase());
    expect(find.byType(MgBtnSos), findsOneWidget);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Zkusit znovu'));
    await t.pumpAndSettle();
    expect(got, 'retry');
  });

  testWidgets('replacement: ALL free bikes listed at once (old list, owner "nic neomezit")', (t) async {
    await pumpV2(
        t,
        SosReplacementViewV2(
            motos: AsyncValue.data(asmMotos(9)),
            selectedId: null,
            onSelect: (_) {},
            loading: false,
            onConfirm: _n,
            onBack: _n,
            hereAddress: const SizedBox(),
            addressField: const SizedBox(),
            error: (_) => const SizedBox(),
            callButton: const SizedBox()),
        scaffold: false,
        overrides: asmBase(),
        reducedMotion: true);
    await t.pump();
    expect(find.text('Zdarma', skipOffstage: false), findsNWidgets(9));
    expect(find.textContaining('Zobrazit další', skipOffstage: false), findsNothing);
  });

  testWidgets('scanner: choice rows run their action; loading = skeleton; result tiles + actions', (t) async {
    final hits = <String>[];
    await pumpV2(
        t,
        ScanChoiceV2(onBack: _n, choices: [
          (icon: MgIcons.idCard, label: 'Občanský průkaz', steps: 4, sub: null, onTap: () => hits.add('op')),
          (icon: MgIcons.bike, label: 'Pouze řidičský průkaz', steps: 2, sub: null, onTap: () => hits.add('dl')),
        ]),
        scaffold: false);
    await t.pump();
    expect(find.text('2 × skenovat'), findsOneWidget);
    await t.tap(find.text('Pouze řidičský průkaz'));
    expect(hits, ['dl']);
    await pumpV2(t, ScanChoiceV2(onBack: _n, choices: const [], loading: true), scaffold: false);
    await t.pump();
    expect(find.byType(MgSkeletonRow), findsNWidgets(3));
    final acts = <String>[];
    await pumpV2(
        t,
        ScanResultV2(
            ok: false,
            side: 'OP',
            message: 'Rozmazané',
            guidance: '',
            remaining: 2,
            onContinue: () => acts.add('c'),
            onRetry: () => acts.add('r'),
            onSkip: () => acts.add('s')));
    await t.pump();
    expect(find.text('Zbývá pokusů: 2'), findsOneWidget);
    await t.tap(find.text('Zkusit znovu'));
    await t.tap(find.text('Přeskočit'));
    expect(acts, ['r', 's']);
    final (f, n) = scanFieldsOf('Jméno: Jan Novák\n⚠️ Číslo ŘP nesedí\nČ. dokladu: 123');
    expect(f, [('Jméno', 'Jan Novák'), ('Č. dokladu', '123')]);
    expect(n, ['Číslo ŘP nesedí']);
  });

  testWidgets('location OK toast (v2) names the time, no emoji', (t) async {
    await pumpV2(t, Builder(builder: (c) => TextButton(onPressed: () => showSosLocSentV2(c), child: const Text('go'))));
    await t.tap(find.text('go'));
    await t.pump();
    expect(find.textContaining('Poloha odeslána · '), findsOneWidget);
  });
}
