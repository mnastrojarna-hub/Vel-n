import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'supabase_client.dart';

/// Log categories for structured debug logging.
enum LogCategory {
  navigation,   // screen transitions
  api,          // Supabase API calls (RPC, select, insert, update)
  auth,         // login, logout, token refresh, biometric
  payment,      // Stripe flow steps
  booking,      // booking creation, edit, cancel
  sos,          // SOS incident flow
  shop,         // cart, checkout, order
  push,         // push notification events
  network,      // online/offline transitions
  permission,   // permission requests/results
  document,     // document scan, OCR
  ui,           // button taps, form interactions
  lifecycle,    // app foreground/background/resume
  error,        // errors (also goes to crash_reports)
}

/// A single debug log entry.
class DebugLogEntry {
  final DateTime timestamp;
  final LogCategory category;
  final String action;
  final String? detail;
  final Map<String, dynamic>? data;
  final int? durationMs;

  const DebugLogEntry({
    required this.timestamp,
    required this.category,
    required this.action,
    this.detail,
    this.data,
    this.durationMs,
  });

  Map<String, dynamic> toJson(String? userId, String? appVersion) => {
    'user_id': userId,
    'app_version': appVersion,
    'platform': _platform,
    'category': category.name,
    'action': action,
    'detail': detail,
    'data': data,
    'duration_ms': durationMs,
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

/// Complete debug logger — logs EVERYTHING to Supabase for Velín.
///
/// Captures:
/// - Every screen navigation (from → to, duration on screen)
/// - Every API call (table/RPC, params, response time, success/fail)
/// - Auth events (login, logout, session expired, biometric)
/// - Payment flow (each step, amounts, Stripe results)
/// - Booking lifecycle (create, edit, cancel, complete)
/// - SOS incidents (create, type, replacement)
/// - Push notifications (received, tapped, deep link target)
/// - Network state changes (online ↔ offline)
/// - Button taps and user interactions
/// - App lifecycle (foreground, background, resume)
///
/// Design:
/// - Never throws, never blocks UI
/// - Batches logs (flush every 10s or 25 entries)
/// - Keeps last 200 entries in memory for local debug
/// - Separate table from crash_reports (debug_log is high volume)
class AppDebugLogger {
  AppDebugLogger._();

  static final _instance = AppDebugLogger._();
  static AppDebugLogger get instance => _instance;

  final _queue = Queue<DebugLogEntry>();
  final _recentLogs = <DebugLogEntry>[];
  Timer? _flushTimer;
  String? _appVersion;
  bool _initialized = false;

  // Track screen timing
  String _currentScreen = 'unknown';
  DateTime? _screenEnteredAt;

  static const _batchSize = 25;
  static const _flushInterval = Duration(seconds: 10);
  static const _maxQueueSize = 200;
  static const _maxRecentLogs = 200;
  static const _tableName = 'app_debug_logs';

  /// Initialize. Call once after Supabase init.
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

    log(LogCategory.lifecycle, 'app_start', detail: 'App initialized');
  }

  /// Main log method. Always non-blocking.
  void log(
    LogCategory category,
    String action, {
    String? detail,
    Map<String, dynamic>? data,
    int? durationMs,
  }) {
    try {
      final entry = DebugLogEntry(
        timestamp: DateTime.now(),
        category: category,
        action: action,
        detail: detail,
        data: data,
        durationMs: durationMs,
      );

      // Keep in memory for local debug
      _recentLogs.add(entry);
      if (_recentLogs.length > _maxRecentLogs) {
        _recentLogs.removeAt(0);
      }

      // Add to send queue
      if (_queue.length >= _maxQueueSize) {
        _queue.removeFirst();
      }
      _queue.add(entry);

      if (_queue.length >= _batchSize) {
        _flush();
      }

      // Console output in debug mode
      if (kDebugMode) {
        debugPrint('[${category.name}] $action${detail != null ? ': $detail' : ''}');
      }
    } catch (_) {}
  }

  // ── Convenience methods ──

  /// Log screen navigation.
  void screen(String screenName) {
    // Log time spent on previous screen
    if (_screenEnteredAt != null) {
      final duration = DateTime.now().difference(_screenEnteredAt!).inMilliseconds;
      log(LogCategory.navigation, 'screen_exit', detail: _currentScreen,
          data: {'duration_ms': duration});
    }
    _currentScreen = screenName;
    _screenEnteredAt = DateTime.now();
    log(LogCategory.navigation, 'screen_enter', detail: screenName);
  }

  /// Log API call with timing.
  Future<T> apiCall<T>(
    String operation,
    Future<T> Function() call, {
    Map<String, dynamic>? params,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await call();
      sw.stop();
      log(LogCategory.api, operation,
          detail: 'success',
          data: {
            if (params != null) 'params': params,
            'response_type': result.runtimeType.toString(),
          },
          durationMs: sw.elapsedMilliseconds);
      return result;
    } catch (e) {
      sw.stop();
      log(LogCategory.api, operation,
          detail: 'error: ${e.runtimeType}',
          data: {
            if (params != null) 'params': params,
            'error': e.toString(),
          },
          durationMs: sw.elapsedMilliseconds);
      rethrow;
    }
  }

  /// Log auth event.
  void auth(String event, {String? detail, Map<String, dynamic>? data}) {
    log(LogCategory.auth, event, detail: detail, data: data);
  }

  /// Log payment step.
  void payment(String step, {String? detail, Map<String, dynamic>? data}) {
    log(LogCategory.payment, step, detail: detail, data: data);
  }

  /// Log button tap.
  void tap(String button, {String? screen}) {
    log(LogCategory.ui, 'tap', detail: button,
        data: {'screen': screen ?? _currentScreen});
  }

  /// Log network state change.
  void network(String state, {Map<String, dynamic>? data}) {
    log(LogCategory.network, state, data: data);
  }

  /// Log push notification event.
  void push(String event, {Map<String, dynamic>? data}) {
    log(LogCategory.push, event, data: data);
  }

  /// Log app lifecycle.
  void lifecycle(String state) {
    log(LogCategory.lifecycle, state);
  }

  /// Get current screen name.
  String get currentScreen => _currentScreen;

  /// Get recent logs (for local debug panel if needed).
  List<DebugLogEntry> get recentLogs => List.unmodifiable(_recentLogs);

  // ── Flush logic ──

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  Future<void> _flush() async {
    if (_queue.isEmpty) return;

    final batch = <DebugLogEntry>[];
    while (_queue.isNotEmpty && batch.length < _batchSize) {
      batch.add(_queue.removeFirst());
    }

    final userId = MotoGoSupabase.currentUser?.id;

    try {
      final rows = batch.map((e) => e.toJson(userId, _appVersion)).toList();
      await MotoGoSupabase.client.from(_tableName).insert(rows);
    } catch (e) {
      // Re-queue on failure (but respect max)
      for (final entry in batch.reversed) {
        if (_queue.length < _maxQueueSize) {
          _queue.addFirst(entry);
        }
      }
      if (kDebugMode) {
        debugPrint('[DebugLogger] Flush failed: $e');
      }
    }
  }

  /// Force flush — call on app pause.
  Future<void> flushNow() async {
    try {
      await _flush();
    } catch (_) {}
  }

  void dispose() {
    _flushTimer?.cancel();
    _flush();
  }
}
