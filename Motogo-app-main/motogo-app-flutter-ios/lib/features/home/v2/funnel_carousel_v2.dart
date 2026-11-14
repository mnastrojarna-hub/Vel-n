import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/motion/mg_hero_photo.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_branch_chip.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';
import 'funnel_provider.dart';
import 'home_fit.dart';
import 'home_ticket_parts.dart';

export 'funnel_slots_v2.dart';

/// One bike of the funnel carousel (V22 `.fc`): full-bleed photo with a
/// scrim, the availability pill top left ("● Volná v termínu" / "Volná
/// dnes" — ping only on the centred card — or "Volná od 26. 3."), the
/// licence / "Znovu" badge under it, the neon branch chip top right (owner
/// v5.0.1), name + category, the price ("Tvoje cena · n dny" + total, or
/// "od X Kč/den" without dates) + struck list price. The whole photo opens
/// the bike detail.
class FunnelBikeCard extends StatelessWidget {
  final Motorcycle moto;
  final bool center;
  final String? badge;
  final bool again;
  final String priceLabel;
  final String price;
  final String? listPrice;
  final VoidCallback onTap;

  /// Availability pill text (null = no pill); [availLive] = a free-now dot
  /// ("Volná v termínu" / "Volná dnes"), else a calendar ("Volná od …").
  final String? avail;
  final bool availLive;

  /// "Obsazená v termínu" (dates given, nothing free): amber calendar.
  final bool availBusy;

  /// "/den" after an "od" price (no dates).
  final String? unit;

  /// false = "Volná v termínu" dot static: another live indicator (ride
  /// recording) already runs on Domů (DESIGN_V2 §1.3 — one live indicator).
  final bool ping;

