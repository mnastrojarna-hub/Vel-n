import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_guard.dart';
import 'core/cache_cleanup_service.dart';
import 'core/currency.dart';
import 'core/crash_report_service.dart';
import 'core/debug_logger.dart';
import 'core/installation_service.dart';
import 'core/net/timeout_client.dart';
import 'core/engagement_service.dart';
import 'core/offline_guard.dart';
import 'core/provider_recovery.dart';
import 'core/push/push_service.dart';
import 'core/push/notification_handler.dart';
import 'core/native/permission_service.dart';
import 'core/supabase_client.dart';
import 'core/router.dart';
import 'core/safe_router_config.dart';
import 'core/theme.dart';
import 'core/i18n/i18n_provider.dart';
import 'core/overlays/onboarding_overlays.dart';
import 'core/widgets/moto_fx.dart';
import 'core/update_check_provider.dart';
import 'core/in_app_update_service.dart';
import 'core/widgets/logo_header.dart' show initAppVersion;
import 'core/pending_booking_fab_provider.dart'
    show onboardingOverlayActiveProvider;
import 'features/loyalty/loyalty_levelup_overlay.dart';
import 'features/routes/ride_recorder.dart';
import 'features/loyalty/loyalty_provider.dart' show maybeRefreshLoyalty;
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

  // Show friendly error widget instead of red screen — s akcí Zpět / Domů
  // (dřív jen „Restartujte aplikaci" bez cesty ven).
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Report build error
    CrashReportService.instance.reportFlutterError(details);
    // Bez BuildContextu s lokalizací → poslední známý jazyk appky.
    final tr = AppTranslations.of(lastKnownAppLang);
    return Material(
      color: const Color(0xFFDFF0EC), // MotoGoColors.bg
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔄', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 12),
              Text(tr.tr('eoCrashTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2E22))),
              const SizedBox(height: 6),
              Text(tr.tr('eoCrashBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B8F7B))),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                  onPressed: () => rootNavigatorKey.currentState?.maybePop(),
                  child: Text(tr.tr('eoBack')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.green, foregroundColor: Colors.black),
                  onPressed: () {
                    final ctx = rootNavigatorKey.currentContext;
                    if (ctx != null) GoRouter.of(ctx).go('/');
                  },
                  child: Text(tr.tr('eoHome')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Android 15 (SDK 35): zobrazení bez okrajů (edge-to-edge) je výchozí.
  // Explicitně ho zapneme, aby se appka chovala správně i na starších verzích,
  // a systémové lišty necháme PRŮHLEDNÉ. Tím se vyhneme zastaralým API
  // Window.setStatusBarColor / setNavigationBarColor (Google Play warning) —
  // neprůhledná barva (dříve černá nav lišta) je totiž volala.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
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
    // Časový limit na každý požadavek — žádné nekonečné točení na zaseklém
    // signálu (viz core/net/timeout_client.dart).
    httpClient: TimeoutClient(http.Client()),
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
  await Money.init(
      defaultLang: langPrefs.getString('mg_language') ?? langPrefs.getString('mg_locale'));
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
    EngagementService.start(); // Velín → App funnel (návštěvy)
    _checkOnboarding();
    _listenAuthExpiration();
    _initPush();
    _initOfflineGuard();
    _resumeActiveRide();
    // Připojení zpět → data, která zůstala v chybě, se načtou znovu sama.
    OfflineGuard.onBackOnline = () {
      if (mounted) recoverFailedProviders(ref);
    };
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
    // Lišta + odznak na ikoně: otevřením appky zákazník upozornění viděl
    // (PŘED initialize — ta bez oprávnění k notifikacím končí dřív).
    PushService.clearDelivered();
    try {
      // Handlery PŘED initialize — klepnutí na notifikaci při studeném startu
      // (getInitialMessage) se jinak ztratilo a appka otevřela jen Domů.
      NotificationHandler.initialize(rootNavigatorKey);
      await PushService.initialize();
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
    // Velín → App funnel: návštěva = ≥5 s v popředí + dotyk (engagement_service).
    EngagementService.onLifecycle(state);

    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      // Flush all logs + crash reports before app goes to background
      AppDebugLogger.instance.flushNow();
      CrashReportService.instance.flushNow();
      CacheCleanupService.run();
    } else if (state == AppLifecycleState.resumed) {
      // Refresh installation heartbeat on resume (throttled internally).
      InstallationService.beat();
      PushService.clearDelivered(); // návrat do appky = upozornění viděno
      // Oznámení mohl zákazník mezitím povolit v Nastavení → zaregistrovat
      // token (idempotentní, bez změny nic nezapisuje).
      unawaited(PushService.initialize().catchError((_) {}));
      // Chyby z doby na pozadí (bez signálu) → načíst znovu.
      recoverFailedProviders(ref);
      // Re-run the forced-update gate + Play in-app update on resume —
      // an app kept open for days must not survive below min_app_version.
      // Both checks throttle themselves internally.
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        UpdateChecker.check(ctx);
        InAppUpdateService.check(ctx);
      }
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

      if (event == AuthChangeEvent.signedOut) {
        // Obnova přihlášení selhala (neplatný / zneplatněný token) → přihlašovací
        // obrazovka jednou vysvětlí, proč zákazník musí znovu přihlásit.
        if (data.signOutReason == SignOutReason.sessionExpired) {
          ForcedSignOut.pending = true;
        }
        return; // already handled
      }

      // Right after sign-in we have a user → record the installation so a
      // freshly logged-in device shows up in app analytics immediately.
      if (event == AuthChangeEvent.signedIn) {
        InstallationService.beat();
        // Token notifikací patří k uživateli — bez přihlášení se nezapsal.
        unawaited(PushService.initialize().catchError((_) {}));
      }

      // Token refresh attempt produced no session → refresh token is invalid
      // or revoked. This is the one case where we must force sign-out so the
      // router can redirect to login.
      if (event == AuthChangeEvent.tokenRefreshed && session == null) {
        ForcedSignOut.pending = true;
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
    // Oprávnění k oznámením se udělilo až teď (po startu) → push zapnout hned,
    // ne až po restartu appky.
    unawaited(PushService.initialize()
        .then((_) => PermissionService.reportToProfile())
        .catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'MotoGo24',
      debugShowCheckedModeBanner: false,
      theme: MotoGoTheme.dark,
      // GoRouter + ochrana před odkazy s vlastním schématem (návrat ze
      // Stripe 3DS `motogo24://payment`) — viz safe_router_config.dart.
      routerConfig: mgSafeRouterConfig(router),
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
        // App-level overlaye (jazyk / oprávnění / intro) jsou v tomto Stacku
        // AŽ ZA `child!`, takže se kreslí NAD dialogem level-up oslavy. Dokud
        // je některý vidět (nebo onboarding ještě není vyhodnocený), hlídač
        // oslavu ODLOŽÍ — nic si nezapíše, takže se dožene hned po zavření.
        final overlayUp = !_onboardingChecked ||
            _showLangOverlay ||
            _showPermOverlay ||
            _showIntro;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final n = ref.read(onboardingOverlayActiveProvider.notifier);
          if (n.state != overlayUp) n.state = overlayUp;
        });
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          // Každý dotyk = levná kontrola věrnostního ranku (throttle 45 s je
          // v `maybeRefreshLoyalty`). Díky tomu zákazník uvidí oslavu i když
          // povýšení nastalo server-side, zatímco měl appku otevřenou —
          // stačí, že na cokoli klikne. `Listener` nic nepohlcuje ani
          // nemění layout, takže UX/UI/flow zůstává beze změny.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              maybeRefreshLoyalty(ref);
              EngagementService.onUserPointer(); // Velín → App funnel (návštěva)
            },
            child: Stack(
              children: [
                child!,
                // Věrnostní ranky — neviditelný hlídač postupu na vyšší level.
                // Sedí NAD celou navigací, takže celoobrazovkovou oslavu
                // (postup o 1 = standard, o 2+ = turbo „MEGA POSTUP") zobrazí
                // na jakékoli obrazovce — i mimo spodní lištu (login, platba,
                // „success" potvrzení rezervace…).
                const LoyaltyLevelUpWatcher(),
                // Záznam projeté jízdy — při aktivní výpůjčce a povolené
                // poloze sbírá stopu do „Mých zážitků". Nic nevykresluje.
                const RideRecorderWatcher(),
                // Language selection overlay (first launch)
                if (_onboardingChecked && _showLangOverlay)
                  LanguageOverlay(onDone: _onLangDone),
                // Permission request overlay (after language)
                if (_onboardingChecked && _showPermOverlay)
                  PermissionOverlay(
                    onAllow: _onPermDone,
                    onSkip: _onPermDone,
                    // ← / systémové zpět → zpět na výběr jazyka.
                    onBack: () => setState(() {
                      _showPermOverlay = false;
                      _showLangOverlay = true;
                    }),
                  ),
                // Intro animace při prvním spuštění — NAD ostatními overlayi,
                // po doběhnutí odhalí výběr jazyka.
                if (_onboardingChecked && _showIntro)
                  MotoIntroOverlay(onDone: _onIntroDone),
              ],
            ),
          ),
        );
      },
    );
  }
}
