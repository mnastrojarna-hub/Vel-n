import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'i18n/i18n_provider.dart';

/// In-app update offers — keeps users on the newest release without waiting
/// for them to visit the store.
///
/// Complements [UpdateChecker]: while the latter force-blocks below
/// `app_settings.min_app_version`, this proactively OFFERS the newest release:
/// - Android: Google Play In-App Updates. High-priority releases
///   (inAppUpdatePriority ≥ 4 set in Play Console) trigger a blocking
///   immediate update; everything else downloads in the background (flexible)
///   and prompts a restart when ready.
/// - iOS: the App Store has no in-app update API, so the live store version
///   is read from the iTunes Lookup API and a dismissible dialog offers the
///   update with a direct App Store link.
class InAppUpdateService {
  static DateTime? _lastOfferAt;

  /// Minimum gap between UPDATE OFFERS (flexible download / immediate flow /
  /// iOS dialog). The cheap availability query itself runs on every call so
  /// a backgrounded immediate update is always resumed right away.
  static const _reofferInterval = Duration(hours: 6);

  // App Store Connect Apple ID aplikace (firemní účet Mnástrojárna s.r.o.).
  static const _appStoreId = '6806045151';
  static const _appStoreUrl = 'https://apps.apple.com/cz/app/id6806045151';

  /// Call after first frame AND on every app resume. Safe to await — never
  /// throws.
  static Future<void> check(BuildContext context) async {
    if (Platform.isAndroid) return _checkAndroid(context);
    if (Platform.isIOS) return _checkIos(context);
  }

  // ---------------------------------------------------------------- Android

  static Future<void> _checkAndroid(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();

      // User backgrounded a blocking immediate update — Play requires the
      // app to resume the flow itself, otherwise the update stays stuck.
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      final now = DateTime.now();
      if (_lastOfferAt != null &&
          now.difference(_lastOfferAt!) < _reofferInterval) {
        return;
      }
      _lastOfferAt = now;

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

  // -------------------------------------------------------------------- iOS

  static Future<void> _checkIos(BuildContext context) async {
    final now = DateTime.now();
    if (_lastOfferAt != null &&
        now.difference(_lastOfferAt!) < _reofferInterval) {
      return;
    }
    try {
      // iTunes Lookup vrací aktuálně publikovanou verzi v App Store (pozor:
      // po releasu se v API může objevit až s několikahodinovým zpožděním).
      final res = await http
          .get(Uri.parse(
              'https://itunes.apple.com/lookup?id=$_appStoreId&country=cz'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final results = data is Map ? data['results'] : null;
      if (results is! List || results.isEmpty) return;
      final storeVersion = (results.first as Map)['version'];
      if (storeVersion is! String || storeVersion.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      if (_compareSemver(info.version, storeVersion) >= 0) return;

      if (!context.mounted) return;
      _lastOfferAt = now;
      _showUpdateDialog(context, storeVersion);
    } catch (_) {
      // Non-blocking — check silently retries on next launch/resume.
    }
  }

  /// Compare two semver strings (e.g. "3.4.0" vs "3.5.0").
  /// Returns negative if a < b, 0 if equal, positive if a > b.
  static int _compareSemver(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (pa.length < 3) pa.add(0);
    while (pb.length < 3) pb.add(0);
    for (var i = 0; i < 3; i++) {
      if (pa[i] < pb[i]) return -1;
      if (pa[i] > pb[i]) return 1;
    }
    return 0;
  }

  static void _showUpdateDialog(BuildContext context, String storeVersion) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: MotoGoColors.greenDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t(context).tr('updateAvailable'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          t(context)
              .tr('updateAvailableDesc')
              .replaceAll('{version}', storeVersion),
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              t(context).tr('updateLater'),
              style: const TextStyle(
                color: MotoGoColors.g500,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.green,
              foregroundColor: MotoGoColors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(_appStoreUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              t(context).tr('updateNow'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
