import 'dart:async';
import 'dart:io' show HandshakeException, HttpException, SocketException;

import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debug_logger.dart';
import 'i18n/i18n_provider.dart';

/// Druh chyby z pohledu zákazníka (co se stalo a co s tím může udělat).
enum FriendlyKind {
  offline,
  timeout,
  server,
  auth,
  notFound,
  permission,
  locationOff,
  rateLimit,
  tooLarge,
  unknown,
}

/// Oprávnění telefonu, kterého se chyba týká (text „Appka nemá přístup k …").
enum DevicePerm { camera, photos, location, notifications }

/// Sdílený převod technické chyby na srozumitelnou hlášku (2026-10-16,
/// požadavek majitele: každá chyba říká CO se stalo, PROČ a JAK to opravit).
///
/// NIKDY nezobrazuje `e.toString()` — technický text jde jen do
/// `AppDebugLogger` ([log]). Texty jsou v `translations_ext_37_errother_*`.
class FriendlyError {
  final FriendlyKind kind;
  final DevicePerm? perm;
  const FriendlyError(this.kind, {this.perm});

  /// Zmapuje libovolnou výjimku. [perm] upřesní, o které oprávnění jde
  /// (fotoaparát / fotky / poloha), když to z výjimky nejde poznat.
  factory FriendlyError.of(Object? e, {DevicePerm? perm}) {
    final k = kindOf(e);
    return FriendlyError(k, perm: k == FriendlyKind.permission ? (perm ?? permOf(e)) : null);
  }

  static int? _status(Object? s) => s is int ? s : int.tryParse('${s ?? ''}');

  static FriendlyKind _byStatus(int? s) {
    if (s == null) return FriendlyKind.unknown;
    if (s == 401 || s == 403) return FriendlyKind.auth;
    if (s == 404) return FriendlyKind.notFound;
    if (s == 408 || s == 504) return FriendlyKind.timeout;
    if (s == 413) return FriendlyKind.tooLarge;
    if (s == 429) return FriendlyKind.rateLimit;
    if (s >= 500) return FriendlyKind.server;
    return FriendlyKind.unknown;
  }

  static bool _netText(String m) =>
      m.contains('failed host lookup') ||
      m.contains('socketexception') ||
      m.contains('clientexception') ||
      m.contains('connection refused') ||
      m.contains('connection reset') ||
      m.contains('connection closed') ||
      m.contains('connection abort') ||
      m.contains('network is unreachable') ||
      m.contains('no address associated') ||
      m.contains('err_internet_disconnected') ||
      m.contains('err_name_not_resolved') ||
      m.contains('err_connection') ||
      m.contains('err_network');

  /// Druh chyby. Pořadí: síť a limit dřív než stavové kódy.
  static FriendlyKind kindOf(Object? e) {
    if (e == null) return FriendlyKind.unknown;
    if (e is FriendlyError) return e.kind;
    if (e is TimeoutException) return FriendlyKind.timeout;
    if (e is SocketException || e is HandshakeException || e is HttpException) {
      return FriendlyKind.offline;
    }
    final m = e.toString().toLowerCase();
    if (e is AuthRetryableFetchException) {
      final s = _status(e.statusCode);
      if (s != null && s >= 500) return FriendlyKind.server;
      return m.contains('timeout') ? FriendlyKind.timeout : FriendlyKind.offline;
    }
    if (e is PostgrestException) {
      final code = e.code ?? '';
      if (code == 'PGRST116' || code == '22P02') return FriendlyKind.notFound;
      if (code == '42501' || m.contains('row-level security')) {
        return FriendlyKind.notFound;
      }
      if (code == '57014') return FriendlyKind.timeout;
      if (code == 'PGRST301' || code == 'PGRST302' || m.contains('jwt')) {
        return FriendlyKind.auth;
      }
      if (_netText(m)) return FriendlyKind.offline;
      if (code.startsWith('PGRST0') || code.startsWith('08') || code.startsWith('53')) {
        return FriendlyKind.server;
      }
      return FriendlyKind.unknown;
    }
    if (e is FunctionException) {
      // status 0 = požadavek vůbec neodešel (síť / limit) — příčina v details.
      if (e.status == 0) {
        final inner = kindOf(e.details);
        return inner == FriendlyKind.timeout ? inner : FriendlyKind.offline;
      }
      return _byStatus(e.status);
    }
    if (e is StorageException) {
      final k = _byStatus(_status(e.statusCode));
      if (k != FriendlyKind.unknown) return k;
      if (m.contains('exceeded the maximum') || m.contains('too large')) {
        return FriendlyKind.tooLarge;
      }
      return _netText(m) ? FriendlyKind.offline : FriendlyKind.unknown;
    }
    if (e is AuthException) {
      final k = _byStatus(_status(e.statusCode));
      if (k != FriendlyKind.unknown) return k;
      if (m.contains('rate limit')) return FriendlyKind.rateLimit;
      if (m.contains('jwt') || m.contains('refresh token') || m.contains('session')) {
        return FriendlyKind.auth;
      }
      return _netText(m) ? FriendlyKind.offline : FriendlyKind.unknown;
    }
    // Oprávnění a služby telefonu (image_picker, camera, geolocator).
    if (m.contains('locationservicedisabled') ||
        m.contains('location services are disabled') ||
        (m.contains('location service') && m.contains('disabled'))) {
      return FriendlyKind.locationOff;
    }
    if (m.contains('accessdenied') ||
        m.contains('access_denied') ||
        m.contains('accessrestricted') ||
        m.contains('permissiondenied') ||
        m.contains('permission denied') ||
        m.contains('not authorized') ||
        (e is PlatformException && m.contains('permission'))) {
      return FriendlyKind.permission;
    }
    if (m.contains('timeoutexception') || m.contains('timed out')) {
      return FriendlyKind.timeout;
    }
    if (_netText(m)) return FriendlyKind.offline;
    if (m.contains('rate limit') || m.contains('too many requests')) {
      return FriendlyKind.rateLimit;
    }
    return FriendlyKind.unknown;
  }

