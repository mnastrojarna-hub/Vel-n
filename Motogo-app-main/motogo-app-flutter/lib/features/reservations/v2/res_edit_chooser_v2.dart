import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// What the customer wants to change (V22 edit chooser "Co chceš změnit?").
/// extend / shorten / move / swap = today's four tabs; time / place / moto
/// / gear = the sections today's extend tab shows on one page.
enum ResEditIntent { extend, shorten, move, swap, time, place, moto, gear }

/// The old tab each intent lives in (time / place / moto / gear = the
/// sections of the extend / shorten tabs).
String? resEditTabOf(ResEditIntent i) => switch (i) {
      ResEditIntent.extend => 'extend',
      ResEditIntent.shorten => 'shorten',
      ResEditIntent.move => 'move',
      ResEditIntent.swap => 'swap',
      _ => null,
    };

String resEditIntentTitle(AppTranslations tr, ResEditIntent i) => switch (i) {
      ResEditIntent.extend => tr.tr('v2ResIntExtend'),
      ResEditIntent.shorten => tr.tr('v2ResIntShorten'),
      ResEditIntent.move => tr.tr('moveChangePlace'),
      ResEditIntent.swap => tr.tr('swap.tab'),
      ResEditIntent.time => tr.tr('v2ResIntTime'),
      ResEditIntent.place => tr.tr('v2ResIntPlace'),
      ResEditIntent.moto => tr.tr('v2ResIntMoto'),
      ResEditIntent.gear => tr.tr('v2ResIntGear'),
    };

String _sub(AppTranslations tr, ResEditIntent i) => switch (i) {
      ResEditIntent.extend => tr.tr('v2ResIntExtendSub'),
      ResEditIntent.shorten => tr.tr('v2ResIntShortenSub'),
      ResEditIntent.move => tr.tr('v2ResIntMoveSub'),
      ResEditIntent.swap => tr.tr('v2ResIntSwapSub'),
      ResEditIntent.time => tr.tr('v2ResIntTimeSub'),
      ResEditIntent.place => tr.tr('v2ResIntPlaceSub'),
      ResEditIntent.moto => tr.tr('v2ResIntMotoSub'),
      ResEditIntent.gear => tr.tr('v2ResIntGearSub'),
    };

String _icon(ResEditIntent i) => switch (i) {
      ResEditIntent.extend => MgIcons.plus,
      ResEditIntent.shorten => MgIcons.shrink,
      ResEditIntent.move => MgIcons.calendarCheck,
      ResEditIntent.swap => MgIcons.swap,
      ResEditIntent.time => MgIcons.clock,
      ResEditIntent.place => MgIcons.pin,
      ResEditIntent.moto => MgIcons.moto,
      ResEditIntent.gear => MgIcons.helmet,
    };

/// Chooser grid: only the intents today's screen offers for this booking
/// (move / swap / sections under the same conditions as today).
class ResEditChooserV2 extends StatelessWidget {
  final List<ResEditIntent> intents;
  final ValueChanged<ResEditIntent> onPick;
  const ResEditChooserV2({super.key, required this.intents, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('v2ResEditWhatSub'), style: MgType.body.copyWith(color: MgColors.lead)),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < intents.length; i++)
              SizedBox(
                width: w,
                child: MgReveal(
                  index: i,
                  child: _Tile(
                    icon: _icon(intents[i]),
                    title: resEditIntentTitle(tr, intents[i]),
                    sub: _sub(tr, intents[i]),
                    onTap: () => onPick(intents[i]),
                  ),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $sub',
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MgColors.tintFeatureA, MgColors.surface],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            MgIcon(icon, size: 22, color: MgColors.link),
            const SizedBox(height: 8),
            Text(title, style: MgType.title.copyWith(color: MgColors.ink)),
            const SizedBox(height: 2),
            Text(sub, style: MgType.small.copyWith(color: MgColors.meta)),
          ]),
        ),
      ),
    );
  }
}
