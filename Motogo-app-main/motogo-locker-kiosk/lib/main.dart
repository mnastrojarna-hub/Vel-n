import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config.dart';
import 'theme.dart';
import 'services/kiosk_storage.dart';
import 'screens/kiosk_screen.dart';
import 'screens/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kiosk: landscape, fullscreen immersive, obrazovka stále zapnutá
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockPlus.enable();

  await Supabase.initialize(
    url: KioskConfig.supabaseUrl,
    anonKey: KioskConfig.supabaseAnonKey,
  );

  await KioskStorage.instance.load();

  runApp(const KioskApp());
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
