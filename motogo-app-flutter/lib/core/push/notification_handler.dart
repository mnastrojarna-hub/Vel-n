import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import '../router.dart';
import 'push_service.dart';

/// Notification handler — connects PushService to UI.
/// Shows in-app banners for foreground notifications,
/// handles deep link routing on notification tap.
class NotificationHandler {
  NotificationHandler._();

  static GlobalKey<NavigatorState>? _navKey;

  /// Initialize with navigator key for routing.
  static void initialize(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;

    PushService.setHandlers(
      onReceived: _showInAppBanner,
      onTap: _handleDeepLink,
    );
  }

  /// Show in-app banner for foreground notifications.
  /// Mirrors showMsgNotification() from messages-ui.js.
  static void _showInAppBanner(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    final context = _navKey?.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('📩', style: TextStyle(fontSize: 19)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: MotoGoColors.dark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Zobrazit',
          textColor: MotoGoColors.green,
          onPressed: () => _handleDeepLink(data),
        ),
      ),
    );
  }

  /// Handle notification tap — route to appropriate screen.
  /// Mirrors deep link routing from native-bridge.js.
  static void _handleDeepLink(Map<String, dynamic> data) {
    final context = _navKey?.currentContext;
    if (context == null) return;

    final type = data['type'] as String?;
    final id = data['id'] as String?;

    switch (type) {
      case 'booking':
        if (id != null) context.push('/reservations/$id');
        break;
      case 'sos':
        context.push(Routes.sos);
        break;
      case 'message':
        if (id != null) {
          context.push('/messages/$id');
        } else {
          context.push(Routes.messages);
        }
        break;
      case 'shop_order':
        context.push(Routes.shop);
        break;
      default:
        context.push(Routes.messages);
    }
  }
}
