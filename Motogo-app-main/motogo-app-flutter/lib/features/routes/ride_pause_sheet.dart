import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/mg_nav_controls.dart';
import 'ride_pause_actions.dart';
import 'ride_rec_controls.dart';
import 'ride_rec_phase.dart';
import 'ride_recorder.dart';

/// Záznam jízdy v navigaci (starý vzhled): štítek v hlavičce „● REC 12,3" /
/// „❚❚ Pauza" → klepnutí otevře sheet se stavem a tlačítky. Navigaci nic
/// nepřekrývá; bez záznamu se štítek nevykreslí vůbec.
class RideNavRecChip extends ConsumerWidget {
  const RideNavRecChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording) return const SizedBox.shrink();
    final tr = t(context);
    final tone = rideRecTone(rec);
    final paused = rec.isPaused && !rec.isArmed;
    return Semantics(
      button: true,
      label: ridePhaseText(rec, tr),
      hint: tr.tr('rpNavChipHint'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showRidePauseSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoRadius.lg),
                  boxShadow: MotoGoShadows.cardSmall,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (paused)
                    Text('❚❚', style: TextStyle(fontSize: 11, fontWeight: MotoGoTypo.w900, color: tone.fg))
                  else
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: rec.gpsLost ? MotoGoColors.amber : tone.fg, shape: BoxShape.circle),
                    ),
                  const SizedBox(width: 5),
                  Text(rideNavChipText(rec, tr),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet „Záznam jízdy": stav, Pozastavit / Pokračovat, Ukončit (jen
/// vlastní jízda), u výpůjčky vysvětlení, že skončí vrácením motorky.
Future<void> showRidePauseSheet(BuildContext context) {
  // Akce běží v kontextu obrazovky (sheet se po klepnutí zavře).
  final outer = context;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => SafeArea(
      child: Consumer(builder: (c, ref, _) {
        final rec = ref.watch(rideRecorderProvider);
        final tr = t(c);
        if (!rec.recording) {
          // Záznam mezitím skončil (vrácení výpůjčky, Ukončit jinde) — sheet
          // nemá co ovládat, zavře se sám.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (c.mounted && ModalRoute.of(c)?.isCurrent == true) Navigator.of(c).pop();
          });
          return const SizedBox(height: 120);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MgSheetHandle(),
            Text('🛰️ ${tr.tr('rideRecordTitle')}',
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeH3,
                    fontWeight: MotoGoTypo.w900,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 12),
            RideRecStatus(rec: rec),
            if (rec.needsDecision) ...[const SizedBox(height: 10), RideRecDecisionNote(rec: rec)],
            const SizedBox(height: 14),
            RideRecButtons(
              rec: rec,
              onToggle: () {
                Navigator.pop(c);
                if (outer.mounted) rideTogglePause(outer, ref);
              },
              onStop: () {
                Navigator.pop(c);
                if (outer.mounted) rideStopWithFeedback(outer, ref);
              },
            ),
            if (!rec.needsDecision) ...[
              const SizedBox(height: 10),
              Text(rec.manual ? rideHintText(rec, tr) : tr.tr('rpRentalEndsHint'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g500,
                      height: 1.35,
                      decoration: TextDecoration.none)),
            ],
          ]),
        );
      }),
    ),
  );
}
