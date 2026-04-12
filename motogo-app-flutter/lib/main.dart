import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_guard.dart';
import 'core/cache_cleanup_service.dart';
import 'core/supabase_client.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/i18n/i18n_provider.dart';
import 'core/overlays/onboarding_overlays.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show red error screen with details instead of blank green screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              Text(details.exceptionAsString(), style: const TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(details.stack.toString(), style: const TextStyle(fontSize: 9, color: Colors.black54)),
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
  try {
    await Stripe.instance.applySettings();
  } catch (_) {
    // Stripe native init may fail (missing Google Play, emulator, etc.)
    // Payment Sheet will re-apply settings before use.
  }

  await Supabase.initialize(
    url: MotoGoSupabase.url,
    anonKey: MotoGoSupabase.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );

  // Cleanup leftover cache/temp from previous session (safety net)
  await CacheCleanupService.run();

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      CacheCleanupService.run();
    }
  }

  /// Global listener: when the session expires or token refresh fails,
  /// force sign-out so the router redirects to login.
  void _listenAuthExpiration() {
    _authSub = MotoGoSupabase.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      // Session gone (expired / revoked) → ensure clean sign-out
      if (event == AuthChangeEvent.signedOut) return; // already handled

      // If we get a token-refreshed event but the session is null or expired,
      // force sign-out.
      if (session == null && event == AuthChangeEvent.tokenRefreshed) {
        MotoGoSupabase.client.auth.signOut();
      }

      // Check if the current session's access token is already expired.
      if (session != null && session.expiresAt != null) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt! * 1000,
        );
        if (DateTime.now().isAfter(expiresAt)) {
          MotoGoSupabase.client.auth.signOut();
        }
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
