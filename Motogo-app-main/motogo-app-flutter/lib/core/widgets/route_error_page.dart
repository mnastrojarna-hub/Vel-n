import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../debug_logger.dart';
import '../i18n/i18n_provider.dart';
import '../theme.dart';
import 'mg_back.dart';
import 'state_views.dart';

/// Neznámý / zastaralý odkaz do appky (deep link, push, App Link
/// `https://motogo24.cz/app/…`). Dřív go_router ukázal anglickou stránku se
/// syrovou `GoException` bez cesty zpět.
class RouteErrorPage extends StatelessWidget {
  final GoRouterState state;
  const RouteErrorPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    try {
      AppDebugLogger.instance.log(LogCategory.navigation, 'unknown_route',
          detail: '${state.uri} ${state.error}');
    } catch (_) {}
    final tr = t(context);
    void home() => context.go('/');
    return MgBackGuard(
      parent: '/',
      child: MgStateScaffold(
        onBack: home,
        child: MgErrorView(
          what: tr.tr('eoRouteTitle'),
          message: tr.tr('eoRouteBody'),
          contact: false,
          extra: [
            ElevatedButton(
              onPressed: home,
              style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.green),
              child: Text(tr.tr('eoHome')),
            ),
          ],
        ),
      ),
    );
  }
}
