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
import 'core/currency.dart';
import 'core/crash_report_service.dart';
import 'core/debug_logger.dart';
import 'core/installation_service.dart';
import 'core/offline_guard.dart';
import 'core/push/push_service.dart';
import 'core/push/notification_handler.dart';
import 'core/native/permission_service.dart';
import 'core/supabase_client.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/i18n/i18n_provider.dart';
import 'core/overlays/onboarding_overlays.dart';
import 'core/widgets/moto_fx.dart';
import 'core/update_check_provider.dart';
import 'core/in_app_update_service.dart';
import 'core/widgets/logo_header.dart' show initAppVersion;
import 'features/loyalty/loyalty_levelup_overlay.dart';
import 'features/routes/active_ride_provider.dart'
    show maybeResumeActiveRideOnLaunch;

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

  // Detect an app update (version+build changed) and, if so, wipe every
  // on-disk cache BEFORE anything loads — this guarantees the app never shows
  // the previous version after a Google Play update. Login session is kept.
  await CacheCleanupService.purgeIfUpdated();

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

  // Měna (CZK/EUR/PLN, parita s webem): načti volbu + kurzy z cache,
  // čerstvé kurzy ČNB dotáhni na pozadí (cache 15 min, fallback chain).
  final langPrefs = await SharedPreferences.getInstance();
  await Money.init(defaultLang: langPrefs.getString('mg_language'));
  unawaited(Money.refreshRates());

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
  bool _showIntro = false;
  bool _onboardingChecked = false;
  StreamSubscription<AuthState>? _authSub;

  static const _introShownKey = 'mg_intro_shown';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboarding();
    _listenAuthExpiration();
    _initPush();
    _initOfflineGuard();
    _resumeActiveRide();
  }

  /// Rozjetá trasa (nezavřená křížkem) → po startu appky se otevře zpět
  /// navigace na ní. Persistence viz features/routes/active_ride_provider.dart.
  void _resumeActiveRide() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeResumeActiveRideOnLaunch(rootNavigatorKey);
    });
  }

  /// Initialize push notifications + notification handler.
  Future<void> _initPush() async {
    try {
      await PushService.initialize();
      NotificationHandler.initialize(rootNavigatorKey);
      // Mirror OS permission grants to the profile (Velín customer detail).
      await PermissionService.reportToProfile();
      // Record this installation for accurate app analytics (independent of
      // push consent). Non-blocking, throttled, swallows errors.
      await InstallationService.beat();
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
          InAppUpdateService.check(ctx);
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
    } else if (state == AppLifecycleState.resumed) {
      // Refresh installation heartbeat on resume (throttled internally).
      InstallationService.beat();
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

      // Right after sign-in we have a user → record the installation so a
      // freshly logged-in device shows up in app analytics immediately.
      if (event == AuthChangeEvent.signedIn) {
        InstallationService.beat();
      }

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
    final prefs = await SharedPreferences.getInstance();
    final introShown = prefs.getBool(_introShownKey) ?? false;
    if (mounted) {
      setState(() {
        _showLangOverlay = showLang;
        _showPermOverlay = !showLang && showPerm;
        // Intro (logo + přejezd motorky) jen při úplně prvním spuštění.
        _showIntro = !introShown;
        _onboardingChecked = true;
      });
    }
  }

  Future<void> _onIntroDone() async {
    setState(() => _showIntro = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introShownKey, true);
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
      // Sdílený seznam z i18n_provider.dart — musí obsahovat VŠECHNY jazyky
      // z pickeru (vč. 'uk'), jinak Flutter locale resolvuje fallbackem na cs
      // a přepnutí jazyka se v UI neprojeví.
      supportedLocales: supportedLocales,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Stack(
            children: [
              child!,
              // Věrnostní ranky — neviditelný hlídač postupu na vyšší level.
              // Sedí NAD celou navigací, takže celoobrazovkovou oslavu
              // (postup o 1 = standard, o 2+ = turbo „MEGA POSTUP") zobrazí
              // na jakékoli obrazovce — i mimo spodní lištu (login, platba,
              // „success" potvrzení rezervace…).
              const LoyaltyLevelUpWatcher(),
              // Language selection overlay (first launch)
              if (_onboardingChecked && _showLangOverlay)
                LanguageOverlay(onDone: _onLangDone),
              // Permission request overlay (after language)
              if (_onboardingChecked && _showPermOverlay)
                PermissionOverlay(
                  onAllow: _onPermDone,
                ),
              // Intro animace při prvním spuštění — NAD ostatními overlayi,
              // po doběhnutí odhalí výběr jazyka.
              if (_onboardingChecked && _showIntro)
                MotoIntroOverlay(onDone: _onIntroDone),
            ],
          ),
        );
      },
    );
  }
}