  /// Které oprávnění chybí — odhad z textu výjimky.
  static DevicePerm? permOf(Object? e) {
    final m = (e?.toString() ?? '').toLowerCase();
    if (m.contains('camera')) return DevicePerm.camera;
    if (m.contains('photo') || m.contains('gallery') || m.contains('library')) {
      return DevicePerm.photos;
    }
    if (m.contains('location') || m.contains('geolocat')) return DevicePerm.location;
    if (m.contains('notification')) return DevicePerm.notifications;
    return null;
  }

  bool get isNetwork => kind == FriendlyKind.offline || kind == FriendlyKind.timeout;

  /// Nápravu najde zákazník v Nastavení telefonu → nabídnout „Otevřít nastavení".
  bool get needsSettings =>
      kind == FriendlyKind.permission || kind == FriendlyKind.locationOff;

  /// Chyba na naší straně / neznámá → nabídnout kontakt.
  bool get suggestContact =>
      kind == FriendlyKind.server || kind == FriendlyKind.unknown;

  String get _k => switch (kind) {
        FriendlyKind.offline => 'Offline',
        FriendlyKind.timeout => 'Timeout',
        FriendlyKind.server => 'Server',
        FriendlyKind.auth => 'Auth',
        FriendlyKind.notFound => 'NotFound',
        FriendlyKind.permission => 'Perm',
        FriendlyKind.locationOff => 'LocOff',
        FriendlyKind.rateLimit => 'Rate',
        FriendlyKind.tooLarge => 'TooLarge',
        FriendlyKind.unknown => 'Unknown',
      };

  String get _p => switch (perm) {
        DevicePerm.camera => 'Camera',
        DevicePerm.photos => 'Photos',
        DevicePerm.location => 'Location',
        DevicePerm.notifications => 'Notif',
        null => '',
      };

  /// Titulek — CO se stalo („Nejsi připojený k internetu").
  String title(AppTranslations tr) => tr.tr('eo${_k}Title');

  /// Tělo — PROČ a JAK to opravit (celé věty). [contact] = false: bez e-mailu
  /// a telefonu (platby, rezervace — D5); u chyby serveru / neznámé pak text
  /// jen vysvětlí, že nic není ztracené, a vyzve zkusit to znovu.
  String body(AppTranslations tr, {bool contact = true}) => kind == FriendlyKind.permission
      ? tr.tr('eoPermBody$_p')
      : tr.tr('eo$_k${!contact && suggestContact ? 'BodyNc' : 'Body'}');

  /// Krátký důvod do věty „X se nepodařilo – {důvod}." (malým písmenem).
  String reason(AppTranslations tr) => kind == FriendlyKind.permission
      ? tr.tr('eoPermReason$_p')
      : tr.tr('eo${_k}Reason');

  /// Krátká rada, co udělat (jedna věta); [contact] jako u [body].
  String hint(AppTranslations tr, {bool contact = true}) => kind == FriendlyKind.permission
      ? tr.tr('eoPermHint')
      : tr.tr('eo$_k${!contact && suggestContact ? 'HintNc' : 'Hint'}');

  /// „{co se nepovedlo} – {důvod}. {rada}" — jedna hláška pro toast / kartu.
  /// [contact] = false: rada bez e-mailu a telefonu (platby, rezervace — D5).
  String compose(AppTranslations tr, String what, {bool contact = true}) =>
      '$what – ${reason(tr)}. ${hint(tr, contact: contact)}';

  /// Zaloguje technický detail (do Velínu), zákazník ho nikdy nevidí.
  static void log(String where, Object? e, [StackTrace? st]) {
    try {
      AppDebugLogger.instance.log(LogCategory.error, where,
          detail: '${e.runtimeType}: $e', data: {'kind': kindOf(e).name});
    } catch (_) {/* logger ještě není inicializovaný (testy) */}
  }
}
