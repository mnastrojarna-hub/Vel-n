import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// RouterConfig appky = GoRouter + ochrana před odkazy s vlastním schématem.
///
/// Návrat ze Stripe ověření (3D Secure) přichází jako `motogo24://payment…`.
/// Flutter ho (deep linking je zapnutý kvůli App Links
/// `https://motogo24.cz/app/…`) předá běžící appce a go_router 13 na něm
/// spadne (`Uri.origin` umí jen http/https → StateError při každém návratu
/// z banky; ověřeno testem). Takový odkaz žádnou stránku neotevírá — platbu
/// dořeší Stripe SDK, takže zůstane aktuální obrazovka (rozdělaná platba se
/// nepřeruší). Studený start z odkazu řeší go_router sám (úvod `/`); pojistka
/// níže pro případ, že by cizí odkaz přišel dřív než první obrazovka.
RouterConfig<RouteMatchList> mgSafeRouterConfig(GoRouter router) =>
    _cache[router] ??= RouterConfig<RouteMatchList>(
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: MgSafeRouteParser(router),
      routerDelegate: router.routerDelegate,
      backButtonDispatcher: router.backButtonDispatcher,
    );

// Jedna instance na router — nová konfigurace při každém buildu by Routeru
// zahazovala rozpracované zpracování odkazu.
final Expando<RouterConfig<RouteMatchList>> _cache = Expando();

/// true = odkaz s vlastním schématem (ne http/https, ne prostá cesta).
@visibleForTesting
bool mgIsForeignSchemeLink(Uri uri) =>
    uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https';

class MgSafeRouteParser extends RouteInformationParser<RouteMatchList> {
  MgSafeRouteParser(this._router);
  final GoRouter _router;

  @override
  Future<RouteMatchList> parseRouteInformationWithDependencies(
    RouteInformation routeInformation,
    BuildContext context,
  ) {
    var info = routeInformation;
    if (mgIsForeignSchemeLink(info.uri)) {
      final current = _router.routerDelegate.currentConfiguration;
      if (current.isNotEmpty) return SynchronousFuture(current);
      info = RouteInformation(uri: Uri(path: '/'), state: info.state);
    }
    return _router.routeInformationParser
        .parseRouteInformationWithDependencies(info, context);
  }

  @override
  RouteInformation? restoreRouteInformation(RouteMatchList configuration) =>
      _router.routeInformationParser.restoreRouteInformation(configuration);
}
