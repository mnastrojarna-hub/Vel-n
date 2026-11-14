import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_sticky_slide.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// Offline overlay in the v2 look (Stavy 8.1 / 8.2 texts; re-skin only, the
/// full-screen behaviour stays — OD-SH-1): info tone, "Jsi offline", what
/// still works, "Zkusit znovu" (ink, spinner inside) → [onRetry],
/// "Pokračovat bez internetu" → [onContinue], ✕ = the same as system back
/// (continue), call MotoGo24 / 112 — exactly today's actions.
class OfflineViewV2 extends StatelessWidget {
  final bool checking;
  final bool stillOffline;
  final VoidCallback? onRetry;
  final VoidCallback onContinue;
  final VoidCallback onCall112;
  const OfflineViewV2({
    super.key,
    required this.checking,
    required this.stillOffline,
    required this.onRetry,
    required this.onContinue,
    required this.onCall112,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateScreen(
      tone: MgTone.info,
      icon: MgIcons.wifiOff,
      title: tr.tr('v2UxShOffTitle'),
      why: tr.tr('v2UxShOffWhy'),
      stepsTitle: tr.tr('v2UxShOffWorks'),
      steps: [
        tr.tr('v2UxShOffWorksSos'),
        tr.tr('v2UxShOffWorksLine'),
        tr.tr('v2UxShOffWorksCodes'),
      ],
      support: false,
      onClose: onContinue,
      primary: MgStateAction(tr.tr('eoRetry'), onRetry, busy: checking),
      secondary: MgStateAction(tr.tr('eoContinueOffline'), onContinue),
      children: [
        if (stillOffline)
          MgStateBanner(tone: MgTone.warn, title: tr.tr('eoStillOffline'), icon: MgIcons.wifiOff),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          const MgSupportRow(showWrite: false),
          MgBtnText(
            key: const ValueKey('offline-112'),
            label: tr.tr('v2UxShCall112'),
            icon: MgIcons.phone,
            color: MgColors.sos,
            onTap: onCall112,
          ),
        ]),
      ],
    );
  }
}

/// The thin top strip (offline with saved data / Wi-Fi without internet)
/// as a v2 T4 night strip under the status bar; slides down from the top
/// edge once (300 emphasized, instant under reduced motion). Touches go
/// through (like the old pill).
class OfflineStripV2 extends StatefulWidget {
  final bool offline;
  const OfflineStripV2({super.key, required this.offline});

  @override
  State<OfflineStripV2> createState() => _OfflineStripV2State();
}

class _OfflineStripV2State extends State<OfflineStripV2> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final title = tr.tr(widget.offline ? 'v2UxShOffTitle' : 'v2UxShWifiTitle');
    final sub = tr.tr(widget.offline ? 'v2UxShOffStripSub' : 'v2UxShWifiSub');
    return Positioned(
      top: top + 6,
      left: 12,
      right: 12,
      child: IgnorePointer(
        // Overlay entry bez Scaffoldu → vlastní Material pro styl textu.
        child: Material(
          type: MaterialType.transparency,
          child: MgStickySlide(
          visible: _shown,
          from: AxisDirection.up,
          child: Semantics(
            liveRegion: true,
            label: '$title. $sub',
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('offline-strip-v2'),
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              decoration: BoxDecoration(
                color: MgColors.nightA(0.94),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MgColors.white(0.10)),
                boxShadow: MgShadows.dark,
              ),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: MgColors.white(0.10), shape: BoxShape.circle),
                  child: const Center(child: MgIcon(MgIcons.wifiOff, size: 18, color: MgColors.onDark)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: MgType.title.copyWith(fontSize: 14, color: MgColors.onDark)),
                    Text(sub, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
