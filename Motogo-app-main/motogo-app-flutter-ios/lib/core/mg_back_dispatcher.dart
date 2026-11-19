import 'package:flutter/animation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Systémové „Zpět“ (Android) appku NIKDY nezavře — zadání majitele
/// 2026-11-15: „vždycky mě to vrátí jen o krok zpátky, nebo při nejhorším na
/// horní stranu stránky Domů“.
///
/// Pořadí: obrazovky s vlastním `BackButtonListener` (listy, platby…) →
/// go_router (zavře list/dialog, o krok zpět) → když už není kam couvnout:
/// mimo Domů přejde na Domů, na Domů vyjede nahoru, nahoře na Domů nic.
class MgBackButtonDispatcher extends RootBackButtonDispatcher {
  MgBackButtonDispatcher(this._router);
  final GoRouter _router;

  @override
  Future<bool> didPopRoute() async {
    if (await super.didPopRoute()) return true;
    mgRootBack(_router);
    return true;
  }
}

/// Posuvník stránky Domů (oba vzhledy si ho sem zapíšou v initState a v
/// dispose ho uvolní) — „Zpět“ na kořeni Domů ho vyjede nahoru.
ScrollController? mgHomeScroll;

/// „Zpět“, když už není kam couvnout.
void mgRootBack(GoRouter router) {
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path != '/') {
    router.go('/');
    return;
  }
  final c = mgHomeScroll;
  if (c != null && c.hasClients && c.offset > 0) {
    c.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }
}

/// `MaterialApp.router(onNavigationNotification:)` — appka vždy hlásí
/// Androidu, že „Zpět“ obslouží sama. Jinak by ho Android 14+ (prediktivní
/// zpět, `enableOnBackInvokedCallback`) na kořeni záložky vyřídil sám
/// zavřením appky a k [MgBackButtonDispatcher] by se vůbec nedostal.
bool mgClaimBack(NavigationNotification notification) {
  final s = WidgetsBinding.instance.lifecycleState;
  if (s == null || s == AppLifecycleState.detached) return true;
  SystemNavigator.setFrameworkHandlesBack(true);
  return true;
}
