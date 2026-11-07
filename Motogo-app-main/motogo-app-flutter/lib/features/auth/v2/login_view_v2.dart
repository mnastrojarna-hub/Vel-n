import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/error_feedback.dart' show callMotoGo;
import '../../../core/widgets/logo_header.dart' show appVersion;
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../biometric_service.dart';
import 'auth_parts_v2.dart';

/// v2 login (Prihlaseni board "Přihlášení", new-device variant): dark brand
/// header, white sheet overlapping −24, caps labels, dark carrier with the
/// looping PŘIHLÁSIT SE (the screen's one loop) + biometric button, "nebo",
/// ghost REGISTROVAT, footer. Every action is the login screen's own.
class LoginViewV2 extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final bool bioVisible;
  final String? emailError;
  final String? passError;
  final bool signedOutNotice;
  final VoidCallback onLogin;
  final VoidCallback onBio;
  final VoidCallback onForgot;
  final VoidCallback onRegister;
  final VoidCallback onEdited;
  final VoidCallback onWeb;
  const LoginViewV2({
    super.key,
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.bioVisible,
    required this.onLogin,
    required this.onBio,
    required this.onForgot,
    required this.onRegister,
    required this.onEdited,
    required this.onWeb,
    this.emailError,
    this.passError,
    this.signedOutNotice = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStatusBar(
      dark: true,
      child: Scaffold(
        backgroundColor: MgColors.surface,
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _BrandHeader(),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (signedOutNotice) ...[
                      MgStateBanner(
                        tone: MgTone.info,
                        icon: MgIcons.lock,
                        title: tr.tr('v2UxAsmSignedOutTitle'),
                        text: tr.tr('eoForcedSignOut'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(tr.tr('v2UxAsmLoginTitle'), style: MgType.h2.copyWith(color: MgColors.ink)),
                    const SizedBox(height: 4),
                    Text(tr.tr('v2UxAsmLoginSub'), style: MgType.body.copyWith(color: MgColors.lead)),
                    const SizedBox(height: 14),
                    _WebHint(text: tr.tr('v2UxAsmLoginWebHint')),
                    const SizedBox(height: 18),
                    AsmField(
                      label: tr.tr('email'),
                      controller: emailCtrl,
                      hint: tr.tr('v2UxAsmEmailHint'),
                      error: emailError,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      action: TextInputAction.next,
                      onChanged: (_) => onEdited(),
                    ),
                    const SizedBox(height: 14),
                    AsmField(
                      label: tr.password,
                      controller: passCtrl,
                      error: passError,
                      obscure: true,
                      autofillHints: const [AutofillHints.password],
                      action: TextInputAction.done,
                      onSubmitted: (_) => onLogin(),
                      onChanged: (_) => onEdited(),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: MgBtnText(label: tr.tr('forgotPassword'), icon: MgIcons.history, onTap: onForgot),
                    ),
                    const SizedBox(height: 10),
                    AsmCarrier(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        MgCta(
                          label: tr.loginBtn,
                          onTap: onLogin,
                          busy: loading,
                          loop: true,
                          leadingIcon: MgIcons.arrowRight,
                        ),
                        if (bioVisible) ...[
                          const SizedBox(height: 8),
                          _BioButton(onTap: loading ? null : onBio),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    AsmOrDivider(tr.tr('or')),
                    const SizedBox(height: 16),
                    MgBtnGhostLight(label: tr.registerBtn, icon: MgIcons.user, onTap: onRegister),
                    const SizedBox(height: 24),
                    _Footer(onWeb: onWeb),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(gradient: MgGradients.dark),
      padding: EdgeInsets.fromLTRB(20, top + 28, 20, 48),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: MgShadows.dark,
            ),
            child: Image.asset('assets/logo.webp',
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: MgColors.panel)),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('MOTO GO 24',
                  maxLines: 1,
                  style: MgType.display.copyWith(fontSize: 30, letterSpacing: 0.6, color: MgColors.onDark)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(t(context).tr('v2UxAsmTagline'),
            textAlign: TextAlign.center,
            style: MgType.body.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: MgColors.neon)),
      ]),
    );
  }
}

class _WebHint extends StatelessWidget {
  final String text;
  const _WebHint({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.line),
        ),
        child: Row(children: [
          const MgIconTileLight(MgIcons.globe, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.ink))),
        ]),
      );
}

/// Biometric button on the dark carrier: label by the phone's method
/// (`BiometricService.getAvailableTypes`, the service the login already
/// uses; asked once per view).
class _BioButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _BioButton({required this.onTap});

  @override
  State<_BioButton> createState() => _BioButtonState();
}

class _BioButtonState extends State<_BioButton> {
  late final Future<Set<String>> _types =
      BiometricService.getAvailableTypes().then((l) => l.map((e) => e.name).toSet());

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return FutureBuilder<Set<String>>(
      future: _types,
      builder: (context, snap) {
        final types = snap.data ?? const <String>{};
        final key = types.contains('face')
            ? 'v2UxAsmBioFace'
            : (types.contains('fingerprint') ? 'v2UxAsmBioFinger' : 'v2UxAsmBioAny');
        return MgBtnGhostDark(label: tr.tr(key), icon: MgIcons.finger, onTap: widget.onTap);
      },
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onWeb;
  const _Footer({required this.onWeb});

  @override
  Widget build(BuildContext context) {
    final meta = MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta);
    return Column(children: [
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          InkWell(
            onTap: callMotoGo,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MgIcon(MgIcons.phone, size: 16, color: MgColors.meta),
                const SizedBox(width: 6),
                Text('+420 774 256 271', style: meta),
              ]),
            ),
          ),
          Text('·', style: meta),
          InkWell(
            onTap: onWeb,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('motogo24.CZ', style: meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
            ),
          ),
        ],
      ),
      Text(appVersion, style: MgType.micro.copyWith(color: MgColors.meta)),
      SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
    ]);
  }
}
