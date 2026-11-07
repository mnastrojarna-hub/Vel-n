import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../sos_provider.dart';
import '../sos_timeline_i18n.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// v2 live incident detail (SOS board "Detail incidentu"): amber SOS header,
/// status card (amber chip + rows), photos, "Průběh" with the screen's one
/// live indicator ("● ŽIVĚ" ping, static when reduced), existing actions.
class SosIncidentViewV2 extends StatelessWidget {
  final SosIncident inc;
  final String status;
  final List<(String, String)> rows;
  final AsyncValue<List<SosTimelineEntry>> timeline;
  final Widget Function(Object error) timelineError;
  final VoidCallback onBack;
  final VoidCallback? onReplacement;
  final VoidCallback? onContinue;
  final VoidCallback onMessages;
  const SosIncidentViewV2({
    super.key,
    required this.inc,
    required this.status,
    required this.rows,
    required this.timeline,
    required this.timelineError,
    required this.onBack,
    required this.onReplacement,
    required this.onContinue,
    required this.onMessages,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final id = inc.id.substring(inc.id.length - 8).toUpperCase();
    final eb = MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.link);
    return SosPageV2(
      onBack: onBack,
      header: SosHeaderV2(
        onBack: onBack,
        icon: MgIcons.alert,
        tint: SosTint.amber,
        eyebrow: 'SOS',
        title: tr.tr('sosIncidentTitle'),
        sub: id,
      ),
      sections: [
        SosCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text('${tr.tr('sosIncidentTitle')} #$id', style: MgType.title.copyWith(color: MgColors.ink)),
                _StatusChip(label: status, active: inc.isActive),
              ],
            ),
            for (final r in rows) ...[
              const Divider(height: 20, thickness: 1, color: MgColors.line),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: MgType.small.copyWith(color: MgColors.meta)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.$2,
                      textAlign: TextAlign.end, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                ),
              ]),
            ],
          ]),
        ),
        if (inc.photos.isNotEmpty)
          SosCardV2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr.tr('photoDocumentation').toUpperCase(), style: eb),
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: inc.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => MgPhoto(
                    url: inc.photos[i],
                    width: 72,
                    height: 72,
                    thumbWidth: 216,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ]),
          ),
        SosCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(tr.tr('timelineTitle'), style: MgType.title.copyWith(color: MgColors.ink))),
              if (inc.isActive) ...[
                const MgPing(size: 8, color: MgColors.neonLo),
                const SizedBox(width: 6),
                Text(tr.tr('v2UxAsmLive').toUpperCase(),
                    style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.link)),
              ],
            ]),
            const SizedBox(height: 12),
            timeline.when(
              data: (entries) => entries.isEmpty
                  ? Text(tr.tr('noRecordsYet'), style: MgType.small.copyWith(color: MgColors.meta))
                  : Column(children: [
                      for (var i = 0; i < entries.length; i++) _entry(context, entries[i], i == entries.length - 1),
                    ]),
              loading: () => const MgSkeletonRow(thumb: 12, thumbRadius: 6, lines: 2),
              error: (e, _) => timelineError(e),
            ),
          ]),
        ),
        if (onReplacement != null)
          MgBtnInk(label: tr.tr('replacementMoto').toUpperCase(), icon: MgIcons.bike, onTap: onReplacement),
        if (onContinue != null)
          MgBtnInk(label: tr.tr('continueRiding').toUpperCase(), icon: MgIcons.ride, onTap: onContinue),
        MgBtnGhostLight(label: tr.tr('messagesFromMotoGo'), icon: MgIcons.chat, onTap: onMessages),
      ],
    );
  }

  Widget _entry(BuildContext context, SosTimelineEntry e, bool last) {
    final c = e.createdAt;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 14,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: MgColors.neonLo, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: MgColors.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(localizeSosAction(t(context), e.action),
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              const SizedBox(height: 2),
              Text('${c.hour}:${c.minute.toString().padLeft(2, '0')} · ${c.day}. ${c.month}.',
                  style: MgType.tab(MgType.micro.copyWith(color: MgColors.meta))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  const _StatusChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? MgColors.warnBg : MgColors.tintOk,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? MgColors.warnBorder : MgColors.tintOkBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: active ? MgColors.warn : MgColors.link, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: MgType.micro.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: active ? MgColors.warn : MgColors.onTintOk)),
        ]),
      );
}
