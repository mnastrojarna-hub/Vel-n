import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../debug_logger.dart';
import '../i18n/i18n_provider.dart';
import '../theme.dart';
import '../v2/flag/v2_scope.dart';
import '../v2/states/mg_state_screen.dart';
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
    // v2 vzhled: výsledková obrazovka T1 se stejnými texty a akcí Domů.
    if (MgV2.on(context)) {
      return MgBackGuard(
        parent: '/',
        child: MgStateScreen(
          tone: MgTone.info,
          title: tr.tr('eoRouteTitle'),
          why: tr.tr('eoRouteBody'),
          onClose: home,
          closeIsBack: true,
          support: false,
          primary: MgStateAction(tr.tr('eoHome'), home),
        ),
      );
    }
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
