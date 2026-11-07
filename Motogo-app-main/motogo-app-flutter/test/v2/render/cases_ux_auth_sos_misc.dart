// verify:render cases — auth_sos_misc package (v2 on every page, 2026-11-07):
// login (+ inline errors, signed-out notice), registration 1–3 (+ errors),
// reset 1–3, welcome, SOS start / sub-screens / sheets / done / detail /
// replacement, document scanner (choice, camera chrome, results, help,
// camera error, verifying).
// MG_VERIFY_RENDER=1 flutter test test/v2/render/render_ux_auth_sos_misc_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/features/auth/login_screen.dart';
import 'package:motogo_app/features/auth/v2/login_view_v2.dart';
import 'package:motogo_app/features/auth/v2/register_view_v2.dart';
import 'package:motogo_app/features/auth/v2/reset_view_v2.dart';
import 'package:motogo_app/features/auth/v2/welcome_overlay_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/documents/v2/scan_camera_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_choice_v2.dart';
import 'package:motogo_app/features/documents/v2/scan_states_v2.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart' show reservationsProvider;
import 'package:motogo_app/features/sos/sos_provider.dart';
import 'package:motogo_app/features/sos/v2/sos_done_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_feedback_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_header_v2.dart' show SosTint;
import 'package:motogo_app/features/sos/v2/sos_immobile_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_incident_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_replacement_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_service_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_sheets_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_start_view_v2.dart';
import 'package:motogo_app/features/sos/v2/sos_theft_view_v2.dart';

import '../support/fakes_home.dart' show kLoyalty3, res;
import 'render_harness.dart';

void _n() {}

List<Override> asmBase({bool active = false}) => [
      loyaltyStatusProvider.overrideWith((ref) async => kLoyalty3),
      reservationsProvider.overrideWith((ref) => Stream.value([res('r1', status: 'active', from: -1, to: 1)])),
      activeSosProvider.overrideWith((ref) => Stream.value(active ? asmIncident() : null)),
    ];

SosIncident asmIncident({List<String> photos = const []}) => SosIncident(
      id: 'aaaa-bbbb-a41c07e2',
      type: 'accident_major',
      status: 'reported',
      customerFault: false,
      photos: photos,
      createdAt: DateTime(2026, 10, 17, 9, 12),
    );

TextEditingController _c([String t = '']) => TextEditingController(text: t);

RegisterV2Model asmRegModel(int step, {Map<String, String> errors = const {}}) {
  final keys = <String, GlobalKey>{};
  return RegisterV2Model(
    step: step,
    loading: false,
    forward: true,
    ctrl: {
      for (final k in ['fname', 'lname', 'email', 'phone', 'pass', 'pass2', 'dob', 'street', 'zip', 'city', 'country', 'idNum', 'licNum', 'licExp'])
        k: _c(k == 'email' ? 'jan.novak@zakaznik.cz' : (k == 'phone' ? '+420 ' : '')),
    },
    licGroup: 'A2',
    onLic: (_) {},
    consentVop: false,
    consentGdpr: true,
    onVop: (_) {},
    onGdpr: (_) {},
    errors: errors,
    keyFor: (f) => keys.putIfAbsent(f, () => GlobalKey()),
    onEdited: (_) {},
    onBack: _n,
    onNext: _n,
  );
}

ResetV2Model asmResetModel(int step, {Map<String, String> errors = const {}}) => ResetV2Model(
      step: step,
      loading: false,
      sentTo: 'jan.novak@zakaznik.cz',
      emailCtrl: _c('jan.novak@zakaznik.cz'),
      codeCtrl: _c(step == 2 ? '1234' : ''),
      pass1Ctrl: _c(step == 3 ? 'tajneheslo' : ''),
      pass2Ctrl: _c(step == 3 ? 'tajneheslo' : ''),
      errors: errors,
      onEdited: (_) {},
      onBack: _n,
      onSend: _n,
      onVerify: _n,
      onSet: _n,
    );

LoginViewV2 _login({String? e, String? p, bool out = false}) => LoginViewV2(
      emailCtrl: _c(e == null ? 'jan.novak@zakaznik.cz' : ''),
      passCtrl: _c(),
      loading: false,
      bioVisible: true,
      emailError: e,
      passError: p,
      signedOutNotice: out,
      onLogin: _n,
      onBio: _n,
      onForgot: _n,
      onRegister: _n,
      onEdited: _n,
      onWeb: _n,
    );

List<Motorcycle> asmMotos(int n) => [
      for (var i = 0; i < n; i++)
        Motorcycle(id: 'm$i', model: ['Ducati Multistrada 1260 S', 'Husqvarna 701 SM', 'BMW R 1200 GS Adventure'][i % 3],
            category: ['cestovni', 'supermoto', 'cestovni'][i % 3]),
    ];

Widget _sheetHost(Widget sheet) => Align(alignment: Alignment.bottomCenter, child: sheet);

Future<void> _tapText(WidgetTester w, String text) async {
  await w.tap(find.text(text).first);
  await w.pump();
  await w.pump(const Duration(milliseconds: 400));
}

