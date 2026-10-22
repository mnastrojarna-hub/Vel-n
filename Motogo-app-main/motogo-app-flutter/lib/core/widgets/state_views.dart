import 'dart:async';

import 'package:flutter/material.dart';

import '../friendly_error.dart';
import '../i18n/i18n_provider.dart';
import '../theme.dart';
import '../v2/flag/v2_scope.dart';
import '../v2/states/legacy_state_looks.dart';
import '../v2/widgets/mg_back_v2.dart';
import 'error_feedback.dart';

/// Viditelná šipka zpět v barvách appky (zelený čtverec „←"), dotyková plocha
/// 44 × 44 a popisek pro čtečku obrazovky.
class MgBackArrow extends StatelessWidget {
  final VoidCallback onTap;
  final bool dark;
  const MgBackArrow({super.key, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    // v2 vzhled (kill-switch app_v2_ui): stejný onTap i popisek.
    if (MgV2.on(context)) {
      return MgV2Back(
        onTap: onTap,
        label: t(context).tr('eoBack'),
        style: dark ? MgBackStyle.light : MgBackStyle.dark,
      );
    }
    return Semantics(
      button: true,
      label: t(context).tr('eoBack'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dark ? MotoGoColors.dark : MotoGoColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('←',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: dark ? Colors.white : Colors.black)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Obal stavu načítání / chyby s hlavičkou a šipkou zpět — pro obrazovky,
/// jejichž vlastní hlavička se kreslí až s daty.
class MgStateScaffold extends StatelessWidget {
  final String? title;
  final VoidCallback onBack;
  final Widget child;
  const MgStateScaffold(
      {super.key, this.title, required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) {
      return v2StateScaffoldLook(context, title: title, onBack: onBack, child: child);
    }
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        backgroundColor: MotoGoColors.dark,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: MgBackArrow(onTap: onBack),
        ),
        title: title == null
            ? null
            : Text(title!,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: child,
    );
  }
}

/// Načítání, které se nikdy nezasekne „potichu": po 15 s řekne, že to trvá
/// déle, a nabídne Zkusit znovu / Zpět.
class MgLoadingView extends StatefulWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final Color color;
  const MgLoadingView(
      {super.key, this.onRetry, this.onBack, this.color = MotoGoColors.green});

  @override
  State<MgLoadingView> createState() => _MgLoadingViewState();
}

class _MgLoadingViewState extends State<MgLoadingView> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) {
      return v2LoadingLook(context, slow: _slow, onRetry: widget.onRetry, onBack: widget.onBack);
    }
    final tr = t(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: widget.color),
            if (_slow) ...[
              const SizedBox(height: 16),
              Text(tr.tr('eoSlowTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              const SizedBox(height: 6),
              Text(tr.tr('eoSlowBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g600)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                if (widget.onRetry != null)
                  ElevatedButton(onPressed: widget.onRetry, child: Text(tr.tr('eoRetry'))),
                if (widget.onBack != null)
                  OutlinedButton(onPressed: widget.onBack, child: Text(tr.tr('eoBack'))),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chybový stav: CO se stalo, PROČ a JAK to opravit + tlačítka, která něco
/// dělají (Zkusit znovu, Otevřít nastavení, Zpět, Zavolat).
class MgErrorView extends StatelessWidget {
  final Object? error;

  /// Vlastní titulek („Zprávy se nepodařilo načíst"); jinak titulek druhu chyby.
  final String? what;

  /// Vlastní text místo výchozího vysvětlení (např. „Rezervaci jsme nenašli…").
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final String? backLabel;
  final bool contact;
  final DevicePerm? perm;
  final List<Widget> extra;
  final bool compact;

  const MgErrorView({
    super.key,
    this.error,
    this.what,
    this.message,
    this.onRetry,
    this.onBack,
    this.backLabel,
    this.contact = true,
    this.perm,
    this.extra = const [],
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final fe = FriendlyError.of(error, perm: perm);
    final title = what ?? fe.title(tr);
    // Bez kontaktu (contact: false) i v textu, ne jen bez tlačítka „Zavolat".
    final body = message ??
        (what != null
            ? '${_cap(fe.reason(tr))}. ${fe.body(tr, contact: contact)}'
            : fe.body(tr, contact: contact));
    if (MgV2.on(context)) {
      return v2ErrorViewLook(context,
          fe: fe,
          title: title,
          body: body,
          onRetry: onRetry,
          onBack: onBack,
          backLabel: backLabel,
          contact: contact,
          extra: extra,
          compact: compact);
    }
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fe.isNetwork ? '📡' : (fe.needsSettings ? '🔒' : '⚠️'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: MotoGoColors.g600, height: 1.35)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onRetry != null)
                ElevatedButton(onPressed: onRetry, child: Text(tr.tr('eoRetry'))),
              if (fe.needsSettings)
                OutlinedButton(
                    onPressed: () => openFixSettings(fe),
                    child: Text(tr.tr('eoOpenSettings'))),
              ...extra,
              if (onBack != null)
                OutlinedButton(
                    onPressed: onBack, child: Text(backLabel ?? tr.tr('eoBack'))),
              if (contact && fe.suggestContact)
                TextButton(
                    onPressed: callMotoGo,
                    child: Text('📞 ${tr.tr('eoCall')}',
                        style: const TextStyle(color: MotoGoColors.greenDarker))),
            ],
          ),
        ],
      ),
    );
    if (compact) return card;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: card,
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Pruh „Zobrazujeme naposledy načtené údaje" — obnova dat selhala (offline,
/// slabý signál), ale už načtené údaje (rezervace, kódy) zůstávají vidět.
class MgStaleNote extends StatelessWidget {
  final VoidCallback onRetry;
  final EdgeInsetsGeometry margin;
  const MgStaleNote(
      {super.key, required this.onRetry, this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0)});

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) return v2StaleNoteLook(context, onRetry: onRetry, margin: margin);
    final tr = t(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: MotoGoColors.amberBg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.amberBorder),
      ),
      child: Row(children: [
        Expanded(
          child: Text('📡 ${tr.tr('fxStaleData')}',
              style: const TextStyle(
                  fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(tr.tr('eoRetry'),
              style: const TextStyle(fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
        ),
      ]),
    );
  }
}
