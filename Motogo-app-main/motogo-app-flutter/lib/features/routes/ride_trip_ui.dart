import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/mg_nav_controls.dart';
import 'ride_trip_api.dart';

/// Společné kousky UI cest (starý vzhled; v2 je smí volat taky): hlášky
/// s „Zpět", dialog názvu, potvrzení, volba mazání.

/// Výsledek operace s cestou: OK → [doneKey] + „Zpět" (vrátí přesně
/// předchozí stav), jinak co se nepovedlo a co s tím.
void rideTripSnack(BuildContext context, RideTripOp op, String doneKey,
    {Iterable<String?> bookingIds = const []}) {
  final msg = ScaffoldMessenger.of(context);
  final tr = t(context);
  final c = ProviderScope.containerOf(context, listen: false);
  msg.hideCurrentSnackBar();
  if (!op.ok) {
    rideTripShowResult(msg, tr, op.result);
    return;
  }
  msg.showSnackBar(SnackBar(
    content: Text(tr.tr(doneKey)),
    duration: const Duration(seconds: 6),
    action: op.undo.isEmpty
        ? null
        : SnackBarAction(
            label: tr.tr('rpUndo'),
            textColor: MotoGoColors.green,
            onPressed: () async {
              final r = (await rideTripApplyIn(c, rideTripUndoPlan(op.undo), bookingIds: bookingIds)).result;
              if (r != RideTripOpResult.ok) rideTripShowResult(msg, tr, r);
            },
          ),
  ));
}

/// Hláška neúspěchu (`rpTripPartial` / `rpTripUnavailable` / `rpTripFailed`).
void rideTripShowResult(ScaffoldMessengerState msg, AppTranslations tr, RideTripOpResult r) {
  final key = rideTripResultKey(r);
  if (key == null) return;
  msg
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr.tr(key)), duration: const Duration(seconds: 7)));
}

/// Dialog názvu cesty. null = zrušeno, '' = výchozí název.
Future<String?> rideTripNameDialog(BuildContext context, {String? initial, required String title}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: t(c).tr('rpMergeNameHint'), hintMaxLines: 2),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(t(c).cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.green, foregroundColor: MotoGoColors.black),
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(t(c).tr('ridePointSave')),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}

/// Potvrzení (rozdělit / smazat). [danger] = červené tlačítko.
Future<bool> rideConfirm(BuildContext context,
    {required String title, required String body, required String confirm, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
      content: Text(body, style: const TextStyle(fontSize: MotoGoTypo.sizeLg, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: danger ? const Color(0xFFD93636) : MotoGoColors.green,
              foregroundColor: danger ? Colors.white : MotoGoColors.black),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

enum RideTripDeleteChoice { split, all }

/// „Smazat cestu" → jen zrušit sloučení, nebo smazat i všechny jízdy.
Future<RideTripDeleteChoice?> rideTripDeleteSheet(BuildContext context) =>
    showModalBottomSheet<RideTripDeleteChoice>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const MgSheetHandle(margin: EdgeInsets.symmetric(horizontal: 12)),
          ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.call_split, color: MotoGoColors.greenDarker),
            title: Text(t(c).tr('rpTripDeleteOnlyGroup'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800)),
            onTap: () => Navigator.pop(c, RideTripDeleteChoice.split),
          ),
          ListTile(
            minVerticalPadding: 12,
            leading: const Icon(Icons.delete_outline, color: MotoGoColors.red),
            title: Text(t(c).tr('rpTripDeleteAll'),
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800, color: MotoGoColors.red)),
            onTap: () => Navigator.pop(c, RideTripDeleteChoice.all),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
