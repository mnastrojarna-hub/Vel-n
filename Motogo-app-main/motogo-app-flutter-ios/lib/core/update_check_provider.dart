import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_client.dart';
import 'theme.dart';
import 'i18n/i18n_provider.dart';

/// Checks app_settings.min_app_version against the running app version.
/// If current < minimum → shows a blocking force-update dialog.
///
/// Usage: call UpdateChecker.check(context) after first frame AND on every
/// app resume (lifecycle) — a long-running session must hit the gate too,
/// not only fresh launches. Re-checks are throttled internally.
class UpdateChecker {
  static bool _dialogShown = false;
  static DateTime? _lastCheckAt;

  /// Minimum gap between checks so a resume-happy user doesn't hammer
  /// app_settings; one query per interval is enough to catch a version bump.
  static const _recheckInterval = Duration(minutes: 15);

  // Android balíček na Google Play zůstává com.motogo24.app (iOS bundle ID
  // je od přechodu na firemní účet com.motogo24.rental — netýká se této URL).
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.motogo24.app';

  // App Store Connect Apple ID aplikace (firemní účet Mnástrojárna s.r.o.).
  static const _appStoreUrl = 'https://apps.apple.com/cz/app/id6806045151';

  static String get _storeUrl =>
      Platform.isIOS ? _appStoreUrl : _playStoreUrl;

  /// Compare two semver strings (e.g. "2.3.2" vs "2.4.0").
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

  /// Fetch min_app_version from Supabase app_settings, compare with current.
  /// Shows blocking dialog if update is required.
  static Future<void> check(BuildContext context) async {
    if (_dialogShown) return;
    final now = DateTime.now();
    if (_lastCheckAt != null &&
        now.difference(_lastCheckAt!) < _recheckInterval) {
      return;
    }
    _lastCheckAt = now;
    try {
      final res = await MotoGoSupabase.client
          .from('app_settings')
          .select('value')
          .eq('key', 'min_app_version')
          .maybeSingle();

      if (res == null || res['value'] == null) return;

      final value = res['value'];
      // value can be a plain string "2.4.0" or a map {"version": "2.4.0"}
      final String minVersion;
      if (value is String) {
        minVersion = value;
      } else if (value is Map && value['version'] is String) {
        minVersion = value['version'] as String;
      } else {
        return;
      }

      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "2.3.2"

      if (_compareSemver(current, minVersion) < 0) {
        if (!context.mounted) return;
        _dialogShown = true;
        _showForceUpdateDialog(context, minVersion);
      }
    } catch (_) {
      // Non-blocking — if check fails, let user continue
    }
  }

  static void _showForceUpdateDialog(BuildContext context, String minVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MotoGoRadius.lg),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: MotoGoColors.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(context).tr('updateRequired'),
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
                .tr('updateRequiredDesc')
                .replaceAll('{version}', minVersion),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: MotoGoColors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                ),
                onPressed: () {
                  launchUrl(
                    Uri.parse(_storeUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Text(
                  t(context).tr('updateNow'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
