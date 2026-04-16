import 'package:flutter/material.dart';

import '../crash_report_service.dart';
import '../safe_action.dart';
import '../theme.dart';

/// Error boundary widget — catches build/render errors in child tree.
///
/// Wraps a screen or widget subtree. If the child throws during build,
/// shows a friendly "something went wrong" UI instead of crashing.
/// Simultaneously logs the full error to Supabase via CrashReportService.
///
/// Usage:
/// ```dart
/// ErrorBoundary(
///   screen: 'home',
///   child: HomeScreen(),
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final String screen;

  const ErrorBoundary({
    super.key,
    required this.child,
    required this.screen,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  String? _errorMessage;

  @override
  void didUpdateWidget(covariant ErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset error state when screen changes
    if (oldWidget.screen != widget.screen && _hasError) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  void _onError(FlutterErrorDetails details) {
    // Log to Supabase
    CrashReportService.instance.report(
      errorType: 'RenderError',
      errorMessage: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
      screen: widget.screen,
      action: 'build',
      severity: CrashSeverity.critical,
      extra: {
        'library': details.library,
        'context': details.context?.toString(),
      },
    );

    // Show friendly UI
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = details.exceptionAsString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _FriendlyErrorWidget(
        screen: widget.screen,
        onRetry: () {
          setState(() {
            _hasError = false;
            _errorMessage = null;
          });
        },
      );
    }

    // Set current screen for crash reports
    currentScreen = widget.screen;

    return _ErrorCatcher(
      onError: _onError,
      child: widget.child,
    );
  }
}

/// Internal widget that catches errors during build.
class _ErrorCatcher extends StatelessWidget {
  final Widget child;
  final void Function(FlutterErrorDetails) onError;

  const _ErrorCatcher({required this.child, required this.onError});

  @override
  Widget build(BuildContext context) {
    // Wrap child in a Builder to catch build errors
    return Builder(
      builder: (context) {
        // Override error widget for this subtree
        ErrorWidget.builder = (details) {
          // Report asynchronously — don't block error widget rendering
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onError(details);
          });
          // Return minimal placeholder while error is being handled
          return const SizedBox.shrink();
        };
        return child;
      },
    );
  }
}

/// User-friendly error screen — clean, reassuring UI.
/// The user only sees "something went wrong, try refreshing".
class _FriendlyErrorWidget extends StatelessWidget {
  final String screen;
  final VoidCallback onRetry;

  const _FriendlyErrorWidget({
    required this.screen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: MotoGoColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text('🔄', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Něco se pokazilo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MotoGoColors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Omlouváme se za komplikace. Zkuste to prosím znovu.',
                style: TextStyle(
                  fontSize: 13,
                  color: MotoGoColors.g400,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                ),
                child: const Text(
                  'Zkusit znovu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
