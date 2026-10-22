import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/rank/rank_hero.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_model.dart';
import '../../ride_trip.dart' show rideDateRange;
import 'ride_card_v2.dart' show RideLiveBadgeV2;
import 'ride_phase_v2.dart';
import 'ride_track_sketch_v2.dart';

export 'ride_stats_v2.dart' show RideStatsCardV2, rideStatColumns;

/// Dark ride header (board `.rdh`): back, name (tap = the old "Upravit
/// jízdu" dialog), share, delete; date range · bike; tags.
class RideDetailHeaderV2 extends StatelessWidget {
  final UserRide ride;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const RideDetailHeaderV2({
    super.key,
    required this.ride,
    required this.onBack,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled');
    final range = rideDateRange(ride.startedAt, ride.endedAt ?? ride.lastFixAt ?? ride.startedAt);
    final sub = [range, if ((ride.motoName ?? '').isNotEmpty) ride.motoName!].join(' · ');
    final mg = ride.bookingId != null;
    final days = ride.days;
    return RideHeaderShellV2(
      title: name,
      sub: sub,
      onBack: onBack,
      onEdit: onEdit,
      shareLabel: tr.tr('rideShareTitle'),
      deleteLabel: tr.tr('v2RideDelete'),
      onShare: onShare,
      onDelete: onDelete,
      badges: [
        if (ride.isRecording) RideLiveBadgeV2(rideId: ride.id, dark: true),
        RideBadgeV2(
          kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private,
          label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'),
          dark: true,
        ),
        if (ride.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared'), dark: true),
        if (days >= 2) RideBadgeV2(kind: RideBadgeKind.days, label: recDaysV2(tr, days), dark: true),
      ],
    );
  }
}

/// Dark detail header shared by a ride and a trip: back, the name (tap =
/// rename / edit, never split inside a word), share + delete, sub line,
/// tags. r1: on phones narrower than 380 dp the share / delete discs move
/// under the title (next to the tags), so de / pl names keep the width.
class RideHeaderShellV2 extends StatelessWidget {
  final String title;
  final String sub;
  final List<Widget> badges;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final String shareLabel;
  final String deleteLabel;
  const RideHeaderShellV2({
    super.key,
    required this.title,
    required this.sub,
    required this.badges,
    required this.onBack,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.shareLabel,
    required this.deleteLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final actions = [
      MgIconButton(icon: MgIcons.share, semanticLabel: shareLabel, onTap: onShare),
      const SizedBox(width: 4),
      MgIconButton(icon: MgIcons.trash, semanticLabel: deleteLabel, iconColor: MgColors.errDark, onTap: onDelete),
    ];
    return MgRankHero(
      ambientKey: 'ride',
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 380 * MediaQuery.textScalerOf(context).scale(1);
        final name = Semantics(
          button: true,
          label: '$title, ${tr.tr('v2RideEditA11y')}',
          excludeSemantics: true,
          child: MgPress(
            scale: 0.98,
            onTap: onEdit,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Flexible(
                    child: MgWordFit(
                      minScale: 0.7,
                      child: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: MgType.h3.copyWith(color: MgColors.onDark)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 4),
                    child: MgIcon(MgIcons.edit, size: 16, color: MgColors.onDarkMeta),
                  ),
                ]),
              ),
            ),
          ),
        );
        final tags = Wrap(spacing: 6, runSpacing: 6, children: badges);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgV2Back(onTap: onBack, style: MgBackStyle.dark),
            const SizedBox(width: 8),
            Expanded(child: name),
            if (!narrow) ...actions,
          ]),
          Padding(
            padding: EdgeInsets.fromLTRB(narrow ? 4 : 52, 2, 0, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead))),
              const SizedBox(height: 8),
              if (narrow)
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: tags), ...actions])
              else
                tags,
            ]),
          ),
        ]);
      }),
    );
  }
}

/// "Sdílet ostatním" (board `.vis`): the EXISTING visibility switch
/// (disabled while saving, as before).
class RideVisibilityCardV2 extends StatelessWidget {
  final bool isPublic;
  final bool busy;
  final ValueChanged<bool> onChanged;

  /// Trip variant texts (null = the ride's own `rideVisibility*`).
  final String? title;
  final String? onText;
  final String? offText;
  const RideVisibilityCardV2({
    super.key,
    required this.isPublic,
    required this.busy,
    required this.onChanged,
    this.title,
    this.onText,
    this.offText,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: MergeSemantics(
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPublic ? MgColors.tintOk : MgColors.well,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: MgIcon(isPublic ? MgIcons.globe : MgIcons.lock, size: 20, color: isPublic ? MgColors.onTintOk : MgColors.meta)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(minScale: 0.8, child: Text(title ?? tr.tr('rideVisibility'), style: MgType.title.copyWith(color: MgColors.ink))),
              Text((isPublic ? onText : offText) ?? tr.tr(isPublic ? 'rideVisibilityOn' : 'rideVisibilityOff'),
                  style: MgType.small.copyWith(color: MgColors.meta)),
            ]),
          ),
          Switch(
            value: isPublic,
            onChanged: busy ? null : onChanged,
            activeThumbColor: MgColors.onNeon,
            activeTrackColor: MgColors.neon,
            inactiveThumbColor: MgColors.meta,
            inactiveTrackColor: MgColors.well,
            trackOutlineColor: const WidgetStatePropertyAll(MgColors.lineInput),
          ),
        ]),
      ),
    );
  }
}

