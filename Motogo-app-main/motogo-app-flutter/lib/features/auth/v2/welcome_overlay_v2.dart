import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/motion/mg_once_progress.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../loyalty/loyalty_provider.dart';

/// The welcome after registration takes as long as the old one.
const kWelcomeV2Duration = Duration(milliseconds: 2800);

/// v2 welcome (Prihlaseni board "Hotovo"): same route kind, timer (2.8 s),
/// haptic and tap-anywhere close as `MotoWelcomeOverlay.show`; returns when
/// it closes.
Future<void> showWelcomeOverlayV2(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: 'welcome',
    transitionDuration: MgMotion.of(context, const Duration(milliseconds: 150)),
    pageBuilder: (_, __, ___) => const WelcomeOverlayV2(),
  );
}

class WelcomeOverlayV2 extends StatefulWidget {
  const WelcomeOverlayV2({super.key});

  @override
  State<WelcomeOverlayV2> createState() => _WelcomeOverlayV2State();
}

class _WelcomeOverlayV2State extends State<WelcomeOverlayV2> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    Future.delayed(kWelcomeV2Duration, _close);
  }

  void _close() {
    if (_closed || !mounted) return;
    if (!Navigator.of(context).canPop()) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return MgStatusBar(
      dark: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Material(
          color: MgColors.night,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, bottom + 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: MgV2Back(onTap: _close, close: true, style: MgBackStyle.dark),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [
                    const SizedBox(height: 32),
                    const MgToneDisc(tone: MgTone.ok, size: 120, dark: true),
                    const SizedBox(height: 28),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(tr.tr('registerComplete'),
                          textAlign: TextAlign.center,
                          style: MgType.h1.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: MgColors.onDark)),
                    ),
                    const SizedBox(height: 8),
                    Text(tr.tr('v2UxAsmWelcome'),
                        textAlign: TextAlign.center,
                        style: MgType.body.copyWith(fontSize: 15, color: MgColors.onDarkLead)),
                    const SizedBox(height: 24),
                    const _RankCard(),
                  ]),
                ),
              ),
              MgOnceProgress(
                duration: kWelcomeV2Duration,
                curve: Curves.linear,
                builder: (_, v) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 2,
                      backgroundColor: MgColors.white(0.12),
                      color: MgColors.neon,
                    ),
                  ),
                ),
              ),
              MgCta(label: tr.tr('continueBtn'), onTap: _close, arrow: true),
              const SizedBox(height: 10),
              Text(tr.tr('v2UxAsmTapAnywhere'),
                  textAlign: TextAlign.center,
                  style: MgType.micro.copyWith(fontSize: 12, color: MgColors.onDarkMeta)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "TVŮJ STARTOVNÍ RANK": the customer's ring + rank chip + level line from
/// the existing loyalty status; hidden until it is known (never a guess).
class _RankCard extends ConsumerWidget {
  const _RankCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final s = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final name = RankCopy.name(tr, s.level, s.rankName);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MgColors.white(0.14)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MgLogoRing(size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('v2UxAsmStartRank').toUpperCase(),
                style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.neon)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MgRankChip(label: '$name · −${s.percent}\u00A0%'),
            ),
            const SizedBox(height: 8),
            Text(tr.trArgs('v2RankLevelLine', {'level': s.level, 'pct': s.percent}),
                style: MgType.small.copyWith(color: MgColors.onDarkLead)),
          ]),
        ),
      ]),
    );
  }
}
