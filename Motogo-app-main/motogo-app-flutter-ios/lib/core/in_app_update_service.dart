import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import 'theme.dart';
import 'i18n/i18n_provider.dart';

/// Google Play In-App Updates (Android only).
///
/// Complements [UpdateChecker]: while the latter force-blocks below
/// `app_settings.min_app_version`, this offers the newest Play release
/// directly inside the app. High-priority releases (inAppUpdatePriority ≥ 4
/// set in Play Console) trigger a blocking immediate update; everything else
/// downloads in the background (flexible) and prompts a restart when ready.
class InAppUpdateService {
  static bool _checked = false;

  /// Call once after first frame. Safe to await — never throws.
  static Future<void> check(BuildContext context) async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      final priority = info.updatePriority;

      if (priority >= 4 && info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }

      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        if (!context.mounted) return;
        _promptRestart(context);
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      // Non-blocking — Play still auto-updates in the background.
    }
  }

  static void _promptRestart(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        backgroundColor: MotoGoColors.black,
        content: Text(
          t(context).tr('updateDownloaded'),
          style: const TextStyle(color: Colors.white),
        ),
        action: SnackBarAction(
          label: t(context).tr('updateRestart'),
          textColor: MotoGoColors.green,
          onPressed: () => InAppUpdate.completeFlexibleUpdate(),
        ),
      ),
    );
  }
}
