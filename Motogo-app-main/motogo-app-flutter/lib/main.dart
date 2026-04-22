import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_guard.dart';
import 'core/cache_cleanup_service.dart';
import 'core/crash_report_service.dart';
import 'core/debug_logger.dart';
import 'core/offline_guard.dart';
import 'core/push/push_service.dart';
import 'core/push/notification_handler.dart';
import 'core/supabase_client.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/i18n/i18n_provider.dart';
import 'core/overlays/onboarding_overlays.dart';
import 'core/update_check_provider.dart';
import 'core/widgets/logo_header.dart' show initAppVersion;

/// Global navigator key for notification deep links.
final rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Run entire app inside error-catching zone
  runZonedGuarded<Future<void>>(() async {
    await _initAndRun();
  }, (error, stack) {
    // Catch ALL unhandled async errors → push to Supabase
    CrashReportService.instance.reportException(
      error, stack,
      action: 'unhandled_async',
      severity: CrashSeverity.critical,
    );
  });
}

Future<void> _initAndRun() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter framework error handler → push to Supabase
  FlutterError.onError = (FlutterErrorDetails details) {
    CrashReportService.instance.reportFlutterError(details);
    // In debug mode, also print to console
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  // Catch platform errors (native crashes, isolate errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReportService.instance.reportException(
      error, stack,
      action: 'platform_error',
      severity: CrashSeverity.critical,
    );
    return true; // Handled
  };

  // Show friendly error widget instead of red screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Report build error
    CrashReportService.instance.reportFlutterError(details);
    return const Material(
      color: Color(0xFFDFF0EC), // MotoGoColors.bg
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🔄', style: TextStyle(fontSize: 36)),
              SizedBox(height: 12),
              Text('Restartujte aplikaci',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2E22))),
              SizedBox(height: 6),
              Text('Omlouváme se za komplikace.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B8F7B))),
            ],
          ),
        ),
      ),
    );
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Firebase (required for firebase_messaging)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized or unavailable — non-blocking
  }

  // Initialize Stripe — wrapped in try-catch so a native SDK failure
  // does not block the entire app from starting.
  Stripe.publishableKey = MotoGoSupabase.stripePublishableKey;
  Stripe.merchantIdentifier = 'merchant.cz.motogo24';
  Stripe.urlScheme = 'motogo24';
  debugPrint('[Stripe] publishableKey: ${Stripe.publishableKey.substring(0, 12)}...');
  debugPrint('[Stripe] urlScheme: ${Stripe.urlScheme}');
  try {
    await Stripe.instance.applySettings();
    debugPrint('[Stripe] applySettings at startup: OK');
  } catch (e) {
    debugPrint('[Stripe] applySettings at startup FAILED: $e');
    // Non-blocking — Payment Sheet will re-apply settings before use.
  }

  await Supabase.initialize(
    url: MotoGoSupabase.url,
    anonKey: MotoGoSupabase.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );

  // Initialize crash reporting + debug logging — must be after Supabase init
  await CrashReportService.instance.init();
  await AppDebugLogger.instance.init();

  // Cleanup leftover cache/temp from previous session (safety net)
  await CacheCleanupService.run();

  // Read version from pubspec.yaml at runtime (package_info_plus)
  await initAppVersion();

  runApp(const ProviderScope(child: MotoGoApp()));
}

class MotoGoApp extends ConsumerStatefulWidget {
  const MotoGoApp({super.key});

  @override
  ConsumerState<MotoGoApp> createState() => _MotoGoAppState();
}

class _MotoGoAppState extends ConsumerState<MotoGoApp>
    with WidgetsBindingObserver {
  bool _showLangOverlay = false;
  bool _showPermOverlay = false;
  bool _onboardingChecked = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboarding();
    _listenAuthExpiration();
    _initPush();
    _initOfflineGuard();
  }

  /// Initialize push notifications + notification handler.
  Future<void> _initPush() async {
    try {
      await PushService.initialize();
      NotificationHandler.initialize(rootNavigatorKey);
    } catch (_) {
      // Non-blocking — push is optional functionality
    }
  }

  /// Start offline connectivity watcher + update check after first frame.
  void _initOfflineGuard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) {
          OfflineGuard.startWatching(ctx);
          UpdateChecker.check(ctx);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    OfflineGuard.stopWatching();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Log every lifecycle change
    AppDebugLogger.instance.lifecycle(state.name);

    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      // Flush all logs + crash reports before app goes to background
      AppDebugLogger.instance.flushNow();
      CrashReportService.instance.flushNow();
      CacheCleanupService.run();
    }
  }

  /// Global listener: only force sign-out when Supabase itself reports that
  /// the refresh flow has failed. An expired access token on its own is NOT a
  /// reason to log the user out — the Supabase SDK refreshes it transparently
  /// via the refresh token (which lives far longer than the access token).
  void _listenAuthExpiration() {
    _authSub = MotoGoSupabase.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedOut) return; // already handled

      // Token refresh attempt produced no session → refresh token is invalid
      // or revoked. This is the one case where we must force sign-out so the
      // router can redirect to login.
      if (event == AuthChangeEvent.tokenRefreshed && session == null) {
        MotoGoSupabase.client.auth.signOut();
      }
    });
  }

  Future<void> _checkOnboarding() async {
    final showLang = await LanguageOverlay.shouldShow();
    final showPerm = await PermissionOverlay.shouldShow();
    if (mounted) {
      setState(() {
        _showLangOverlay = showLang;
        _showPermOverlay = !showLang && showPerm;
        _onboardingChecked = true;
      });
    }
  }

  Future<void> _onLangDone() async {
    final showPerm = await PermissionOverlay.shouldShow();
    setState(() {
      _showLangOverlay = false;
      _showPermOverlay = showPerm;
    });
  }

  Future<void> _onPermDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mg_perms_shown', true);
    setState(() => _showPermOverlay = false);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'MotoGo24',
      debugShowCheckedModeBanner: false,
      theme: MotoGoTheme.dark,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('cs'), Locale('en'), Locale('de'),
        Locale('es'), Locale('fr'), Locale('nl'), Locale('pl'),
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Stack(
            children: [
              child!,
              // Language selection overlay (first launch)
              if (_onboardingChecked && _showLangOverlay)
                LanguageOverlay(onDone: _onLangDone),
              // Permission request overlay (after language)
              if (_onboardingChecked && _showPermOverlay)
                PermissionOverlay(
                  onAllow: _onPermDone,
                  onSkip: _onPermDone,
                ),
            ],
          ),
        );
      },
    );
  }
}
