import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icons.dart';
import '../../../core/v2/states/mg_state_parts.dart';
import '../../../core/v2/states/mg_state_sheet.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../auth_error_mapper.dart';

/// v2 login / register / reset states (Stavy 18 + 8.10–8.12): errors that
/// need an action are T2 sheets or T6 dialogs, never a vanishing toast.
/// Texts come from the same mapper / keys; actions are the screen's own.

/// 18.3 — e-mail or password does not fit: T2 err, "Zkusit znovu" (closes,
/// the form stays filled) + "Poslat nové heslo" (the existing reset flow).
Future<void> showLoginFailedV2(BuildContext context, AuthErrorInfo error, {required VoidCallback onForgot}) {
  final tr = t(context);
  return showMgStateSheet<void>(
    context,
    tone: MgTone.err,
    title: error.title,
    why: error.message,
    support: false,
    primary: MgStateAction(tr.tr('eoRetry'), null),
    tertiary: MgStateAction(tr.tr('v2UxAsmSendNewPassword'), () {
      Navigator.of(context, rootNavigator: true).maybePop();
      onForgot();
    }),
  );
}

/// 18.2 — no account with this e-mail: T6 "Zrušit" / "Zaregistrovat se"
/// (the e-mail travels to the registration).
Future<void> showUnknownEmailV2(BuildContext context, {required VoidCallback onRegister}) async {
  final tr = t(context);
  final go = await showMgConfirm(
    context,
    title: tr.tr('v2UxAsmUnknownTitle'),
    body: tr.tr('v2UxAsmUnknownBody'),
    safeLabel: tr.cancel,
    actionLabel: tr.tr('v2UxAsmRegisterAction'),
  );
  if (go == true) onRegister();
}

/// 8.12 — biometric sign-in needs the internet: T2 warn + "Zkusit znovu"
/// (= the same biometric sign-in).
Future<void> showBioOfflineV2(BuildContext context, {required VoidCallback onRetry}) {
  final tr = t(context);
  return showMgStateSheet<void>(
    context,
    tone: MgTone.warn,
    icon: MgIcons.wifiOff,
    title: tr.tr('v2UxAsmOfflineTitle'),
    why: tr.tr('eoBioOffline'),
    support: false,
    primary: MgStateAction(tr.tr('eoRetry'), () {
      Navigator.of(context, rootNavigator: true).maybePop();
      onRetry();
    }),
  );
}

/// 8.11 — the saved session is gone: T2 info "Přihlas se e-mailem".
Future<void> showBioSessionGoneV2(BuildContext context) {
  final tr = t(context);
  return showMgStateSheet<void>(
    context,
    tone: MgTone.info,
    icon: MgIcons.lock,
    title: tr.tr('v2UxAsmSessionGoneTitle'),
    why: tr.tr('sessionExpired'),
    support: false,
    primary: MgStateAction(tr.tr('v2UxAsmLoginWithEmail'), null),
  );
}

/// 18.7 — the e-mail already has an account (register step 1): T6
/// "Zrušit" / "Přihlásit se" → [onLogin] (existing navigation with the
/// carried e-mail).
Future<void> showEmailTakenV2(BuildContext context, AuthErrorInfo info, {required VoidCallback onLogin}) async {
  final tr = t(context);
  final go = await showMgConfirm(
    context,
    title: info.title,
    body: info.message,
    safeLabel: tr.cancel,
    actionLabel: tr.tr('v2UxAsmLoginAction'),
  );
  if (go == true) onLogin();
}

/// T2 err for a failed request (register server error 18.8, reset send /
/// save 18.11 / 18.14). [primary] = an existing action of the screen; null
/// = "Zkusit znovu" that closes the sheet (the form stays filled).
Future<void> showAuthErrorV2(BuildContext context,
    {required String title, required String why, MgStateAction? primary, String? tech}) {
  final tr = t(context);
  return showMgStateSheet<void>(
    context,
    tone: MgTone.err,
    title: title,
    why: why,
    tech: tech,
    support: false,
    primary: primary ?? MgStateAction(tr.tr('eoRetry'), null),
  );
}
