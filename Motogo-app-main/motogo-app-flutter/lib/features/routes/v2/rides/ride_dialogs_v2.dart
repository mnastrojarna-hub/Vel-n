import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';

/// v2 (T6) look of the old "Smazat …?" dialogs: [title] + [body] (the
/// name), Zrušit (pop false) / Smazat red (pop true) — the SAME pop values
/// the old AlertDialog returned. Built inside the old `showDialog` builder.
Widget rideConfirmDeleteV2(BuildContext dc, {required String title, required String body}) {
  final tr = t(dc);
  return MgDialogFrame(
    title: title,
    body: body,
    safeLabel: tr.cancel,
    actionLabel: tr.tr('myExpDelete'),
    safe: MgBtnGhostLight(label: tr.cancel, onTap: () => Navigator.pop(dc, false)),
    action: MgBtnDestructive(label: tr.tr('myExpDelete'), onTap: () => Navigator.pop(dc, true)),
  );
}

/// v2 look of "Upravit jízdu": the SAME controllers (name, description) and
/// pop values (Zrušit false / Uložit true) as the old dialog.
Widget rideEditDialogV2(BuildContext c, TextEditingController name, TextEditingController desc) {
  final tr = t(c);
  return MgDialogFrame(
    title: tr.tr('rideEditTitle'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: mgInputDecoration(c, label: tr.tr('rideName'))),
      const SizedBox(height: 12),
      TextField(controller: desc, maxLines: 3, decoration: mgInputDecoration(c, label: tr.tr('rideDescription'))),
    ]),
    safeLabel: tr.cancel,
    actionLabel: tr.tr('ridePointSave'),
    safe: MgBtnGhostLight(label: tr.cancel, onTap: () => Navigator.pop(c, false)),
    action: MgBtnInk(label: tr.tr('ridePointSave'), neonLabel: true, onTap: () => Navigator.pop(c, true)),
  );
}