  const FunnelBikeCard({
    super.key,
    required this.moto,
    required this.center,
    this.ping = true,
    required this.badge,
    required this.again,
    required this.priceLabel,
    required this.price,
    required this.listPrice,
    required this.onTap,
    required this.avail,
    this.availLive = true,
    this.availBusy = false,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cat = homeCategoryKey(moto.category);
    // Pobočka je štítek vpravo nahoře (v5.0.1), pod názvem jen kategorie.
    final meta = cat.isEmpty ? '' : tr.tr(cat);
    final branchLabel = mgBikeBranchChipLabel(tr, moto);
    final shown = unit == null ? price : '$price$unit';
    final reduced = MgMotion.reduced(context);
    // Sdílená fotka → detail motorky jen z karty uprostřed (V2 §5.11 Hero).
    Widget photo = MgHeroPhoto(
      tag: mgHeroTagMoto(moto.id),
      enabled: center,
      child: HomePhoto(url: moto.displayImage, thumbWidth: 900),
    );
    if (!reduced) {
      // One-shot Ken Burns on the centred card (8 s, ends at 1.06); a card
      // leaving the centre eases back to 1 over 300 ms (no scale jump).
      photo = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: center ? 1.06 : 1),
        duration: center ? MgMotion.kenBurns : MgMotion.pager,
        // One curve both ways: changing it would re-evaluate the running tween.
        curve: Curves.easeOut,
        builder: (_, s, child) => Transform.scale(key: const ValueKey('funnel-kb'), scale: s, child: child),
        child: photo,
      );
    }
    return Semantics(
      button: true,
      label: [moto.model, if (branchLabel != null) branchLabel, if (meta.isNotEmpty) meta, if (avail != null) avail!, '$priceLabel $shown']
          .join(', '),
      excludeSemantics: true,
      child: MgPress(
        scale: 0.99,
        onTap: onTap,
        child: LayoutBuilder(builder: (context, box) {
          // Nízká fotka (≤ 170: telefon < 800 dp): štítky jen v JEDNOM řádku
          // (dostupnost + pobočka), „Znovu" jde k názvu, štítek ŘP odpadne —
          // nic nepřekryje název motorky.
          final compact = box.maxHeight < 170;
          final lic = compact && !again ? badge : null;
          return Stack(fit: StackFit.expand, children: [
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
            // Vlevo dostupnost + pod ní štítek ŘP / „Znovu", vpravo pobočka.
            child: _TopRow(
              ping: ping,
              avail: avail,
              availLive: availLive,
              availBusy: availBusy,
              center: center,
              badge: compact ? null : badge,
              again: again,
              branch: branchLabel,
              branchShort: mgBranchShortName(moto.branchName, moto.branchCity),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (compact && again && badge != null)
                    MgWordFit(
                      minScale: 0.7,
                      child: Text(badge!.toUpperCase(),
                          key: const ValueKey('funnel-again-inline'),
                          maxLines: 1,
                          softWrap: false,
                          style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon, letterSpacing: 0.6)),
                    ),
                  // Název celý — raději menší než rozdělené slovo („Roya|l").
                  MgWordFit(
                    minScale: 0.7,
                    fitLines: 2,
                    child: Text(homeNoOrphan(moto.model),
                        maxLines: 2,
                        style: MgType.section.copyWith(
                            color: MgColors.onDark,
                            shadows: [Shadow(color: MgColors.black(0.55), blurRadius: 10, offset: const Offset(0, 2))])),
                  ),
                  if (meta.isNotEmpty || lic != null) ...[
                    const SizedBox(height: 2),
                    // Kategorie celá, raději menší; když se nevejde ani
                    // zmenšená (úzký telefon, velké písmo), odpadne. Nízká
                    // fotka: štítek ŘP sem za kategorii (na fotce není místo).
                    LayoutBuilder(builder: (context, c) {
                      final style = MgType.meta.copyWith(color: MgColors.white(0.86));
                      final small = style.copyWith(fontSize: style.fontSize! * 0.75);
                      bool fits(String x) => x.isNotEmpty && homeLinesFitIn(context, x, small, c.maxWidth, 1);
                      final both = [if (meta.isNotEmpty) meta, if (lic != null) lic].join(' · ');
                      final text = fits(both) ? both : (fits(meta) ? meta : null);
                      if (text == null) return const SizedBox.shrink();
                      return MgWordFit(
                        minScale: 0.75,
                        child: Text(text, key: const ValueKey('funnel-meta'), maxLines: 1, softWrap: false, style: style),
                      );
                    }),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              // Cena nejvýš na půl šířky (zmenší se), název má vždy místo.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (box.maxWidth - 28) * 0.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomRight,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(mgNbsp(priceLabel), style: MgType.micro.copyWith(color: MgColors.neonText)),
                MgBump(
                  trigger: price,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: mgNbsp(price)),
                      if (unit != null)
                        TextSpan(text: mgNbsp(unit!), style: MgType.small.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    style: MgType.tab(MgType.h2.copyWith(
                        fontWeight: FontWeight.w900,
                        color: MgColors.neon,
                        shadows: [Shadow(color: MgColors.neonA(0.35), blurRadius: 14)])),
                  ),
                ),
                if (listPrice != null)
                  Text(mgNbsp(listPrice!),
                      style: MgType.tab(MgType.meta.copyWith(
                          fontWeight: FontWeight.w600,
                          color: MgColors.white(0.62),
                          decoration: TextDecoration.lineThrough,
                          decorationColor: MgColors.white(0.62)))),
              ]),
                ),
              ),
            ]),
          ),
        ]);
        }),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final String? avail;
  final bool availLive;
  final bool availBusy;
  final bool center;
  final String? badge;
  final bool again;
  final bool ping;
  final String? branch;
  final String? branchShort;
  const _TopRow({
    required this.avail,
    required this.availLive,
    this.availBusy = false,
    required this.center,
    required this.badge,
    required this.again,
    required this.ping,
    required this.branch,
    required this.branchShort,
  });

  static final _freeStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark);
  static final _badgeStyle = MgType.micro.copyWith(height: 1.15, fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    final a = avail, b = badge, br = branch;
    final pills = <Widget>[
      if (a != null)
        _GlassPill(
          key: const ValueKey('funnel-avail'),
          border: availBusy ? MgColors.warnDark.withValues(alpha: 0.5) : MgColors.neonA(0.42),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (availLive)
              MgPing(size: 7, color: MgColors.neon, active: center && ping)
            else if (availBusy)
              const MgIcon(MgIcons.calendarX, size: 13, color: MgColors.warnDark)
            else
              const MgIcon(MgIcons.calendarCheck, size: 13, color: MgColors.neon),
            const SizedBox(width: 6),
            Flexible(
              child: MgWordFit(
                minScale: 0.7,
                child: Text(a, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: _freeStyle),
              ),
            ),
          ]),
        ),
      if (b != null)
        _GlassPill(
          border: again ? MgColors.neonA(0.42) : MgColors.white(0.25),
          // Celý štítek i se skupinou ŘP („A2"): raději menší, jinak 2 řádky.
          child: MgWordFit(
            minScale: 0.8,
            fitLines: 1,
            child: Text(b, maxLines: 2, style: _badgeStyle.copyWith(color: again ? MgColors.neonText : MgColors.onDark)),
          ),
        ),
    ];
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < pills.length; i++) ...[if (i > 0) const SizedBox(height: 6), pills[i]],
    ]);
    if (br == null) return Align(alignment: Alignment.topLeft, child: left);
    return LayoutBuilder(builder: (context, c) {
      // Štítek dostupnosti dostane aspoň místo na svůj text zmenšený na
      // 75 % (jinak by se useknul), pobočka zbytek (min. 110 — pak jen
      // název bez režimu, v nouzi zkrácený); nic se nepřekryje.
      var leftW = 0.0;
      if (a != null || b != null) {
        var need = 96.0;
        if (a != null) {
          final tp = TextPainter(
            text: TextSpan(text: a, style: DefaultTextStyle.of(context).style.merge(_freeStyle)),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          need = tp.width * 0.75 + 37;
          tp.dispose();
        }
        leftW = need.clamp(96.0, c.maxWidth * 0.58);
      }
      final chipMax = (c.maxWidth - 12 - leftW).clamp(110.0, 250.0);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Align(alignment: Alignment.topLeft, child: left)),
        const SizedBox(width: 12),
        MgBranchChip(label: br, shortLabel: branchShort, maxWidth: chipMax),
      ]);
    });
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  final Color border;
  const _GlassPill({super.key, required this.child, required this.border});

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

/// [name] with its last word glued to the one before when it is only 1–2
/// characters ("Benelli TRK 502 X" never leaves a lone "X" on line two).
String homeNoOrphan(String name) {
  final i = name.lastIndexOf(' ');
  if (i <= 0 || name.length - i - 1 > 2) return name;
  return '${name.substring(0, i)}\u00A0${name.substring(i + 1)}';
}
