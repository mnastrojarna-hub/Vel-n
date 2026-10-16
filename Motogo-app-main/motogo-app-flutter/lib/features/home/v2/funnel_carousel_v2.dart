import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';
import 'funnel_provider.dart';
import 'home_ticket_parts.dart';

/// One bike of the funnel carousel (V22 `.fc`): full-bleed photo with a
/// scrim, "● Volná v termínu" (ping only on the centred card), licence /
/// "Znovu" badge, name + branch · category, "Tvoje cena · n dny" + price +
/// struck list price. The whole photo opens the bike detail.
class FunnelBikeCard extends StatelessWidget {
  final Motorcycle moto;
  final bool center;
  final String? badge;
  final bool again;
  final String priceLabel;
  final String price;
  final String? listPrice;
  final VoidCallback onTap;

  const FunnelBikeCard({
    super.key,
    required this.moto,
    required this.center,
    required this.badge,
    required this.again,
    required this.priceLabel,
    required this.price,
    required this.listPrice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cat = homeCategoryKey(moto.category);
    final meta = [
      if ((moto.branchName ?? '').trim().isNotEmpty) moto.branchName!.trim(),
      if (cat.isNotEmpty) tr.tr(cat),
    ].join(' · ');
    final reduced = MgMotion.reduced(context);
    Widget photo = HomePhoto(url: moto.displayImage, thumbWidth: 900);
    if (center && !reduced) {
      // One-shot Ken Burns on the centred card (8 s, ends at 1.06).
      photo = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 1.06),
        duration: MgMotion.kenBurns,
        curve: Curves.easeOut,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: photo,
      );
    }
    return Semantics(
      button: true,
      label: '${moto.model}, $meta, $priceLabel $price',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.99,
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          ClipRect(child: photo),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MgColors.nightA(0.6), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.92)],
                stops: const [0, 0.3, 0.46, 1],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            // „Volná v termínu" + štítek ŘP: když se oba nevejdou, dostanou místo
            // podle délky a zmenší se (štítek smí na 2 řádky) — nic se neusekne.
            child: _TopPills(
              free: tr.tr('v2HomeFnFree'),
              center: center,
              badge: badge,
              again: again,
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(moto.model,
                      maxLines: 2,
                      style: MgType.section.copyWith(
                          color: MgColors.onDark,
                          shadows: [Shadow(color: MgColors.black(0.55), blurRadius: 10, offset: const Offset(0, 2))])),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const MgIcon(MgIcons.pin, size: 14, color: MgColors.neon),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.meta.copyWith(color: MgColors.white(0.86))),
                      ),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(priceLabel, style: MgType.micro.copyWith(color: MgColors.neonText)),
                MgBump(
                  trigger: price,
                  child: Text(price,
                      style: MgType.tab(MgType.h2.copyWith(
                          fontWeight: FontWeight.w900,
                          color: MgColors.neon,
                          shadows: [Shadow(color: MgColors.neonA(0.35), blurRadius: 14)]))),
                ),
                if (listPrice != null)
                  Text(listPrice!,
                      style: MgType.tab(MgType.meta.copyWith(
                          fontWeight: FontWeight.w600,
                          color: MgColors.white(0.62),
                          decoration: TextDecoration.lineThrough,
                          decorationColor: MgColors.white(0.62)))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TopPills extends StatelessWidget {
  final String free;
  final bool center;
  final String? badge;
  final bool again;
  const _TopPills({required this.free, required this.center, required this.badge, required this.again});

  static final _freeStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark);
  static final _badgeStyle = MgType.micro.copyWith(height: 1.15, fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    final b = badge;
    final freePill = _GlassPill(
      border: MgColors.neonA(0.42),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MgPing(size: 7, color: MgColors.neon, active: center),
        const SizedBox(width: 6),
        Flexible(
          child: MgWordFit(
            minScale: 0.7,
            child: Text(free, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: _freeStyle),
          ),
        ),
      ]),
    );
    if (b == null) return Row(children: [Flexible(child: freePill)]);
    final badgePill = _GlassPill(
      border: again ? MgColors.neonA(0.42) : MgColors.white(0.25),
      // Celý štítek i se skupinou ŘP („A2"): nejdřív menší na jednom
      // řádku, jinak na dva řádky v mezeře — nikdy useknutý.
      child: MgWordFit(
        minScale: 0.8,
        fitLines: 1,
        alignment: AlignmentDirectional.centerEnd,
        child: Text(b,
            maxLines: 2,
            textAlign: TextAlign.end,
            style: _badgeStyle.copyWith(color: again ? MgColors.neonText : MgColors.onDark)),
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    double w(String text, TextStyle st) {
      final tp = TextPainter(text: TextSpan(text: text, style: base.merge(st)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final v = tp.width;
      tp.dispose();
      return v;
    }

    final wFree = w(free, _freeStyle) + 7 + 6 + 22;
    final wOne = w(b, _badgeStyle) + 22;
    // Štítek smí na 2 řádky → v nouzi mu stačí zhruba půlka (aspoň
    // nejdelší slovo), zbytek místa dostane „Volná v termínu".
    var longest = 0.0;
    for (final x in b.split(' ')) {
      if (x.isNotEmpty) longest = longest > w(x, _badgeStyle) ? longest : w(x, _badgeStyle);
    }
    final wTwo = (longest > (wOne - 22) * 0.55 ? longest : (wOne - 22) * 0.55) + 22;
    // Místo úměrné potřebné šířce: když se oba vejdou, má každý aspoň svou
    // šířku (vzhled beze změny), jinak štítek na 2 řádky a oba se zmenší.
    return LayoutBuilder(builder: (context, c) {
      final wBadge = wFree + 8 + wOne <= c.maxWidth ? wOne : wTwo;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Flexible(flex: wFree.round(), child: Align(alignment: Alignment.centerLeft, child: freePill)),
        const SizedBox(width: 8),
        Flexible(flex: wBadge.round(), child: Align(alignment: Alignment.centerRight, child: badgePill)),
      ]);
    });
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  final Color border;
  const _GlassPill({required this.child, required this.border});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Center(widthFactor: 1, child: child),
      );
}