List<RenderCase> authSosMiscUxCases() => [
      RenderCase('asm', 'login', 'screen', () => const LoginScreen(initialEmail: 'jan.novak@zakaznik.cz'), asmBase, scaffold: false),
      RenderCase('asm', 'login', 'errors', () => _login(e: 'Vyplň e-mail', p: 'Vyplň heslo'), asmBase, scaffold: false),
      RenderCase('asm', 'login', 'signed_out', () => _login(out: true), asmBase, scaffold: false),
      for (final s in [1, 2, 3])
        RenderCase('asm', 'register', 's$s', () => RegisterViewV2(m: asmRegModel(s)), asmBase, scaffold: false),
      RenderCase('asm', 'register', 's1_error',
          () => RegisterViewV2(m: asmRegModel(1, errors: {'fname': 'Napiš platné jméno (aspoň 2 písmena, bez číslic)'})), asmBase,
          scaffold: false),
      RenderCase('asm', 'register', 's3_consent',
          () => RegisterViewV2(m: asmRegModel(3, errors: {'consent': 'Pro dokončení registrace musíš souhlasit s VOP.'})), asmBase,
          scaffold: false),
      for (final s in [1, 2, 3]) RenderCase('asm', 'reset', 's$s', () => ResetViewV2(m: asmResetModel(s)), asmBase, scaffold: false),
      RenderCase('asm', 'reset', 's2_error', () => ResetViewV2(m: asmResetModel(2, errors: {'code': 'Zadej celý 8místný kód'})),
          asmBase, scaffold: false),
      RenderCase('asm', 'welcome', 'overlay', () => const WelcomeOverlayV2(), asmBase, scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'start',
          () => SosStartViewV2(
              active: const AsyncValue.data(null),
              onBack: _n,
              onAccident: _n,
              onBreakdown: _n,
              onShareLocation: _n,
              onAi: _n,
              onOpenIncident: _n,
              onDial: (_) {}),
          asmBase,
          scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'start_active',
          () => SosStartViewV2(
              active: AsyncValue.data(asmIncident()),
              onBack: _n,
              onAccident: _n,
              onBreakdown: _n,
              onShareLocation: _n,
              onAi: _n,
              onOpenIncident: _n,
              onDial: (_) {}),
          asmBase,
          scaffold: false),
      RenderCase('asm', 'sos', 'type_sheet', () => Builder(builder: (c) {
            return Center(
              child: TextButton(
                onPressed: () => showSosTypeSheetV2(c, title: 'Typ nehody', choices: [
                  (icon: MgIcons.target, tint: SosTint.ok, label: 'Lehká nehoda — pokračuji v jízdě', onTap: _n),
                  (icon: MgIcons.alert, tint: SosTint.red, label: 'Závažná nehoda — motorka nepojízdná', onTap: _n),
                  (icon: MgIcons.lock, tint: SosTint.red, label: 'Krádež motorky', onTap: _n),
                ]),
                child: const Text('open'),
              ),
            );
          }), asmBase, after: (w) => _tapText(w, 'open')),
      RenderCase(
          'asm',
          'sos',
          'report_sheet',
          () => _sheetHost(SosReportSheetV2(
                typeLabel: 'Lehká nehoda',
                accident: true,
                descCtrl: _c(),
                photoPaths: const [],
                cameraProblem: null,
                needsSettings: false,
                missingDesc: true,
                missingPhoto: true,
                submitLabel: 'Ano, nahlásit',
                onSubmit: null,
                onCapture: _n,
                onCancel: _n,
                onOpenSettings: _n,
                onDescChanged: (_) {},
              )),
          asmBase),
      RenderCase('asm', 'sos', 'fail_sheet', () => Builder(builder: (c) {
            return Center(
              child: TextButton(
                onPressed: () => showSosFailSheetV2(c,
                    title: 'Hlášení se neodeslalo',
                    body: 'Server teď neodpovídá. Zavolej nám hned na nonstop linku +420 774 256 271 (hovor funguje i bez dat). Při zranění volej 112.'),
                child: const Text('open'),
              ),
            );
          }), asmBase, after: (w) => _tapText(w, 'open')),
      for (final f in [null, false])
        RenderCase(
            'asm',
            'sos',
            'immobile_${f == null ? 'idle' : 'chosen'}',
            () => SosImmobileViewV2(
                fault: f, submitting: false, onFault: (_) {}, onBack: _n, onReplacement: _n, onTow: _n, onShare: _n),
            asmBase,
            scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'breakdown',
          () => SosBreakdownViewV2(descCtrl: _c(), submitting: false, onBack: _n, onReplacement: _n, onTow: _n, onShare: _n),
          asmBase,
          scaffold: false),
      for (final r in [false, true])
        RenderCase(
            'asm',
            'sos',
            'theft_${r ? 'reported' : 'idle'}',
            () => SosTheftViewV2(
                reported: r,
                submitting: false,
                secured: r ? true : null,
                onSecured: (_) {},
                onBack: _n,
                onCallPolice: _n,
                onReport: _n,
                onReplacement: _n,
                onNoReplacement: _n),
            asmBase,
            scaffold: false),
      for (final u in [false, true])
        RenderCase(
            'asm',
            'sos',
            'service_${u ? 'uploaded' : 'idle'}',
            () => SosServiceViewV2(uploading: false, uploaded: u, onBack: _n, onFindService: _n, onUpload: _n, onDone: _n),
            asmBase,
            scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'replacement',
          () => SosReplacementViewV2(
              motos: AsyncValue.data(asmMotos(9)),
              selectedId: 'm1',
              onSelect: (_) {},
              loading: false,
              onConfirm: _n,
              onBack: _n,
              hereAddress: const SizedBox(height: 44),
              addressField: const TextField(),
              error: (_) => const SizedBox(),
              callButton: const SizedBox()),
          asmBase,
          scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'done',
          () => SosDoneViewV2(
              title: 'Odtah objednán — zdarma',
              subtitle: 'Pronájem ukončen bez poplatku',
              nextSteps: 'Vracíme plnou částku za pronájem. MotoGo24 zařídí odtah motorky.',
              icon: MgIcons.truck,
              refLabel: '#A41C07E2',
              onBack: _n,
              onReservations: _n,
              onMessages: _n,
              onHome: _n),
          asmBase,
          scaffold: false),
      RenderCase(
          'asm',
          'sos',
          'incident',
          () => SosIncidentViewV2(
              inc: asmIncident(),
              status: 'Nahlášeno',
              rows: const [('Typ', 'Závažná nehoda'), ('Nahlášeno', '17. 10. 2026 9:12'), ('Zavinění', 'Porucha / nezaviněno')],
              timeline: AsyncValue.data([
                SosTimelineEntry(id: 't1', action: 'Incident nahlášen zákazníkem (Závažná nehoda)', createdAt: DateTime(2026, 10, 17, 9, 12)),
              ]),
              timelineError: (_) => const SizedBox(),
              onBack: _n,
              onReplacement: _n,
              onContinue: null,
              onMessages: _n),
          asmBase,
          scaffold: false),
      RenderCase(
          'asm',
          'scan',
          'choice',
          () => ScanChoiceV2(onBack: _n, choices: [
                (icon: MgIcons.idCard, label: 'Občanský průkaz', steps: 4, onTap: _n),
                (icon: MgIcons.doc, label: 'Cestovní pas', steps: 4, onTap: _n),
                (icon: MgIcons.bike, label: 'Pouze řidičský průkaz', steps: 2, onTap: _n),
              ]),
          asmBase,
          scaffold: false),
      RenderCase('asm', 'scan', 'loading', () => ScanChoiceV2(onBack: _n, choices: const [], loading: true), asmBase,
          scaffold: false, loading: true),
      RenderCase('asm', 'scan', 'verifying', () => ScanVerifyingV2(onBack: _n), asmBase, scaffold: false, loading: true),
      RenderCase(
          'asm',
          'scan',
          'camera',
          () => ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  Positioned(top: 55, left: 16, right: 16, child: ScanTopV2(onBack: _n, step: 'Občanský průkaz · přední strana', index: 0, total: 4)),
                  Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: ScanControlsV2(guide: 'Umísti občanský průkaz do rámečku', capturing: false, onCapture: _n, onSkip: _n)),
                ]),
              ),
          asmBase,
          scaffold: true),
      for (final ok in [true, false])
        RenderCase(
            'asm',
            'scan',
            'result_${ok ? 'ok' : 'error'}',
            () => ColoredBox(
                  color: Colors.black,
                  child: ScanResultV2(
                      ok: ok,
                      side: 'Občanský průkaz – přední strana',
                      message: ok ? 'Jméno: Jan Novák\nDatum narození: 1. 2. 1990\nČ. dokladu: 123456789\nPlatnost do: 1. 2. 2031' : 'Fotka je rozmazaná.',
                      guidance: 'Polož doklad na tmavý podklad\nVyhni se odleskům\nDrž telefon rovně',
                      remaining: 2,
                      onContinue: _n,
                      onRetry: _n,
                      onSkip: _n),
                ),
            asmBase,
            scaffold: true),
      RenderCase(
          'asm',
          'scan',
          'help',
          () => ColoredBox(
                color: Colors.black,
                child: ScanHelpV2(
                    attempts: 3,
                    side: 'Řidičský průkaz – zadní strana',
                    guidance: '',
                    phone: '+420 774 256 271',
                    onCall: _n,
                    onWrite: _n,
                    onTryAgain: _n,
                    onClose: _n),
              ),
          asmBase,
          scaffold: true),
      RenderCase(
          'asm',
          'scan',
          'camera_error',
          () => ScanCameraErrorV2(message: 'Appka nemá přístup ke kameře.', onSettings: _n, onRetry: _n, onBack: _n),
          asmBase,
          scaffold: false),
    ];
