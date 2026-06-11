import 'package:flutter/material.dart';

import 'crash_report_service.dart';
import 'i18n/i18n_provider.dart';
import '../features/auth/widgets/toast_helper.dart';

/// Current screen name tracker — set by router or screen widgets.
/// Used by crash reports to identify which screen the error occurred on.
String currentScreen = 'unknown';

/// Wraps any async callback with error catching + crash reporting.
/// Use this on EVERY button tap, form submit, and navigation action.
///
/// Example:
/// ```dart
/// onPressed: safeAction(context, 'booking.submit', () async {
///   await createBooking();
/// }),
/// ```
///
/// If the callback throws:
/// 1. Error is caught silently
/// 2. Detailed crash report is sent to Supabase
/// 3. User sees a friendly toast (never raw error)
/// 4. Returns null (for VoidCallback compatibility)
VoidCallback safeAction(
  BuildContext context,
  String actionName,
  Future<void> Function() callback, {
  CrashSeverity severity = CrashSeverity.error,
  Map<String, dynamic>? extra,
}) {
  return () async {
    try {
      await callback();
    } catch (e, stack) {
      CrashReportService.instance.report(
        errorType: e.runtimeType.toString(),
        errorMessage: e.toString(),
        stackTrace: stack.toString(),
        screen: currentScreen,
        action: actionName,
        severity: severity,
        extra: {
          if (extra != null) ...extra,
          'user_id': _safeUserId(),
        },
      );

      // Show friendly toast — never expose raw error
      if (context.mounted) {
        showMotoGoToast(
          context,
          icon: '⚠️',
          title: t(context).tr('error'),
          message: t(context).tr('tryAgainPlease'),
        );
      }
    }
  };
}

/// Synchronous version for non-async callbacks.
VoidCallback safeSync(
  BuildContext context,
  String actionName,
  void Function() callback,
) {
  return () {
    try {
      callback();
    } catch (e, stack) {
      CrashReportService.instance.report(
        errorType: e.runtimeType.toString(),
        errorMessage: e.toString(),
        stackTrace: stack.toString(),
        screen: currentScreen,
        action: actionName,
      );
      if (context.mounted) {
        showMotoGoToast(
          context,
          icon: '⚠️',
          title: t(context).tr('error'),
          message: t(context).tr('tryAgainPlease'),
        );
      }
    }
  };
}

/// Wraps a Future-returning function and catches errors.
/// Use for async operations that return values.
///
/// Example:
/// ```dart
/// final result = await safeFuture(context, 'payment.process', () async {
///   return await processPayment();
/// });
/// ```
Future<T?> safeFuture<T>(
  BuildContext context,
  String actionName,
  Future<T> Function() callback, {
  CrashSeverity severity = CrashSeverity.error,
  bool showToast = true,
}) async {
  try {
    return await callback();
  } catch (e, stack) {
    CrashReportService.instance.report(
      errorType: e.runtimeType.toString(),
      errorMessage: e.toString(),
      stackTrace: stack.toString(),
      screen: currentScreen,
      action: actionName,
      severity: severity,
    );
    if (showToast && context.mounted) {
      showMotoGoToast(
        context,
        icon: '⚠️',
        title: t(context).tr('error'),
        message: t(context).tr('tryAgainPlease'),
      );
    }
    return null;
  }
}

/// Reports a non-fatal event (warning/info) without showing UI.
/// Use for logging unusual but non-breaking situations.
void reportWarning(
  String action,
  String message, {
  Map<String, dynamic>? extra,
}) {
  CrashReportService.instance.report(
    errorType: 'warning',
    errorMessage: message,
    screen: currentScreen,
    action: action,
    severity: CrashSeverity.warning,
    extra: extra,
  );
}

String? _safeUserId() {
  try {
    return CrashReportService.instance._appVersion;
  } catch (_) {
    return null;
  }
}
