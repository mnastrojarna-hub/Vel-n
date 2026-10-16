import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import '../router.dart';
import '../i18n/i18n_provider.dart';
import '../../features/reservations/reservation_provider.dart' show reservationsProvider;
import '../../features/sos/sos_provider.dart' show hasActiveRentalProvider;
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
          label: AppTranslations.of(lastKnownAppLang).tr('manualView'),
          textColor: MotoGoColors.green,
          onPressed: () => _handleDeepLink(data),
        ),
      ),
    );
  }

  /// Handle notification tap — route to appropriate screen.
  /// SOS jen při aktivní rezervaci — jinak Zprávy (odpověď centrály je i tam).
  static Future<void> _openSos(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(reservationsProvider.future).timeout(const Duration(seconds: 5));
    } catch (_) {}
    final ctx = _navKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ctx.push(container.read(hasActiveRentalProvider) ? Routes.sos : Routes.messages);
  }

  /// Klepnutí na notifikaci při studeném startu přijde dřív, než router
  /// projde přihlášením (start na /login → přesměrování na Domů). Počkáme, až
  /// je zákazník uvnitř appky — jinak by se otevřel jen úvod (max. 2 min).
  static Future<void> _deliverWhenReady(Map<String, dynamic> data) async {
    for (var i = 0; i < 240; i++) {
      final ctx = _navKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        String loc = Routes.login;
        try {
          loc = GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.path;
        } catch (_) {}
        final onAuth = loc == Routes.login ||
            loc == Routes.register ||
            loc == Routes.resetPassword;
        if (!onAuth) {
          _route(ctx, data);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Mirrors deep link routing from native-bridge.js.
  static void _handleDeepLink(Map<String, dynamic> data) {
    unawaited(_deliverWhenReady(data));
  }

  static void _route(BuildContext context, Map<String, dynamic> data) {

    final type = data['type'] as String?;
    final id = data['id'] as String?;

    switch (type) {
      case 'booking':
        if (id != null) context.push('/reservations/$id');
        break;
      case 'handover_protocol':
        // Předávací protokol (samoobslužná) → detail rezervace; vyplňuje se
        // jen na displeji pobočky, podepsané PDF je v dokumentech rezervace.
        if (id != null) context.push('/reservations/$id');
        break;
      case 'door_codes':
        // Door codes notification → go to messages to see the codes
        // (`id` = admin_messages.id → zprávu rozbalit a označit přečtenou)
        context.push(id != null ? '${Routes.messages}?n=$id' : Routes.messages);
        break;
      case 'sos':
        _openSos(context);
        break;
      case 'message':
        // `id` je admin_messages.id (trg_push_on_admin_message), NE id konverzace —
        // dřív se otevřel prázdný „chat“ a zpráva zůstala nepřečtená.
        context.push(id != null ? '${Routes.messages}?n=$id' : Routes.messages);
        break;
      case 'shop_order':
        context.push(Routes.shop);
        break;
      default:
        context.push(Routes.messages);
    }
  }
}
