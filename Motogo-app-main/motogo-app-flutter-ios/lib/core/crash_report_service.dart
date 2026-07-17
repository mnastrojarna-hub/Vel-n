import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'debug_logger.dart';
import 'supabase_client.dart';

/// Severity levels for crash reports.
enum CrashSeverity { info, warning, error, critical }

/// A single crash report entry.
class CrashReport {
  final DateTime timestamp;
  final String errorType;
  final String errorMessage;
  final String? stackTrace;
  final String? screen;
  final String? action;
  final CrashSeverity severity;
  final Map<String, dynamic>? extra;

  const CrashReport({
    required this.timestamp,
    required this.errorType,
    required this.errorMessage,
    this.stackTrace,
    this.screen,
    this.action,
    this.severity = CrashSeverity.error,
    this.extra,
  });

  Map<String, dynamic> toJson(String? userId, String? appVersion) => {
    'user_id': userId,
    'app_version': appVersion,
    'platform': _platform,
    'screen': screen,
    'action': action,
    'error_type': errorType,
    'error_message': errorMessage,
    'stack_trace': stackTrace != null
        ? (stackTrace!.length > 4000
            ? stackTrace!.substring(0, 4000)
            : stackTrace!)
        : null,
    'severity': severity.name,
    'extra_data': extra,
    'created_at': timestamp.toUtc().toIso8601String(),
  };

  static String get _platform {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}

/// Crash report service — collects errors silently and pushes
/// batched reports to Supabase `app_crash_reports` table.
///
/// Design principles:
/// - NEVER throws — all internal errors are swallowed
/// - NEVER blocks UI — reports are queued and sent async
/// - Batches reports to reduce DB writes (flushes every 5s or 10 reports)
/// - Deduplicates identical errors within 60s window
/// - Trims stack traces to 4000 chars max
class CrashReportService {
  CrashReportService._();

  static final _instance = CrashReportService._();
  static CrashReportService get instance => _instance;

  /// Queue of pending reports.
  final _queue = Queue<CrashReport>();

  /// Dedup: recent error fingerprints (hash → timestamp).
  final _recentErrors = <String, DateTime>{};

  /// Flush timer.
  Timer? _flushTimer;

  /// App version (cached once).
  String? _appVersion;

  /// Whether the service is initialized.
  bool _initialized = false;

  // ── Configuration ──
  static const _batchSize = 10;
  static const _flushInterval = Duration(seconds: 5);
  static const _dedupWindow = Duration(seconds: 60);
  static const _maxQueueSize = 100;
  static const _tableName = 'app_crash_reports';

  /// Initialize the service. Call once at app startup.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    _startFlushTimer();
  }

  /// Report an error. This is the main entry point.
  /// Always returns immediately — never blocks.
  void report({
    required String errorType,
    required String errorMessage,
    String? stackTrace,
    String? screen,
    String? action,
    CrashSeverity severity = CrashSeverity.error,
    Map<String, dynamic>? extra,
  }) {
    try {
      // Re-classify known non-fatal errors that surface through the global
      // handlers as „critical" even though the app keeps running. Without this
      // Velín shows them as „Kritická (restart appky)", drowning the real
      // crashes in noise. Only ever downgrades — never hides a true crash.
      severity = _effectiveSeverity(errorType, errorMessage, severity);

      // Deduplicate: same error+screen within 60s → skip
      final fingerprint = '$errorType:$errorMessage:$screen';
      final now = DateTime.now();
      final lastSeen = _recentErrors[fingerprint];
      if (lastSeen != null && now.difference(lastSeen) < _dedupWindow) {
        return;
      }
      _recentErrors[fingerprint] = now;

      // Clean old dedup entries
      _recentErrors.removeWhere(
          (_, ts) => now.difference(ts) > _dedupWindow);

      // For a FATAL crash (the kind that shows the „Restartujte aplikaci"
      // screen) enrich the report so Velín receives a COMPLETE, solvable bug:
      // the recent breadcrumb trail (actions/API calls/screens that led up to
      // it) + the screen the user was on. Non-fatal reports stay lightweight.
      final bool isFatal = severity == CrashSeverity.critical;
      String? effScreen = screen;
      Map<String, dynamic>? effExtra = extra;
      if (isFatal) {
        effScreen = screen ?? AppDebugLogger.instance.currentScreen;
        effExtra = {
          if (extra != null) ...extra,
          'current_screen': AppDebugLogger.instance.currentScreen,
          'breadcrumbs': AppDebugLogger.instance.breadcrumbSnapshot(),
        };
      }

      // Add to queue (cap size)
      if (_queue.length >= _maxQueueSize) {
        _queue.removeFirst();
      }
      _queue.add(CrashReport(
        timestamp: now,
        errorType: errorType,
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        screen: effScreen,
        action: action,
        severity: severity,
        extra: effExtra,
      ));

      // Flush immediately on a fatal crash (deliver before a possible restart)
      // or when the batch is full.
      if (isFatal || _queue.length >= _batchSize) {
        _flush();
      }
    } catch (_) {
      // Never throw from the crash reporter itself
    }
  }

