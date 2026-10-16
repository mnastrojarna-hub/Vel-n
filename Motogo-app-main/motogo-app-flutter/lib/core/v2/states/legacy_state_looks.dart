import 'package:flutter/material.dart';

import '../../friendly_error.dart';
import '../../i18n/i18n_provider.dart';
import '../../widgets/error_feedback.dart' show callMotoGo, openFixSettings;
import '../chrome/mg_app_bar.dart';
import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_buttons.dart';
import 'mg_state_banner.dart';
import 'mg_tone.dart';

/// v2 looks of the EXISTING state widgets in `core/widgets/state_views.dart`
/// (V-seams, PLAN §1.8). Same texts, same callbacks — only the look.

/// Tone + icon of a [FriendlyError] (network → offline info, settings →
/// lock warning, otherwise error).
(MgTone, String) v2ToneOf(FriendlyError fe) {
  if (fe.isNetwork) return (MgTone.info, MgIcons.wifiOff);
  if (fe.needsSettings) return (MgTone.warn, MgIcons.lock);
  return (MgTone.err, MgIcons.close);
}

/// `MgErrorView` in the v2 look: compact = T3 banner, otherwise a centred
/// T1-style block (tone disc 72, title, why, actions) inside the screen.
Widget v2ErrorViewLook(
  BuildContext context, {
  required FriendlyError fe,
  required String title,
  required String body,
  VoidCallback? onRetry,
  VoidCallback? onBack,
  String? backLabel,
  bool contact = true,
  List<Widget> extra = const [],
  bool compact = false,
}) {
  final tr = t(context);
  final (tone, icon) = v2ToneOf(fe);
  final actions = <Widget>[
    if (onRetry != null) MgBtnInk(label: tr.tr('eoRetry'), onTap: onRetry, expand: !compact, height: compact ? 44 : 52),
    if (fe.needsSettings)
      MgBtnGhostLight(label: tr.tr('eoOpenSettings'), onTap: () => openFixSettings(fe), expand: !compact),
    ...extra,
    if (onBack != null) MgBtnText(label: backLabel ?? tr.tr('eoBack'), onTap: onBack),
    if (contact && fe.suggestContact) MgBtnText(label: tr.tr('eoCall'), icon: MgIcons.phone, onTap: callMotoGo),
  ];
  if (compact) {
    return MgStateBanner(tone: tone, icon: icon, title: title, text: body, actions: actions, plain: true);
  }
  return Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: MgToneDisc(tone: tone, size: 72, icon: icon)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
        const SizedBox(height: 20),
        for (final a in actions) ...[a, const SizedBox(height: MgSpace.s8)],
      ]),
    ),
  );
}

/// `MgLoadingView` in the v2 look (its 15 s "trvá to déle" logic stays in
/// the State; [slow] comes from there).
Widget v2LoadingLook(BuildContext context, {required bool slow, VoidCallback? onRetry, VoidCallback? onBack}) {
  final tr = t(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          label: tr.loading,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3, color: MgColors.link),
          ),
        ),
        if (slow) ...[
          const SizedBox(height: 16),
          Text(tr.tr('eoSlowTitle'),
              textAlign: TextAlign.center, style: MgType.title.copyWith(color: MgColors.ink)),
          const SizedBox(height: 6),
          Text(tr.tr('eoSlowBody'),
              textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.body2)),
          const SizedBox(height: 12),
          if (onRetry != null) MgBtnInk(label: tr.tr('eoRetry'), onTap: onRetry, expand: false),
          if (onBack != null) MgBtnText(label: tr.tr('eoBack'), onTap: onBack),
        ],
      ]),
    ),
  );
}

/// `MgStateScaffold` in the v2 look: compact dark app bar + `MgV2Back`.
Widget v2StateScaffoldLook(BuildContext context, {String? title, required VoidCallback onBack, required Widget child}) {
  return Scaffold(
    backgroundColor: MgColors.canvas,
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MgAppBar(title: title ?? '', onBack: onBack),
      Expanded(child: child),
    ]),
  );
}

/// `MgStaleNote` in the v2 look: T3 info banner with the same retry.
Widget v2StaleNoteLook(BuildContext context, {required VoidCallback onRetry, required EdgeInsetsGeometry margin}) {
  final tr = t(context);
  return Padding(
    padding: margin,
    child: MgStateBanner(
      tone: MgTone.info,
      icon: MgIcons.wifiOff,
      title: tr.tr('fxStaleData'),
      actions: [MgBtnText(label: tr.tr('eoRetry'), onTap: onRetry)],
    ),
  );
}
