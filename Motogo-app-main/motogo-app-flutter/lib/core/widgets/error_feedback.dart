import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';

import '../friendly_error.dart';
import '../native/gps_service.dart' show GpsStatus;
import '../i18n/i18n_provider.dart';
import '../theme.dart';
import '../v2/flag/v2_scope.dart';
import '../v2/states/legacy_dialog_looks.dart';

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
/// [contact] = false: bez e-mailu, telefonu i akce „Zavolat" (platby,
/// rezervace — D5); rada pak jen řekne, co zkusit.
void showErrorSnack(
  BuildContext context,
  String what,
  Object? error, {
  VoidCallback? onRetry,
  DevicePerm? perm,
  String? where,
  FriendlyError? friendly,
  bool contact = true,
}) {
  if (error != null) FriendlyError.log(where ?? 'ui_error', error);
  final tr = t(context);
  final fe = friendly ?? FriendlyError.of(error, perm: perm);
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
  } else if (contact && fe.suggestContact) {
    action = SnackBarAction(
        label: tr.tr('eoCall'), textColor: MotoGoColors.green, onPressed: callMotoGo);
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(fe.compose(tr, what, contact: contact)),
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
    builder: (ctx) => MgV2.on(ctx)
        ? v2ErrorDialogLook(ctx, title: title, body: body, actions: actions, showClose: showClose)
        : AlertDialog(
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

/// Poloha není k dispozici (vypnutá / bez oprávnění / bez GPS signálu) →
/// PROČ a JAK to opravit. Nastavení se otevře JEN na klepnutí „Otevřít
/// nastavení" (dřív ho appka otevírala sama a beze slova). [snack] = jen
/// nenápadný toast (poloha se zjišťuje sama při otevření obrazovky), jinak
/// dialog (zákazník si o polohu právě řekl — i nad bottom sheetem).
Future<void> explainLocation(BuildContext context, GpsStatus st,
    {bool snack = false}) async {
  if (st == GpsStatus.ok || !context.mounted) return;
  final tr = t(context);
  final fe = switch (st) {
    GpsStatus.serviceOff => const FriendlyError(FriendlyKind.locationOff),
    GpsStatus.denied || GpsStatus.deniedForever =>
      const FriendlyError(FriendlyKind.permission, perm: DevicePerm.location),
    _ => null,
  };
  if (snack) {
    if (fe != null) {
      showErrorSnack(context, tr.tr('fxLocUnavailable'), null, friendly: fe);
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(tr.tr('fxLocNoFixBody')),
          duration: const Duration(seconds: 7)));
    return;
  }
  if (fe == null) {
    await showErrorDialog(context,
        title: tr.tr('fxLocNoFixTitle'), body: tr.tr('fxLocNoFixBody'));
    return;
  }
  final r = await showErrorDialog(context,
      title: fe.title(tr),
      body: fe.body(tr),
      actions: [('settings', tr.tr('eoOpenSettings'))]);
  if (r == 'settings') await openFixSettings(fe);
}

/// Dotaz před zahozením rozpracovaných údajů (zpět / ✕). true = zahodit.
/// [title] / [body] = vlastní texty (např. úpravy trasy), jinak obecné.
Future<bool> confirmDiscard(BuildContext context,
    {String? title, String? body}) async {
  final tr = t(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => MgV2.on(ctx)
        ? v2DiscardDialogLook(ctx, title: title ?? tr.tr('eoDiscardTitle'), body: body ?? tr.tr('eoDiscardBody'))
        : AlertDialog(
      title: Text(title ?? tr.tr('eoDiscardTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body ?? tr.tr('eoDiscardBody')),
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

/// Zákazník klepl u průběhu na „Zrušit" — volající pozdní výsledek zahodí.
class MgCancelled implements Exception {
  const MgCancelled();
}

/// Průběh (spinner + text) přes celou obrazovku — akce, která chvíli trvá,
/// nejde spustit dvakrát ani omylem zavřít. [close] vždy uklidí.
/// [cancelAfter] = po této době (slabý signál) se ukáže „trvá to déle"
/// + „Zrušit"; systémové Zpět ruší kdykoli — zákazník nikdy neuvízne v modálu;
/// operaci obalenou [guard] pak zruší ([MgCancelled]) a pozdní výsledek
/// se zahodí ([cancelled]).
class MgProgress {
  MgProgress._(this._route, this.text, this._cancel);
  final Route<void> _route;
  final ValueNotifier<String> text;
  final Completer<void> _cancel;

  /// Zákazník průběh zrušil.
  bool get cancelled => _cancel.isCompleted;

  static MgProgress show(BuildContext context, String initial,
      {Duration? cancelAfter}) {
    final text = ValueNotifier(initial);
    final cancel = Completer<void>();
    late final DialogRoute<void> route;
    void doCancel() {
      if (!cancel.isCompleted) cancel.complete();
      final nav = route.navigator;
      if (nav != null && route.isActive) nav.removeRoute(route);
    }

    route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MgProgressDialog(
          text: text, cancelAfter: cancelAfter, onCancel: doCancel),
    );
    Navigator.of(context, rootNavigator: true).push(route);
    return MgProgress._(route, text, cancel);
  }

  void update(String s) => text.value = s;

  /// Počká na [op]; klepne-li zákazník mezitím na „Zrušit", skončí hned
  /// výjimkou [MgCancelled] (výsledek [op] se zahodí).
  Future<T> guard<T>(Future<T> op) {
    if (cancelled) return Future<T>.error(const MgCancelled());
    return Future.any<T>([
      op,
      _cancel.future.then<T>((_) => throw const MgCancelled()),
    ]);
  }

  void close() {
    final nav = _route.navigator;
    if (nav != null && _route.isActive) nav.removeRoute(_route);
  }
}

class _MgProgressDialog extends StatefulWidget {
  final ValueNotifier<String> text;
  final Duration? cancelAfter;
  final VoidCallback onCancel;
  const _MgProgressDialog(
      {required this.text, required this.cancelAfter, required this.onCancel});

  @override
  State<_MgProgressDialog> createState() => _MgProgressDialogState();
}

class _MgProgressDialogState extends State<_MgProgressDialog> {
  Timer? _timer;
  bool _canCancel = false;

  @override
  void initState() {
    super.initState();
    final d = widget.cancelAfter;
    if (d != null) {
      _timer = Timer(d, () {
        if (mounted) setState(() => _canCancel = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return PopScope(
      canPop: false,
      // Systémové Zpět / gesto u zrušitelného průběhu = „Zrušit" (kdykoli,
      // tlačítko se ukáže až po limitu); nezrušitelný (SOS) drží.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.cancelAfter != null) widget.onCancel();
      },
      child: MgV2.on(context)
          ? v2ProgressDialogLook(context,
              text: widget.text, slow: _canCancel, onCancel: _canCancel ? widget.onCancel : null)
          : AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.text,
                builder: (_, v, __) => Text(v,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          if (_canCancel) ...[
            const SizedBox(height: 12),
            Text(tr.tr('r3SlowHint'),
                style: const TextStyle(fontSize: 12, color: MotoGoColors.g600, height: 1.35)),
          ],
        ]),
        actions: _canCancel
            ? [
                TextButton(
                  onPressed: widget.onCancel,
                  child: Text(tr.cancel,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]
            : null,
      ),
    );
  }
}