  /// Convenience: report a caught exception.
  void reportException(
    Object error,
    StackTrace? stack, {
    String? screen,
    String? action,
    CrashSeverity severity = CrashSeverity.error,
    Map<String, dynamic>? extra,
  }) {
    report(
      errorType: error.runtimeType.toString(),
      errorMessage: error.toString(),
      stackTrace: stack?.toString(),
      screen: screen,
      action: action,
      severity: severity,
      extra: extra,
    );
  }

  /// Convenience: report a FlutterErrorDetails.
  void reportFlutterError(FlutterErrorDetails details) {
    // A „silent" FlutterError is one the framework itself does NOT surface
    // (it never triggers the ErrorWidget / „Restartujte aplikaci" screen).
    // The classic case is the image resource service failing to fetch a
    // picture (HTTP 429/404, offline, …) — the app keeps running and just
    // shows the placeholder. Reporting these as „critical" made Velín label
    // them „Kritická (restart appky)", burying the real crashes in noise.
    // Non-silent framework errors stay critical.
    final severity =
        details.silent ? CrashSeverity.warning : CrashSeverity.critical;
    report(
      errorType: 'FlutterError',
      errorMessage: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
      screen: details.context?.toString(),
      severity: severity,
      extra: {
        'library': details.library,
        'silent': details.silent,
      },
    );
  }

  /// Downgrade a „critical" report to `warning` when it matches a known
  /// non-fatal pattern. The app does NOT restart for any of these:
  /// - Google Fonts runtime fetch failure (offline) — text falls back.
  /// - Transient network / DNS errors (host lookup, socket, timeout).
  /// - Expired/revoked refresh token — handled by the auth listener (sign-out).
  /// - RenderFlex layout overflow — cosmetic, app continues.
  /// - Secure-storage keystore rotation (BadPaddingException) — recovered by
  ///   clearing the corrupted entry.
  /// - Stripe CardField focus/blur on a disposed platform view
  ///   (MissingPluginException on flutter.stripe/card_field).
  /// Everything else stays `critical`.
  static CrashSeverity _effectiveSeverity(
      String errorType, String message, CrashSeverity requested) {
    if (requested != CrashSeverity.critical) return requested;
    final blob = '$errorType $message'.toLowerCase();
    bool has(String s) => blob.contains(s);

    if (has('failed to load font')) return CrashSeverity.warning;

    // Image resource service failing to fetch a picture (rate-limit 429,
    // 404, transient HTTP error). Only the placeholder is affected — the
    // app never restarts.
    if (has('http request failed') ||
        has('image resource service') ||
        has('networkimage') ||
        has('errorwhenfetchingimage')) {
      return CrashSeverity.warning;
    }

    if (has('failed host lookup') ||
        has('socketexception') ||
        has('clientexception') ||
        has('authretryablefetchexception') ||
        has('connection closed') ||
        has('connection reset') ||
        has('handshakeexception') ||
        has('timeoutexception')) {
      return CrashSeverity.warning;
    }

    if (has('authapiexception') ||
        has('refresh token') ||
        has('refresh_token')) {
      return CrashSeverity.warning;
    }

    if (has('renderflex overflowed') || has('overflowed by')) {
      return CrashSeverity.warning;
    }

    if (has('badpaddingexception') || has('bad_decrypt')) {
      return CrashSeverity.warning;
    }

    // flutter_stripe CardField: `focus`/`blur` doručené na nativní pole,
    // které systém mezitím zahodil (návrat z pozadí, 3DS, zavřený sheet).
    // Appka běží dál — nejde o pád, jen o osiřelý platform-view kanál.
    if (has('missingpluginexception') && has('flutter.stripe')) {
      return CrashSeverity.warning;
    }

    return CrashSeverity.critical;
  }

  // ── Internal flush logic ──

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  Future<void> _flush() async {
    if (_queue.isEmpty) return;

    // Take all pending reports
    final batch = <CrashReport>[];
    while (_queue.isNotEmpty && batch.length < _batchSize) {
      batch.add(_queue.removeFirst());
    }

    final userId = MotoGoSupabase.currentUser?.id;

    try {
      final rows = batch.map((r) => r.toJson(userId, _appVersion)).toList();
      await MotoGoSupabase.client.from(_tableName).insert(rows);
    } catch (e) {
      // If insert fails (table doesn't exist, network error, etc.)
      // → put reports back in queue for retry (but don't exceed max)
      for (final r in batch.reversed) {
        if (_queue.length < _maxQueueSize) {
          _queue.addFirst(r);
        }
      }
      debugPrint('[CrashReport] Flush failed: $e');
    }
  }

  /// Force flush — call on app pause/close.
  Future<void> flushNow() async {
    try {
      await _flush();
    } catch (_) {}
  }

  /// Stop the service.
  void dispose() {
    _flushTimer?.cancel();
    _flush(); // Best-effort final flush
  }
}
