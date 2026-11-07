// auth_sos_misc (ASM-01…07, 27, 28): v2 login / registration / reset /
// welcome — the seams show the v2 views, errors stay at the field (same
// validators), every button runs the screen's own callback, the iOS edge
// swipe runs the same step back, the welcome closes once (timer or tap).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_choice_card.dart';
import 'package:motogo_app/core/v2/widgets/mg_inputs.dart';
import 'package:motogo_app/features/auth/login_screen.dart';
import 'package:motogo_app/features/auth/register_screen.dart';
import 'package:motogo_app/features/auth/reset_password_screen.dart';
import 'package:motogo_app/features/auth/v2/code_boxes_v2.dart';
import 'package:motogo_app/features/auth/auth_error_mapper.dart';
import 'package:motogo_app/features/auth/v2/login_states_v2.dart';
import 'package:motogo_app/features/auth/v2/login_view_v2.dart';
import 'package:motogo_app/features/auth/v2/register_view_v2.dart';
import 'package:motogo_app/features/auth/v2/reset_view_v2.dart';
import 'package:motogo_app/features/auth/v2/welcome_overlay_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_auth_sos_misc.dart' show asmBase, asmRegModel, asmResetModel;
import '../support/asm_harness.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(loadMontserrat);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('login: flag ON = v2 view, OFF = old screen', (t) async {
    await pumpAsmRouted(t, const LoginScreen(), overrides: asmBase());
    await t.pump();
    expect(find.byType(LoginViewV2), findsOneWidget);
    await pumpAsmRouted(t, const LoginScreen(), v2: false, overrides: asmBase());
    await t.pump();
    expect(find.byType(LoginViewV2), findsNothing);
  });

  testWidgets('login: empty submit → inline errors (no toast), typing clears them', (t) async {
    await pumpAsmRouted(t, const LoginScreen(), overrides: asmBase());
    await t.pump();
    await t.ensureVisible(find.text('PŘIHLÁSIT SE'));
    await t.tap(find.text('PŘIHLÁSIT SE'));
    await t.pump();
    expect(find.text('Vyplň e-mail'), findsOneWidget);
    expect(find.text('Vyplň heslo'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await t.enterText(find.byType(TextField).first, 'a@b.cz');
    await t.pump();
    expect(find.text('Vyplň e-mail'), findsNothing);
  });

  testWidgets('login view: every button runs its callback', (t) async {
    final hits = <String>[];
    void h(String s) => hits.add(s);
    await pumpV2(
        t,
        LoginViewV2(
          emailCtrl: TextEditingController(),
          passCtrl: TextEditingController(),
          loading: false,
          bioVisible: true,
          onLogin: () => h('login'),
          onBio: () => h('bio'),
          onForgot: () => h('forgot'),
          onRegister: () => h('register'),
          onEdited: () {},
          onWeb: () => h('web'),
        ),
        scaffold: false);
    await t.pump();
    for (final label in ['Zapomenuté heslo?', 'PŘIHLÁSIT SE', 'Přihlásit biometrikou', 'REGISTROVAT', 'motogo24.CZ']) {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(hits, ['forgot', 'login', 'bio', 'register', 'web']);
  });

  testWidgets('register: flag ON → v2 view; invalid first name → error at the field, no toast', (t) async {
    await pumpAsmRouted(t, const RegisterScreen(initialEmail: 'jan@x.cz'));
    await t.pump();
    expect(find.byType(RegisterViewV2), findsOneWidget);
    await t.tap(find.text('POKRAČOVAT'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Napiš platné jméno (aspoň 2 písmena, bez číslic)'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Jan');
    await t.pump();
    expect(find.textContaining('Napiš platné jméno'), findsNothing);
  });

  testWidgets('register step 3: licence cards and consents call the same setters', (t) async {
    final lic = <String>[];
    final vop = <bool>[];
    final base = asmRegModel(3);
    final m = RegisterV2Model(
      step: 3, loading: false, forward: true, ctrl: base.ctrl, licGroup: 'A2', onLic: lic.add,
      consentVop: false, consentGdpr: false, onVop: vop.add, onGdpr: (_) {}, errors: const {},
      keyFor: base.keyFor, onEdited: (_) {}, onBack: () {}, onNext: () {},
    );
    await pumpV2(t, RegisterViewV2(m: m), scaffold: false);
    await t.pump();
    await t.ensureVisible(find.byType(MgChoiceCard).last);
    await t.tap(find.byType(MgChoiceCard).last);
    await t.ensureVisible(find.byType(MgCheckRow).first);
    await t.tap(find.byType(MgCheckRow).first);
    await t.pump();
    expect(lic, ['A']);
    expect(vop, [true]);
  });

  testWidgets('register (iOS): left-edge swipe runs the same back → discard confirm', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpAsmRouted(t, const RegisterScreen());
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'Jan');
      await t.pump();
      await t.dragFrom(const Offset(5, 400), const Offset(250, 0));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reset: invalid e-mail → inline error (v2), no toast', (t) async {
    await pumpAsmRouted(t, const ResetPasswordScreen());
    await t.pump();
    expect(find.byType(ResetViewV2), findsOneWidget);
    await t.tap(find.text('ODESLAT KÓD'));
    await t.pump();
    expect(find.text('Napiš platný e-mail'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('reset code boxes: typing and paste fill the SAME controller (digits only); resend = send', (t) async {
    var sent = 0;
    final base = asmResetModel(2);
    base.codeCtrl.clear();
    final m = ResetV2Model(
      step: 2, loading: false, sentTo: 'a@b.cz', emailCtrl: base.emailCtrl, codeCtrl: base.codeCtrl,
      pass1Ctrl: base.pass1Ctrl, pass2Ctrl: base.pass2Ctrl, errors: const {}, onEdited: (_) {},
      onBack: () {}, onSend: () => sent++, onVerify: () {}, onSet: () {},
    );
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'Kód: 1234-5678 9'};
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpV2(t, ResetViewV2(m: m), scaffold: false);
    await t.pump();
    await t.enterText(find.descendant(of: find.byType(CodeBoxesV2), matching: find.byType(TextField)), '12a34');
    await t.pump();
    expect(m.codeCtrl.text, '1234');
    expect(find.text('3'), findsOneWidget);
    await t.tap(find.text('Vložit zkopírovaný kód'));
    await t.pump();
    expect(m.codeCtrl.text, '12345678');
    await t.tap(find.text('Odeslat kód znovu'));
    expect(sent, 1);
    expect(asmDigits('ab 12 34 56 78 90'), '12345678');
  });

  Future<int> openWelcome(WidgetTester t, {bool reduced = false}) async {
    var done = 0;
    await pumpV2(
        t,
        Builder(
            builder: (c) => TextButton(
                onPressed: () async {
                  await showWelcomeOverlayV2(c);
                  done++;
                },
                child: const Text('go'))),
        overrides: asmBase(),
        reducedMotion: reduced);
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(WelcomeOverlayV2), findsOneWidget);
    return done;
  }

  testWidgets('welcome: closes by itself after 2.8 s, exactly once', (t) async {
    var done = 0;
    await pumpV2(
        t,
        Builder(
            builder: (c) => TextButton(
                onPressed: () async {
                  await showWelcomeOverlayV2(c);
                  done++;
                },
                child: const Text('go'))),
        overrides: asmBase());
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 2000));
    expect(find.byType(WelcomeOverlayV2), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(WelcomeOverlayV2), findsNothing);
    expect(done, 1);
    await t.pump(const Duration(seconds: 3));
    expect(done, 1);
  });

  testWidgets('welcome: tap anywhere closes once; reduced motion = full progress line', (t) async {
    await openWelcome(t, reduced: true);
    final bar = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1);
    await t.tapAt(const Offset(180, 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(WelcomeOverlayV2), findsNothing);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('login states: wrong credentials T2 → "Poslat nové heslo" = existing reset; unknown e-mail T6 → register', (t) async {
    final hits = <String>[];
    await pumpV2(
        t,
        Builder(
            builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => showLoginFailedV2(c, const AuthErrorInfo(title: 'Špatné heslo', message: 'Zkontroluj ho.', code: 'x'),
                          onForgot: () => hits.add('forgot')),
                      child: const Text('a')),
                  TextButton(onPressed: () => showUnknownEmailV2(c, onRegister: () => hits.add('register')), child: const Text('b')),
                ])));
    await t.tap(find.text('a'));
    await t.pumpAndSettle();
    expect(find.text('Špatné heslo'), findsOneWidget);
    await t.tap(find.text('Poslat nové heslo'));
    await t.pumpAndSettle();
    expect(find.text('Špatné heslo'), findsNothing);
    await t.tap(find.text('b'));
    await t.pumpAndSettle();
    expect(find.text('Účet s tímhle e-mailem nemáme'), findsOneWidget);
    await t.tap(find.text('Zaregistrovat se'));
    await t.pumpAndSettle();
    expect(hits, ['forgot', 'register']);
  });
}
