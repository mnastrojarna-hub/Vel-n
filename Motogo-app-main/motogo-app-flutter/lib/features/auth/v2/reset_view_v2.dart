import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/error_feedback.dart' show callMotoGo, kMotoGoPhoneLabel;
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_swipe_switcher.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'auth_parts_v2.dart';
import 'code_boxes_v2.dart';

/// State of the reset flow, owned by the reset screen (same controllers,
/// same `_sendCode` / `_verifyCode` / `_setPassword`).
class ResetV2Model {
  final int step;
  final bool loading;
  final String sentTo;
  final TextEditingController emailCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController pass1Ctrl;
  final TextEditingController pass2Ctrl;
  final Map<String, String> errors;
  final ValueChanged<String> onEdited;
  final VoidCallback onBack;
  final VoidCallback onSend;
  final VoidCallback onVerify;
  final VoidCallback onSet;
  const ResetV2Model({
    required this.step,
    required this.loading,
    required this.sentTo,
    required this.emailCtrl,
    required this.codeCtrl,
    required this.pass1Ctrl,
    required this.pass2Ctrl,
    required this.errors,
    required this.onEdited,
    required this.onBack,
    required this.onSend,
    required this.onVerify,
    required this.onSet,
  });
}

/// v2 password reset (Prihlaseni "Obnovení hesla 1/3–3/3"): dark compact
/// header (‹, title, n/3 chip, progress), white sheet −24, one step at a
/// time with its CTA in a dark carrier, phone line under it.
class ResetViewV2 extends StatelessWidget {
  final ResetV2Model m;
  const ResetViewV2({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    return MgStatusBar(
      dark: true,
      child: Scaffold(
        backgroundColor: MgColors.surface,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: const BoxDecoration(gradient: MgGradients.dark),
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 48),
            child: Column(children: [
              Row(children: [
                MgV2Back(onTap: m.onBack, style: MgBackStyle.dark),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: MgWordFit(
                      minScale: 0.65,
                      child: Text(tr.tr('resetPasswordTitle'),
                          maxLines: 2, style: MgType.section.copyWith(color: MgColors.onDark)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AsmStepChip('${m.step}/3', dark: true),
              ]),
              const SizedBox(height: 20),
              AsmStepBar(step: m.step, dark: true),
            ]),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.paddingOf(context).bottom + 48),
                  child: MgStepFade(
                    trigger: m.step,
                    direction: 1,
                    child: switch (m.step) {
                      1 => _Step1(m: m),
                      2 => _Step2(m: m),
                      _ => _Step3(m: m),
                    },
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

Widget _head(String title, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: MgType.h2.copyWith(color: MgColors.ink)),
      const SizedBox(height: 6),
      Text(sub, style: MgType.body.copyWith(color: MgColors.lead)),
      const SizedBox(height: 18),
    ]);

Widget _cta(String label, String icon, VoidCallback onTap, bool busy) => Column(children: [
      const SizedBox(height: 18),
      AsmCarrier(child: MgCta(label: label, onTap: onTap, busy: busy, leadingIcon: icon)),
      const SizedBox(height: 14),
      InkWell(
        onTap: callMotoGo,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.phone, size: 16, color: MgColors.meta),
            const SizedBox(width: 6),
            Text(kMotoGoPhoneLabel, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta)),
          ]),
        ),
      ),
    ]);

class _Step1 extends StatelessWidget {
  final ResetV2Model m;
  const _Step1({required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(tr.tr('v2UxAsmResetT1'), tr.tr('v2UxAsmResetS1')),
        AsmField(
          label: tr.tr('email'),
          controller: m.emailCtrl,
          hint: tr.tr('v2UxAsmEmailHint'),
          error: m.errors['email'],
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          action: TextInputAction.done,
          onSubmitted: (_) => m.onSend(),
          onChanged: (_) => m.onEdited('email'),
        ),
        _cta(tr.tr('sendCode'), MgIcons.send, m.onSend, m.loading),
      ]),
    );
  }
}

class _Step2 extends StatelessWidget {
  final ResetV2Model m;
  const _Step2({required this.m});

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = asmDigits(data?.text ?? '');
    if (digits.isEmpty) return;
    m.codeCtrl.value = TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
    m.onEdited('code');
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final err = m.errors['code'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _head(tr.tr('v2UxAsmResetT2'), tr.trArgs('v2UxAsmResetS2', {'email': m.sentTo})),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AsmLabel(tr.tr('codeLabel')),
          MgBtnText(label: tr.tr('v2UxAsmPasteCode'), icon: MgIcons.copy, onTap: _paste),
        ],
      ),
      const SizedBox(height: 4),
      CodeBoxesV2(
        controller: m.codeCtrl,
        error: err != null,
        semanticLabel: tr.tr('codeLabel'),
        onSubmitted: (_) => m.onVerify(),
        onChanged: (_) => m.onEdited('code'),
      ),
      if (err != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(err, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.err)),
        ),
      const SizedBox(height: 8),
      Center(
        child: MgBtnText(label: tr.tr('resendCode'), icon: MgIcons.history, onTap: m.loading ? null : m.onSend),
      ),
      _cta(tr.tr('verifyCodeBtn'), MgIcons.checkCircle, m.onVerify, m.loading),
    ]);
  }
}

class _Step3 extends StatelessWidget {
  final ResetV2Model m;
  const _Step3({required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(tr.tr('newPassword'), tr.tr('v2UxAsmResetS3')),
        AsmField(
          label: tr.tr('newPasswordLabel'),
          controller: m.pass1Ctrl,
          error: m.errors['pass1'],
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          action: TextInputAction.next,
          onChanged: (_) => m.onEdited('pass1'),
        ),
        const SizedBox(height: 14),
        AsmField(
          label: tr.tr('passwordAgain'),
          controller: m.pass2Ctrl,
          error: m.errors['pass2'],
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          action: TextInputAction.done,
          onSubmitted: (_) => m.onSet(),
          onChanged: (_) => m.onEdited('pass2'),
        ),
        const SizedBox(height: 12),
        // Live checks with the SAME rules as `_setPassword` (≥ 8, equal).
        ListenableBuilder(
          listenable: Listenable.merge([m.pass1Ctrl, m.pass2Ctrl]),
          builder: (context, _) {
            final p1 = m.pass1Ctrl.text, p2 = m.pass2Ctrl.text;
            final len = p1.length >= 8;
            final same = p1.isNotEmpty && p1 == p2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              MgMeaningChip(
                  label: tr.tr('v2UxAsmCheckLen'),
                  tone: len ? MgTone.ok : MgTone.info,
                  icon: len ? MgIcons.check : MgIcons.info),
              MgMeaningChip(
                  label: tr.tr('v2UxAsmCheckMatch'),
                  tone: same ? MgTone.ok : MgTone.info,
                  icon: same ? MgIcons.check : MgIcons.info),
            ]);
          },
        ),
        _cta(tr.tr('setPassword'), MgIcons.lock, m.onSet, m.loading),
      ]),
    );
  }
}
