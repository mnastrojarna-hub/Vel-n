import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/friendly_error.dart';
import '../../core/i18n/i18n_provider.dart';

/// Srozumitelné hlášky pro obnovu / změnu hesla (2026-10-16). Dřív se ukazoval
/// holý anglický text GoTrue („Token has expired or is invalid", „New password
/// should be different…") nebo technický text síťové chyby.
class PasswordFlowErrors {
  PasswordFlowErrors._();

  static String _msg(Object e) =>
      (e is AuthException ? e.message : e.toString()).toLowerCase();

  static String _code(Object e) => e is AuthException ? (e.code ?? '') : '';

  static String? _common(Object e, AppTranslations tr, String what) {
    final fe = FriendlyError.of(e);
    if (fe.isNetwork || fe.kind == FriendlyKind.server) return fe.compose(tr, tr.tr(what));
    final m = _msg(e);
    if (fe.kind == FriendlyKind.rateLimit ||
        m.contains('rate limit') ||
        _code(e).startsWith('over_')) {
      return tr.tr('eoRateBody');
    }
    return null;
  }

  /// Ověření 8místného kódu z e-mailu.
  static String otp(Object e, String lang) {
    final tr = AppTranslations.of(lang);
    final common = _common(e, tr, 'eoOtpVerifyFail');
    if (common != null) return common;
    final m = _msg(e);
    final c = _code(e);
    if (c.startsWith('otp_') ||
        m.contains('expired') ||
        m.contains('invalid') ||
        m.contains('token')) {
      return tr.tr('eoOtpInvalid');
    }
    return FriendlyError.of(e).compose(tr, tr.tr('eoOtpVerifyFail'));
  }

  /// Uložení nového hesla (obnova hesla i změna v Nastavení).
  static String update(Object e, String lang) {
    final tr = AppTranslations.of(lang);
    final common = _common(e, tr, 'eoPwSaveFail');
    if (common != null) return common;
    final m = _msg(e);
    final c = _code(e);
    if (c == 'same_password' || m.contains('different from') || m.contains('should be different')) {
      return tr.tr('eoPwSame');
    }
    if (c == 'weak_password' || m.contains('password should') || m.contains('weak')) {
      return tr.tr('eoPwWeak');
    }
    if (c == 'reauthentication_needed' || c == 'reauthentication_not_valid') {
      return tr.tr('eoPwReauth');
    }
    if (c.contains('session') || m.contains('session') || FriendlyError.kindOf(e) == FriendlyKind.auth) {
      return tr.tr('eoPwSessionGone');
    }
    return FriendlyError.of(e).compose(tr, tr.tr('eoPwSaveFail'));
  }
}
