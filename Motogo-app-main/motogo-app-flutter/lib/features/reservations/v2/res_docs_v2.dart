import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/res_modification_history.dart';

/// "Historie rezervace" — a collapsed row that opens today's
/// `ResModificationHistory` (timeline, changes, SOS, storno) unchanged.
class ResHistoryV2 extends ConsumerStatefulWidget {
  final Reservation res;
  const ResHistoryV2({super.key, required this.res});

  @override
  ConsumerState<ResHistoryV2> createState() => _ResHistoryV2State();
}

class _ResHistoryV2State extends ConsumerState<ResHistoryV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final sos = ref.watch(sosIncidentsProvider(widget.res.id)).valueOrNull ?? <SosIncident>[];
    final n = widget.res.modificationHistory.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: _open,
        label: tr.tr('v2ResHistory'),
        excludeSemantics: true,
        child: MgPress(
          scale: 0.99,
          onTap: () => setState(() => _open = !_open),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(children: [
              const MgIconTileLight(MgIcons.history),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(
                    minScale: 0.8,
                    child: Text(tr.tr('v2ResHistory'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                  ),
                  if (n > 0) Text(tr.trArgs('v2ResHistoryCount', {'n': n}), style: MgType.meta.copyWith(color: MgColors.meta)),
                ]),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: MgMotion.of(context, MgMotion.pop),
                child: const MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.link),
              ),
            ]),
          ),
        ),
      ),
      MgAnimatedSize(
        duration: MgMotion.pop,
        curve: MgMotion.out,
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ResModificationHistory(res: widget.res, sosIncidents: sos),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
