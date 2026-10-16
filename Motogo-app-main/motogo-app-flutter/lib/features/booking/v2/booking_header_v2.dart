import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Compact dark rank header of the v2 booking form (board `.rk-hero.bh`):
/// back (dark style, the form's EXISTING back action), title "Rezervace",
/// the bike, and the 3-step progress (`.stp`). The step state is derived
/// only from what the form already knows (dates, validation, sizes) —
/// it decides nothing. No countdown chip (the form has none today).
class BookingHeaderV2 extends StatelessWidget {
  final String bikeName;
  final VoidCallback onBack;

  /// 0 = Termín a předání, 1 = Výbava a velikosti, 2 = Kontrola a platba.
  final int currentStep;

  const BookingHeaderV2({
    super.key,
    required this.bikeName,
    required this.onBack,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgRankHero(
      ambientKey: 'booking',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgV2Back(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('v2BkTitle'), style: MgType.section.copyWith(color: MgColors.onDark)),
                const SizedBox(height: 2),
                Text(bikeName,
                    maxLines: 2,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        BookingStepsV2(current: currentStep),
      ]),
    );
  }
}

/// The 3-step bar: done = ✓ disc, current = neon disc + label pill,
/// future = number disc; the connector fills up to the current step. The
/// pill label is never cut: it shrinks a little to stay on one line, else
/// wraps to two lines (the pill and the bar grow).
class BookingStepsV2 extends StatelessWidget {
  final int current;
  const BookingStepsV2({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final labels = [tr.tr('v2BkStepDates'), tr.tr('v2BkStepGear'), tr.tr('v2BkStepPay')];
    final cur = current.clamp(0, 2);
    final dur = MgMotion.of(context, MgMotion.thumb);
    return Semantics(
      container: true,
      label: tr.trArgs('v2BkStepAria', {'n': cur + 1, 'step': labels[cur]}),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.neonA(0.22)),
        ),
        child: Stack(children: [
          // Connector through the disc centres (the bar grows when the
          // current label needs two lines).
          Positioned(
            left: 18,
            right: 18,
            top: 0,
            bottom: 0,
            child: Center(
              child: SizedBox(
                height: 2,
                width: double.infinity,
                child: LayoutBuilder(builder: (context, c) {
                  return Stack(children: [
                    Container(color: MgColors.white(0.14)),
                    AnimatedContainer(
                      duration: dur,
                      curve: MgMotion.emphasized,
                      width: c.maxWidth * cur / 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [MgColors.neonLo, MgColors.neon]),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              i == cur
                  ? Expanded(child: _StepPill(n: i + 1, label: labels[i]))
                  : _StepDisc(n: i + 1, done: i < cur, aria: '${labels[i]}${i < cur ? ', ${tr.tr('v2BkStepDone')}' : ''}'),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _StepDisc extends StatelessWidget {
  final int n;
  final bool done;
  final String aria;
  const _StepDisc({required this.n, required this.done, required this.aria});

  @override
  Widget build(BuildContext context) => Semantics(
        label: aria,
        child: ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(done ? MgColors.neonA(0.12) : MgColors.white(0.06), MgColors.panel),
              border: Border.all(color: done ? MgColors.neonA(0.6) : MgColors.white(0.14), width: done ? 1.5 : 1),
            ),
            child: done
                ? MgPop(playOnMount: true, child: MgIcon(MgIcons.check, size: 16, color: MgColors.neon, stroke: 2.6))
                : Text('$n', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDarkLead))),
          ),
        ),
      );
}

class _StepPill extends StatelessWidget {
  final int n;
  final String label;
  const _StepPill({required this.n, required this.label});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      label: '$label, ${tr.tr('v2BkStepNow')}',
      child: ExcludeSemantics(
        child: MgEnter(
          trigger: n,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(MgColors.neonA(0.16), MgColors.panel),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.neonA(0.35)),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MgColors.neon,
                  boxShadow: [BoxShadow(color: MgColors.neonA(0.3), spreadRadius: 3)],
                ),
                child: Text('$n', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: MgWordFit(
                    minScale: 0.85,
                    fitLines: 1,
                    child: Text(label,
                        maxLines: 2, style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
