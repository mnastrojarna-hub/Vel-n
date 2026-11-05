import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/i18n/translations.dart' show translations;
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/v2/flag/v2_scope.dart';
import 'routes_model.dart';
import 'submit_common.dart';
import 'v2/route_name_sheet_v2.dart';

/// Název a popis trasy, které zákazník v editoru už zadal. List „Uložit
/// trasu" i „Navrhnout do komunity" se jimi předvyplní — po uložení se
/// při návrhu (a naopak) nic nepíše podruhé (majitel 2026-10-22: „nikdy
/// nic nevyplňovat dvakrát").
class RouteNameMemory {
  String name;
  String desc;
  RouteNameMemory({this.name = '', this.desc = ''});

  /// Výchozí hodnoty podle otevřené trasy:
  /// - trasa z katalogu → její název (popis katalogu ne — není zákazníkův),
  /// - vlastní trasa otevřená z Mých zážitků ([ownStops] = explicitní
  ///   zastávky) → její název (a popis, pokud ho trasa nese), kromě
  ///   obecného popisku „Vlastní vyjížďka" v kterémkoli jazyce,
  /// - nová vlastní trasa → prázdné (jako dosud).
  factory RouteNameMemory.fromRoute(RouteItem r, {required bool ownStops}) {
    if (r.id != 'custom') return RouteNameMemory(name: r.name);
    if (!ownStops || isGenericRouteName(r.name)) return RouteNameMemory();
    return RouteNameMemory(name: r.name.trim(), desc: r.description?.trim() ?? '');
  }

  /// Úspěšně uložené / odeslané hodnoty → výchozí pro další list.
  void remember(String n, String d) {
    name = n;
    desc = d;
  }
}

/// Prázdný název nebo obecný popisek vlastní trasy (všechny jazyky).
bool isGenericRouteName(String name) {
  final n = name.trim();
  return n.isEmpty || translations.values.any((m) => m['poiCustomRouteTitle'] == n);
}

/// List „Uložit trasu" (jen pro mě → Moje zážitky → Moje trasy).
void showRouteSaveSheet(
  BuildContext context, {
  required RouteNameMemory names,
  required Future<bool> Function(String name, String desc) onSubmit,
  required Future<void> Function() onDone,
}) =>
    _showNameSheet(context,
        names: names,
        titleKey: 'routeSaveTitle',
        intro: (c) => [
              const SizedBox(height: 6),
              Text(
                t(c).tr('routeSaveHint'),
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeMd,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.g500,
                    decoration: TextDecoration.none),
              ),
            ],
        v2HintKey: 'routeSaveHint',
        nameKey: 'routeSaveName',
        descKey: 'routeSaveDesc',
        descLines: 2,
        sendKey: 'routeSaveBtn',
        errKey: 'routeSaveErr',
        onSubmit: onSubmit,
        onDone: onDone);

/// List „Navrhnout do komunity" (moderace ve Velíně).
void showRouteSuggestSheet(
  BuildContext context, {
  required RouteNameMemory names,
  required Future<bool> Function(String name, String desc) onSubmit,
  required Future<void> Function() onDone,
}) =>
    _showNameSheet(context,
        names: names,
        titleKey: 'routeSuggestTitle',
        intro: (_) => const [SizedBox(height: 12), SubmitIntroBanner()],
        nameKey: 'poiSubmitName',
        descKey: 'routeSubmitDescLabel',
        descLines: 3,
        sendKey: 'poiSubmitSend',
        errKey: 'poiSubmitErr',
        onSubmit: onSubmit,
        onDone: onDone);

void _showNameSheet(
  BuildContext context, {
  required RouteNameMemory names,
  required String titleKey,
  required List<Widget> Function(BuildContext) intro,
  String? v2HintKey,
  required String nameKey,
  required String descKey,
  required int descLines,
  required String sendKey,
  required String errKey,
  required Future<bool> Function(String name, String desc) onSubmit,
  required Future<void> Function() onDone,
}) {
  final nameCtrl = TextEditingController(text: names.name);
  final descCtrl = TextEditingController(text: names.desc);
  var busy = false;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        // Odeslání sdílené starým i v2 vzhledem (kill-switch) — tělo beze změny.
        Future<void> submit() async {
          if (nameCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(sheetCtx)
                .showSnackBar(SnackBar(content: Text(t(sheetCtx).tr('poiSubmitNameReq'))));
            return;
          }
          setSheet(() => busy = true);
          final name = nameCtrl.text.trim(), desc = descCtrl.text.trim();
          final ok = await onSubmit(name, desc);
          // Zapamatovat i když zákazník list mezitím zavřel.
          if (ok) names.remember(name, desc);
          if (!sheetCtx.mounted) return;
          if (ok) {
            Navigator.of(sheetCtx).pop();
            await onDone();
          } else {
            setSheet(() => busy = false);
            ScaffoldMessenger.of(sheetCtx)
                .showSnackBar(SnackBar(content: Text(t(sheetCtx).tr(errKey))));
          }
        }

        if (MgV2.on(sheetCtx)) {
          return RouteNameSheetV2(
            title: t(sheetCtx).tr(titleKey),
            hintKey: v2HintKey,
            name: nameCtrl,
            nameLabel: t(sheetCtx).tr(nameKey),
            desc: descCtrl,
            descLabel: t(sheetCtx).tr(descKey),
            descLines: descLines,
            sendLabel: t(sheetCtx).tr(busy ? 'submitSending' : sendKey),
            busy: busy,
            onSend: submit,
          );
        }
        return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MgSheetTitleRow(
                  center: false,
                  title: Text(
                    t(sheetCtx).tr(titleKey),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH2,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  )),
              ...intro(sheetCtx),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: t(sheetCtx).tr(nameKey)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: descLines,
                decoration: InputDecoration(labelText: t(sheetCtx).tr(descKey)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: busy ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MotoGoColors.green,
                    foregroundColor: MotoGoColors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
                  ),
                  child: Text(
                    t(sheetCtx).tr(busy ? 'submitSending' : sendKey),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      },
    ),
  );
}
