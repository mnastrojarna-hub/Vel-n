import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Rodič obrazovky pro systémové „zpět", když není kam popnout (obrazovka
/// otevřená přes `context.go`, záložku, push notifikaci nebo deep link).
/// null = kořen (Domů / přihlášení) → „zpět" appku zavře (konvence Androidu).
String? mgBackParent(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path.isEmpty || path == '/' || path == '/login') return null;
  final s = path.split('/').where((p) => p.isNotEmpty).toList();
  final first = s.first;
  switch (first) {
    case 'register':
    case 'reset-password':
      return '/login';
    case 'search':
    case 'profile':
    case 'ai-agent':
      return '/';
    case 'reservations':
      if (s.length == 1) return '/';
      if (s.length == 2) return '/reservations';
      return '/reservations/${s[1]}'; // /edit, /done → detail
    case 'sos':
      if (s.length == 1) return '/';
      if (s[1] == 'done') return '/';
      return '/sos';
    case 'messages':
      return s.length == 1 ? '/profile' : '/messages';
    case 'shop':
      return s.length == 1 ? '/profile' : '/shop';
    case 'cart':
    case 'voucher':
      return '/shop';
    case 'checkout':
      return '/cart';
    case 'pobocky':
      return s.length == 1 ? '/profile' : '/pobocky';
    case 'docs':
      return s.length == 1 ? '/profile' : '/docs';
    case 'invoices':
    case 'contracts':
    case 'permissions':
    case 'loyalty':
      return '/profile';
    case 'moto':
    case 'booking':
      return '/search';
    case 'payment':
    case 'success':
    case 'payment-result':
      return '/reservations';
    case 'routes':
      return s.length == 1 ? '/' : '/routes-list';
    case 'routes-list':
    case 'places-map':
    case 'pois':
    case 'my-experiences':
    case 'route-build':
    case 'route-nav-custom':
      return '/routes';
    case 'routes-map':
      return '/routes-list';
    case 'route-nav':
      return s.length > 1 ? '/routes/${s[1]}' : '/routes';
    case 'ride':
      return '/my-experiences';
    default:
      return '/';
  }
}

/// Aktuální poloha routeru (i pro obrazovky otevřené přes push).
String mgCurrentLocation(GoRouter router) {
  try {
    return router.routerDelegate.currentConfiguration.last.matchedLocation;
  } catch (_) {
    try {
      return router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '/';
    }
  }
}

/// Systémové „zpět" (Android tlačítko / gesto) na obrazovce, pod kterou v
/// zásobníku nic není: místo zavření appky přejde na rodiče ([mgBackParent]).
///
/// go_router 13 v té situaci `PopScope` obrazovky vůbec nezavolá a appka se
/// zavře. Proto: `PopScope(canPop:false)` (ať „zpět" převezme Flutter, ne OS —
/// prediktivní gesto) + `BackButtonListener`. Když je kam popnout, nic
/// nepřebírá — normální zpět i iOS swipe zůstávají beze změny.
///
/// [shell] = obal obsahu AppShellu: před přechodem na rodiče dá šanci
/// vlastnímu `PopScope` viditelné obrazovky (potvrzovací dialogy apod.).
/// Obrazovky s vlastním `BackButtonListener` mají přednost (registrují se později).
class MgBackGuard extends StatefulWidget {
  final Widget child;
  final bool shell;
  final String? parent;
  const MgBackGuard({super.key, required this.child, this.shell = false, this.parent});

  @override
  State<MgBackGuard> createState() => _MgBackGuardState();
}

class _MgBackGuardState extends State<MgBackGuard> {
  NavigatorState? _innerNavigator(GoRouter router) {
    try {
      RouteMatchBase walker = router.routerDelegate.currentConfiguration.matches.last;
      NavigatorState? found;
      while (walker is ShellRouteMatch) {
        found = walker.navigatorKey.currentState ?? found;
        walker = walker.matches.last;
      }
      return found;
    } catch (_) {
      return null;
    }
  }

  // Metoda (ne closure z buildu) → stabilní reference, takže překreslení
  // shellu nepřebere prioritu obrazovkám s vlastním BackButtonListenerem.
  Future<bool> _onBack() async {
    if (!mounted) return false;
    final GoRouter router;
    try {
      router = GoRouter.of(context);
    } catch (_) {
      return false;
    }
    if (router.canPop()) return false; // běžné zpět (stránka, sheet, dialog)
    if (widget.shell) {
      final inner = _innerNavigator(router);
      if (inner != null && await inner.maybePop()) return true;
      if (!mounted) return true;
    }
    final loc = mgCurrentLocation(router);
    final parent = widget.parent ?? mgBackParent(loc);
    if (parent == null || parent == loc) return false;
    router.go(parent);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool allowPop;
    if (widget.shell) {
      String loc = '/';
      try {
        loc = GoRouterState.of(context).matchedLocation;
      } catch (_) {}
      allowPop = (widget.parent ?? mgBackParent(loc)) == null;
    } else {
      allowPop = (ModalRoute.of(context)?.canPop ?? true) ||
          widget.parent == null && _rootParentNull(context);
    }
    return PopScope(
      canPop: allowPop,
      child: BackButtonListener(onBackButtonPressed: _onBack, child: widget.child),
    );
  }

  bool _rootParentNull(BuildContext context) {
    try {
      return mgBackParent(GoRouterState.of(context).matchedLocation) == null;
    } catch (_) {
      return true;
    }
  }
}

/// true = obrazovka s [context] je nahoře (nad ní není jiná trasa ani dialog
/// / sheet). Jen pak smí vlastní `BackButtonListener` převzít systémové zpět.
bool mgIsTopmost(BuildContext context) {
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
  var popupOnTop = false;
  Navigator.of(context, rootNavigator: true).popUntil((r) {
    popupOnTop = r is PopupRoute;
    return true; // jen nahlédnout na vrchol, nic nezavírat
  });
  return !popupOnTop;
}
