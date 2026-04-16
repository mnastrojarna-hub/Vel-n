import 'package:flutter/material.dart';

import 'debug_logger.dart';
import 'safe_action.dart';

/// Navigation observer that automatically logs every screen transition.
/// Attach to GoRouter or MaterialApp.router for automatic tracking.
class DebugNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
    if (name != null) {
      currentScreen = name;
      AppDebugLogger.instance.screen(name);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(previousRoute);
    if (name != null) {
      currentScreen = name;
      AppDebugLogger.instance.log(
        LogCategory.navigation, 'pop',
        detail: '${_routeName(route)} → $name',
      );
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = _routeName(newRoute);
    if (name != null) {
      currentScreen = name;
      AppDebugLogger.instance.log(
        LogCategory.navigation, 'replace',
        detail: '${_routeName(oldRoute)} → $name',
      );
    }
  }

  String? _routeName(Route<dynamic>? route) {
    return route?.settings.name;
  }
}
