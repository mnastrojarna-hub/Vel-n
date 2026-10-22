import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/native/permission_service.dart';
import '../../../core/widgets/error_feedback.dart';
import '../../auth/widgets/toast_helper.dart';

/// „Povolit vše znovu" — systém po trvalém zamítnutí už žádný dialog neukáže,
/// takže dřív hláška „✅ Oprávnění znovu vyžádána" lhala. Teď se stavy přečtou
/// znovu: vše povoleno → potvrzení; jinak které chybí a jak je povolit.
Future<void> requestAllPermissionsAndReport(BuildContext context) async {
  await PermissionService.requestAll();
  final missing = await PermissionService.missingTitles();
  if (!context.mounted) return;
  final tr = t(context);
  if (missing.isEmpty) {
    showMotoGoToast(context,
        icon: '✅', title: tr.tr('permissionLabel'), message: tr.tr('eoPermsAllGranted'));
    return;
  }
  final names = missing.map(tr.tr).join(', ');
  final r = await showErrorDialog(context,
      title: tr.tr('eoPermsMissingTitle'),
      body: tr.trArgs('eoPermsMissingBody', {'list': names}),
      actions: [('settings', tr.tr('eoOpenSettings'))]);
  if (r == 'settings') await PermissionService.openSettings();
}
