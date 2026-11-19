// 5.0.2: Android „Zpět“ NIKDY nezavře appku (majitel 2026-11-15) — o krok
// zpět, z jiné záložky na Domů, na Domů nahoru, nahoře na Domů nic.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/mg_back_dispatcher.dart';
import 'package:motogo_app/core/safe_router_config.dart';

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _c = ScrollController();
  @override
  void initState() {
    super.initState();
    mgHomeScroll = _c;
  }

  @override
  void dispose() {
    if (identical(mgHomeScroll, _c)) mgHomeScroll = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListView(controller: _c, children: [for (var i = 0; i < 60; i++) SizedBox(height: 80, child: Text('home $i'))]);
}

void main() {
  late GoRouter router;
  late List<MethodCall> calls;

  Future<void> pumpApp(WidgetTester t) async {
    calls = [];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      calls.add(c);
      return null;
    });
    router = GoRouter(routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const _Home()),
          GoRoute(
            path: '/routes',
            builder: (_, __) => const Text('routes'),
            routes: [GoRoute(path: 'x', builder: (_, __) => const Text('route x'))],
          ),
        ],
      ),
      GoRoute(path: '/booking', builder: (_, __) => const Scaffold(body: Text('booking'))),
    ]);
    await t.pumpWidget(MaterialApp.router(routerConfig: mgSafeRouterConfig(router), onNavigationNotification: mgClaimBack));
    await t.pumpAndSettle();
  }

  Future<bool> back(WidgetTester t) async {
    // ignore: invalid_use_of_protected_member
    final handled = await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    return handled;
  }

  String loc() => router.routerDelegate.currentConfiguration.uri.path;
  bool closed() => calls.any((c) => c.method == 'SystemNavigator.pop');

  testWidgets('Domů nahoře: nic, appka se nezavře', (t) async {
    await pumpApp(t);
    expect(await back(t), isTrue);
    expect(loc(), '/');
    expect(closed(), isFalse);
  });

  testWidgets('Domů posunutá: vyjede nahoru', (t) async {
    await pumpApp(t);
    mgHomeScroll!.jumpTo(1500);
    await t.pump();
    expect(await back(t), isTrue);
    expect(mgHomeScroll!.offset, 0);
    expect(closed(), isFalse);
  });

  testWidgets('kořen jiné záložky → Domů', (t) async {
    await pumpApp(t);
    router.go('/routes');
    await t.pumpAndSettle();
    expect(await back(t), isTrue);
    expect(loc(), '/');
    expect(closed(), isFalse);
  });

  testWidgets('vnořená stránka → o krok zpět', (t) async {
    await pumpApp(t);
    router.go('/routes');
    await t.pumpAndSettle();
    router.push('/routes/x');
    await t.pumpAndSettle();
    expect(await back(t), isTrue);
    expect(loc(), '/routes');
    expect(find.text('routes'), findsOneWidget);
    expect(closed(), isFalse);
  });

  testWidgets('stránka mimo menu otevřená přes go → Domů', (t) async {
    await pumpApp(t);
    router.go('/booking');
    await t.pumpAndSettle();
    expect(await back(t), isTrue);
    expect(loc(), '/');
    expect(closed(), isFalse);
  });

  testWidgets('otevřený dialog se zavře, stránka zůstane', (t) async {
    await pumpApp(t);
    showDialog<void>(context: router.routerDelegate.navigatorKey.currentContext!, builder: (_) => const Text('dlg'));
    await t.pumpAndSettle();
    expect(find.text('dlg'), findsOneWidget);
    expect(await back(t), isTrue);
    expect(find.text('dlg'), findsNothing);
    expect(loc(), '/');
    expect(closed(), isFalse);
  });

  testWidgets('Androidu se vždy hlásí, že Zpět obslouží appka', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpApp(t);
    router.go('/routes');
    await t.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    final claims = calls.where((c) => c.method == 'SystemNavigator.setFrameworkHandlesBack').map((c) => c.arguments);
    expect(claims, isNotEmpty);
    expect(claims.every((a) => a == true), isTrue);
  });
}
