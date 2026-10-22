import 'package:flutter/material.dart';

import '../../../../core/friendly_error.dart';
import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/motion/mg_animated_size.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_chips.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/widgets/error_feedback.dart' show openFixSettings;
import '../../ride_recorder.dart' show RideRecorderState;

/// The four Moje sub-screens (V22 Zazitky): Jízdy and Uložené trasy share
/// the old first tab, Objevená místa = old tab 1, Historie = old tab 2.
enum MojeSub { rides, saved, places, history }

/// Ride list filter (UI only, on the same list): all / with a MotoGo
/// rental / own bike.
enum RideFilter { all, motogo, private }

/// Horizontal chip row of the sub-screens with counts (null = unknown).
class MojeSubChipsV2 extends StatelessWidget {
  final MojeSub value;
  final ValueChanged<MojeSub> onChanged;
  final Map<MojeSub, int?> counts;
  const MojeSubChipsV2({super.key, required this.value, required this.onChanged, required this.counts});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    const icons = {
      MojeSub.rides: MgIcons.bike,
      MojeSub.saved: MgIcons.bookmark,
      MojeSub.places: MgIcons.pin,
      MojeSub.history: MgIcons.history,
    };
    const keys = {
      MojeSub.rides: 'v2RideSubRides',
      MojeSub.saved: 'v2RideSubSaved',
      MojeSub.places: 'v2RideSubPlaces',
      MojeSub.history: 'v2RideSubHistory',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final s in MojeSub.values) ...[
          if (s != MojeSub.rides) const SizedBox(width: 8),
          MgFilterChip(
            label: tr.tr(keys[s]!),
            icon: icons[s],
            count: counts[s],
            selected: s == value,
            onTap: () => onChanged(s),
          ),
        ],
      ]),
    );
  }
}

/// "Záznam jízdy" row (board `.recs`): status line, ⓘ (the existing hint),
/// the EXISTING auto-record switch; tapping the row opens the recorder.
class MojeRecordRowV2 extends StatelessWidget {
  final RideRecorderState rec;
  final bool hintOpen;
  final VoidCallback onHint;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onOpen;
  const MojeRecordRowV2({
    super.key,
    required this.rec,
    required this.hintOpen,
    required this.onHint,
    required this.onEnabled,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final sub = rec.recording
        ? tr.tr(rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto')
        : tr.tr(rec.enabled ? 'v2RideAutoOn' : 'v2RideAutoOff');
    final tile = Semantics(
      button: true,
      label: '${tr.tr('rideRecordTitle')}, $sub',
      hint: tr.tr('v2RideRecOpenA11y'),
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: rec.recording
                    ? MgPing(size: 10, color: MgColors.sosDot, active: !MgMotion.reduced(context))
                    : const MgIcon(MgIcons.recordDot, size: 22, color: MgColors.neon),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  MgWordFit(minScale: 0.75, child: Text(tr.tr('rideRecordTitle'), style: MgType.title.copyWith(color: MgColors.ink))),
                  if (rec.recording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: MgColors.errBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(tr.tr('rideRecording'),
                          style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.err)),
                    ),
                ]),
                MgWordFit(minScale: 0.85, child: Text(sub, style: MgType.small.copyWith(color: MgColors.meta))),
              ]),
            ),
          ]),
        ),
      ),
    );
    final controls = <Widget>[
      MgIconButton(
        icon: MgIcons.info,
        style: MgIconButtonStyle.light,
        iconColor: MgColors.link,
        semanticLabel: tr.tr('v2RideRecInfoA11y'),
        onTap: onHint,
      ),
      Semantics(
        label: tr.tr('v2RideAutoTitle'),
        child: Switch(
          value: rec.enabled,
          onChanged: onEnabled,
          activeThumbColor: MgColors.onNeon,
          activeTrackColor: MgColors.neon,
          inactiveThumbColor: MgColors.meta,
          inactiveTrackColor: MgColors.well,
          trackOutlineColor: const WidgetStatePropertyAll(MgColors.lineInput),
        ),
      ),
    ];
    return MgCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Úzký telefon: ⓘ a přepínač na druhý řádek, ať má název a stav
        // celou šířku (de „Fahrtaufzeichnung" se jinak lámal uprostřed).
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 340) return Row(children: [Expanded(child: tile), ...controls]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            tile,
            Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
          ]);
        }),
        MgAnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: MgMotion.out,
          alignment: Alignment.topCenter,
          child: hintOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 8, 6),
                  child: MgWell(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr.tr('rideRecordHint'), style: MgType.small.copyWith(color: MgColors.body2)),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// "Záznam jízdy stojí – poloha je vypnutá" (old RideGpsLostBanner): same
/// text and the same "Otevřít nastavení" action, as a T3 warning.
class MojeGpsLostV2 extends StatelessWidget {
  const MojeGpsLostV2({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateBanner(
      tone: MgTone.warn,
      icon: MgIcons.gps,
      title: tr.tr('v2RtRecGps'),
      text: tr.tr('eoRideGpsLost'),
      actions: [
        MgBtnText(
          label: tr.tr('eoOpenSettings'),
          onTap: () => openFixSettings(const FriendlyError(FriendlyKind.locationOff)),
        ),
      ],
    );
  }
}

/// Empty / locked state card (icon disc, title, text, optional action).
class MojeEmptyV2 extends StatelessWidget {
  final String icon;
  final String title;
  final String? text;
  final Widget? action;
  const MojeEmptyV2({super.key, required this.icon, required this.title, this.text, this.action});

  @override
  Widget build(BuildContext context) => MgCard(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(children: [
          MgPop(
            playOnMount: true,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: MgColors.well, shape: BoxShape.circle, border: Border.all(color: MgColors.line)),
              child: Center(child: MgIcon(icon, size: 28, color: MgColors.ink)),
            ),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: MgType.title.copyWith(color: MgColors.ink)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text!, textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}
