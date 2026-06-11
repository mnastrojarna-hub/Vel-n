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
  /// Door code notifications get a prominent green banner.
  static void _showInAppBanner(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    final context = _navKey?.currentContext;
    if (context == null) return;

    final isDoorCodes = data['type'] == 'door_codes';
    final emoji = isDoorCodes ? '🔑' : '📩';
    final bgColor = isDoorCodes ? const Color(0xFF1A2E22) : MotoGoColors.dark;
    final duration = isDoorCodes ? 8 : 5;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 19)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isDoorCodes ? 14 : 13,
                      fontWeight: isDoorCodes ? FontWeight.w900 : FontWeight.w700,
                      color: isDoorCodes ? MotoGoColors.green : Colors.white,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: isDoorCodes ? 0.8 : 0.5),
                      ),
                      maxLines: isDoorCodes ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isDoorCodes
              ? const BorderSide(color: MotoGoColors.green, width: 1.5)
              : BorderSide.none,
        ),
        duration: Duration(seconds: duration),
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
      case 'door_codes':
        // Door codes notification → go to messages to see the codes
        context.push(Routes.messages);
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
