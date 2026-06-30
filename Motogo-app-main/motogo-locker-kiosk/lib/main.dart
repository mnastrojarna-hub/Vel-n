import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config.dart';
import 'theme.dart';
import 'services/code_cache.dart';
import 'services/diag.dart';
import 'services/kiosk_storage.dart';
import 'services/updater.dart';
import 'screens/kiosk_screen.dart';
import 'screens/setup_screen.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Pády frameworku → vzdálená diagnostika (kiosk_logs)
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      KioskDiag.crash('flutter', details.exceptionAsString(),
          {'library': details.library ?? ''});
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      KioskDiag.crash('platform', error.toString(), {'stack': stack.toString()});
      return true;
    };

    // Kiosk: landscape, fullscreen immersive, obrazovka stále zapnutá
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await WakelockPlus.enable();

    await Supabase.initialize(
      url: KioskConfig.supabaseUrl,
      anonKey: KioskConfig.supabaseAnonKey,
    );

    // Verze appky (OTA porovnání + diagnostika)
    try {
      final info = await PackageInfo.fromPlatform();
      KioskDiag.appVersion = '${info.version}+${info.buildNumber}';
      Updater.instance.currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {}

    await KioskStorage.instance.load();
    await CodeCache.instance.load();

    runApp(const KioskApp());
  }, (error, stack) {
    KioskDiag.crash('zone', error.toString(), {'stack': stack.toString()});
  });
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoGo24 — Pobočka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: MG.gradientTop,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MG.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  Widget build(BuildContext context) {
    if (!KioskStorage.instance.isConfigured) {
      return SetupScreen(onDone: () => setState(() {}));
    }
    return const KioskScreen();
  }
}