/// Loading slot of the carousel (one shimmer pass while loading).
class FunnelSkeleton extends StatelessWidget {
  const FunnelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h, [double r = 6]) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: MgColors.white(0.08), borderRadius: BorderRadius.circular(r)),
        );
    return ExcludeSemantics(
      child: MgShimmer(
        highlight: MgColors.white(0.13),
        child: Container(
          color: MgColors.panel,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(120, 26, 999),
            const Spacer(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(170, 18),
                  const SizedBox(height: 8),
                  bar(110, 14),
                ]),
              ),
              bar(96, 26),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Empty / error slot of the carousel (`.fn-emp`): tone disc + title + text.
class FunnelEmptySlot extends StatelessWidget {
  final bool error;
  final String title;
  final String text;
  const FunnelEmptySlot({super.key, required this.error, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [MgColors.panel, MgColors.night],
        ),
      ),
      // Výška podle obsahu (min. 200 v HomeFunnelV2): celé vysvětlení
      // i při velkém písmu, nic se neusekne.
      constraints: const BoxConstraints(minHeight: 200),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Semantics(
        liveRegion: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MgToneDisc(tone: error ? MgTone.err : MgTone.info, size: 48, dark: true, icon: error ? null : MgIcons.calendarX),
          const SizedBox(height: 8),
          MgWordFit(
            minScale: 0.8,
            alignment: Alignment.center,
            child: Text(title, textAlign: TextAlign.center, style: MgType.title.copyWith(color: MgColors.onDark)),
          ),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
        ]),
      ),
    );
  }
}
