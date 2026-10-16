import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';

import '../friendly_error.dart';
import '../i18n/i18n_provider.dart';
import '../theme.dart';

/// Nonstop linka MotoGo24 (volání funguje i bez mobilních dat).
const String kMotoGoPhone = '+420774256271';
const String kMotoGoPhoneLabel = '+420 774 256 271';

/// Zavolá MotoGo24. Vrací false, když telefon hovor neumí (tablet).
Future<bool> callMotoGo() => _dial(kMotoGoPhone);

/// Tísňová linka 112.
Future<bool> call112() => _dial('112');

Future<bool> _dial(String n) async {
  try {
    return await launchUrl(Uri.parse('tel:$n'));
  } catch (_) {
    return false;
  }
}

/// Otevře nastavení, kde zákazník chybu opraví: vypnutá poloha → nastavení
/// polohy, jinak nastavení appky (oprávnění).
Future<void> openFixSettings(FriendlyError fe) async {
  try {
    if (fe.kind == FriendlyKind.locationOff) {
      await Geolocator.openLocationSettings();
    } else {
      await ph.openAppSettings();
    }
  } catch (_) {}
}

/// Toast „{co} – {proč}. {jak}" + akce (Zkusit znovu / Otevřít nastavení).
/// Delší zobrazení, ať se dá dočíst. Technický detail jde jen do logu.
void showErrorSnack(
  BuildContext context,
  String what,
  Object? error, {
  VoidCallback? onRetry,
  DevicePerm? perm,
  String? where,
}) {
  FriendlyError.log(where ?? 'ui_error', error);
  final tr = t(context);
  final fe = FriendlyError.of(error, perm: perm);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  SnackBarAction? action;
  if (fe.needsSettings) {
    action = SnackBarAction(
        label: tr.tr('eoOpenSettings'),
        textColor: MotoGoColors.green,
        onPressed: () => openFixSettings(fe));
  } else if (onRetry != null) {
    action = SnackBarAction(
        label: tr.tr('eoRetry'), textColor: MotoGoColors.green, onPressed: onRetry);
  } else if (fe.suggestContact) {
    action = SnackBarAction(
        label: tr.tr('eoCall'), textColor: MotoGoColors.green, onPressed: callMotoGo);
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(fe.compose(tr, what)),
      duration: const Duration(seconds: 7),
      action: action,
    ));
}

/// Dialog s chybou: titulek (co), tělo (proč + jak) a tlačítka, která něco
/// dělají. [extra] = další akce (např. Zavolat). Vrací id zvolené akce.
Future<String?> showErrorDialog(
  BuildContext context, {
  required String title,
  required String body,
  List<(String id, String label)> actions = const [],
  bool showClose = true,
}) {
  final tr = t(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        if (showClose)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr.tr('eoClose'),
                style: const TextStyle(color: MotoGoColors.g500)),
          ),
        for (final a in actions)
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, a.$1),
            child: Text(a.$2),
          ),
      ],
    ),
  );
}

/// Dotaz před zahozením rozpracovaných údajů (zpět / ✕). true = zahodit.
Future<bool> confirmDiscard(BuildContext context) async {
  final tr = t(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr.tr('eoDiscardTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(tr.tr('eoDiscardBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr.tr('eoDiscard'),
              style: const TextStyle(color: MotoGoColors.red)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr.tr('eoStay')),
        ),
      ],
    ),
  );
  return r == true;
}

/// Neblokovatelný průběh (spinner + text) přes celou obrazovku — akce, která
/// chvíli trvá, nejde spustit dvakrát ani omylem zavřít. [close] vždy uklidí.
class MgProgress {
  MgProgress._(this._route, this.text);
  final Route<void> _route;
  final ValueNotifier<String> text;

  static MgProgress show(BuildContext context, String initial) {
    final text = ValueNotifier(initial);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: text,
                builder: (_, v, __) => Text(v,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
    Navigator.of(context, rootNavigator: true).push(route);
    return MgProgress._(route, text);
  }

  void update(String s) => text.value = s;

  void close() {
    final nav = _route.navigator;
    if (nav != null && _route.isActive) nav.removeRoute(_route);
  }
}
