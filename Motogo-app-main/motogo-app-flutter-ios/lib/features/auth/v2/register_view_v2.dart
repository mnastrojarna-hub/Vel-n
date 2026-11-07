import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_swipe_switcher.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'auth_parts_v2.dart';
import 'register_steps_v2.dart';

/// Everything the v2 registration shows, owned by the registration screen
/// (same controllers, values, callbacks — the view decides nothing).
class RegisterV2Model {
  final int step;
  final bool loading;
  final bool forward;
  final Map<String, TextEditingController> ctrl;
  final String licGroup;
  final ValueChanged<String> onLic;
  final bool consentVop;
  final bool consentGdpr;
  final ValueChanged<bool> onVop;
  final ValueChanged<bool> onGdpr;
  final Map<String, String> errors;
  final GlobalKey Function(String field) keyFor;
  final ValueChanged<String> onEdited;
  final VoidCallback onBack;
  final VoidCallback onNext;
  const RegisterV2Model({
    required this.step,
    required this.loading,
    required this.forward,
    required this.ctrl,
    required this.licGroup,
    required this.onLic,
    required this.consentVop,
    required this.consentGdpr,
    required this.onVop,
    required this.onGdpr,
    required this.errors,
    required this.keyFor,
    required this.onEdited,
    required this.onBack,
    required this.onNext,
  });
}

/// v2 registration (Prihlaseni board "Registrace 1/3–3/3"): light canvas,
/// back (16,55) + "Registrace pilota" + "1/3" chip + 3-segment bar; one
/// white card per step (step disc, "KROK n / 3", 20/800 title); labels
/// above inputs; dark dock with POKRAČOVAT → / DOKONČIT REGISTRACI (may wrap,
/// never clipped). Step change = directional slide + fade (MgStepFade).
class RegisterViewV2 extends StatelessWidget {
  final RegisterV2Model m;
  const RegisterViewV2({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final last = m.step == 3;
    return MgStatusBar(
      dark: false,
      child: Scaffold(
        backgroundColor: MgColors.canvas,
        body: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 12),
            child: Column(children: [
              Row(children: [
                MgV2Back(onTap: m.onBack, style: MgBackStyle.light),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: MgWordFit(
                      minScale: 0.7,
                      child: Text(tr.tr('registerTitle'),
                          maxLines: 2, style: MgType.section.copyWith(color: MgColors.ink)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AsmStepChip('${m.step}/3'),
              ]),
              const SizedBox(height: 14),
              AsmStepBar(step: m.step),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: MgStepFade(
                trigger: m.step,
                direction: m.forward ? 1 : -1,
                child: _StepCard(m: m),
              ),
            ),
          ),
          MgDock(
            child: MgCta(
              label: last ? tr.tr('finishRegistration') : tr.tr('continueBtn'),
              onTap: m.onNext,
              busy: m.loading,
              arrow: !last,
              leadingIcon: last ? MgIcons.checkCircle : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final RegisterV2Model m;
  const _StepCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final n = m.step;
    return Container(
      key: ValueKey('reg-step-$n'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MgColors.night, shape: BoxShape.circle),
            child: Text('$n', style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.trArgs('v2UxAsmStepOf', {'n': n, 'm': 3}).toUpperCase(),
                  style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.meta)),
              const SizedBox(height: 2),
              MgWordFit(minScale: 0.7, child: Text(tr.tr('v2UxAsmRegT$n'), style: MgType.h3.copyWith(color: MgColors.ink))),
              const SizedBox(height: 2),
              Text(tr.tr('v2UxAsmRegS$n'), style: MgType.small.copyWith(color: MgColors.lead)),
            ]),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, thickness: 1, color: MgColors.line),
        ),
        switch (n) {
          1 => RegisterStep1V2(m: m),
          2 => RegisterStep2V2(m: m),
          _ => RegisterStep3V2(m: m),
        },
      ]),
    );
  }
}
