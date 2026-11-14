import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_chrome_lift.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_hero_photo.dart';
import '../../../core/v2/motion/mg_ken_burns.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_branch_chip.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/widgets/net_image.dart';
import '../moto_model.dart';
import 'bike_screen_card_parts_v2.dart';
import 'bike_screen_video_layer_v2.dart';
import 'bike_screen_video_stage_v2.dart';
import 'catalog_fit.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';

/// Full-screen photo card of the v2 Motorky list (board `MotoKatalog` `.kc`):
/// photo pager (swipe / side tap zones, segments), availability pill,
/// category · licence · branch, name, "Základní údaje" chips, the card price
/// and the rank CTA. EVERY tap target opens the detail through [onOpen] —
/// the caller's existing logic (sibling ids + `context.push('/moto/:id')`) —
/// except the CTA when the caller gives [onCta] (dates set → REZERVOVAT).
/// One bike per screen (owner 2026-11-08 "vždycky motorka je na celou
/// stránku"): the lists give it the whole folded viewport as [height] and
/// the status-bar inset as [topInset] — the top controls (photo segments,
/// availability pill, side tap zones) sit below the status bar, and on a
/// tall card the contained photo rides in the upper part, clear of the
/// caption block. Photo first, then the bike's first video, looped and
/// muted (owner v5.0.1, [BikeVideoStage]: settled ~5 s, Wi-Fi only, else
/// "Pustit video" under the chip); the branch chip sits in the photo's
/// top-right corner, level with the availability pill (when "name · mode"
/// does not fit there, the chip shows the name and the mode joins the tags).
class MotoCardFullV2 extends StatefulWidget {
  final Motorcycle moto;
  final CatCardPrice price;

  /// Pill text ("Volná v termínu" / "Dnes volná") or null.
  final String? availability;

  /// The live ping on the availability dot + looping CTA (first card only).
  final bool live;
  final String ctaLabel;
  final VoidCallback onOpen;

  /// CTA action; null = [onOpen].
  final VoidCallback? onCta;
  final double height;

  /// Status-bar inset over the card's top edge (0 = none).
  final double topInset;

  /// A slot under the caption shown only with the bars unfolded (Domů's
  /// scroll-to-top): the caption rides above the nav AND it (`MgChromeLift`).
  final double liftExtra;

  const MotoCardFullV2({
    super.key,
    required this.moto,
    required this.price,
    required this.availability,
    required this.ctaLabel,
    required this.onOpen,
    this.onCta,
    this.live = false,
    this.height = 560,
    this.topInset = 0,
    this.liftExtra = 0,
  });

  @override
  State<MotoCardFullV2> createState() => _MotoCardFullV2State();
}

class _MotoCardFullV2State extends State<MotoCardFullV2> {
  final PageController _pc = PageController();
  int _page = 0;

  List<String> get _images {
    final m = widget.moto;
    if (m.images.isNotEmpty) return m.images;
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) return [m.imageUrl!];
    return const [];
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _flip(int delta) {
    final n = _images.length;
    if (n < 2 || !_pc.hasClients) return;
    final next = (_page + delta).clamp(0, n - 1);
    if (next == _page) return;
    if (MgMotion.reduced(context)) {
      _pc.jumpToPage(next);
    } else {
      _pc.animateToPage(next, duration: MgMotion.sheet, curve: MgMotion.out);
    }
  }

  // Upper part of the card: the bottom third carries tags, name and price.
  Widget _fallback() => Container(
        color: MgColors.panel,
        alignment: const Alignment(0, -0.4),
        child: MgIcon(MgIcons.moto, size: 56, color: MgColors.onDarkFloor),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = widget.moto;
    final imgs = _images;
    final multi = imgs.length > 1;
    // The old card's "Základní údaje": up to 6 (Velín short_desc_fields).
    final specs = m.shortDescItems(tr.tr).take(6).map((e) => e.card).toList();
    final lic = catLicenseLabel(tr, m);
    final branch = mgBikeBranchChipLabel(tr, m);
    final short = mgBranchShortName(m.branchName, m.branchCity);
    final chipMax = mgBranchChipMaxWidth(MediaQuery.sizeOf(context).width,
        leftPill: widget.availability == null ? 0 : _pillWidth(context, widget.availability!));
    // The mode word leaves the chip only when the chip has to shorten.
    final modeTag = branch == null || MgBranchChip(label: branch, shortLabel: short, maxWidth: chipMax).fitted(context) == branch
        ? null
        : bikeCardModeTag(tr, m);
    final top = widget.topInset;
    // A full-screen card: the photo in the upper part, above the caption.
    final photoAlign = widget.height > 640 ? const Alignment(0, -0.4) : Alignment.center;
    // [height] is the MINIMUM: with large text / long words the card grows
    // so the bottom block (tags, name, chips, price, CTA) is never pushed
    // out over the top edge (it is the only non-positioned child).
    return BikeVideoStage(
      // One stage per bike: a recycled card never shows another bike's button.
      key: ValueKey('bike-video-stage-${m.id}'),
      videos: m.videos,
      builder: (context, video) => Semantics(
        container: true,
        label: m.model,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.height),
          child: ColoredBox(
            color: MgColors.night,
            child: Stack(alignment: AlignmentDirectional.bottomStart, children: [
              // Darkened cover copy behind the whole (contain) photo — no blur
              // filter in lists (low-end Android, PLAN §6.2 #10).
              if (imgs.isNotEmpty)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: Stack(fit: StackFit.expand, children: [
                      // CB-15: dark placeholder + 180 ms cross-fade per photo.
                      AnimatedSwitcher(
                        duration: MgMotion.of(context, MgMotion.color),
                        child: KeyedSubtree(
                          key: ValueKey(_page),
                          child: MgImage(imgs[_page.clamp(0, imgs.length - 1)],
                              thumbWidth: 400,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: const ColoredBox(color: MgColors.panel),
                              error: _fallback()),
                        ),
                      ),
                      ColoredBox(color: MgColors.nightA(0.62)),
                    ]),
                  ),
                ),
              if (imgs.isEmpty)
                Positioned.fill(child: GestureDetector(onTap: widget.onOpen, child: _fallback()))
              else
                Positioned.fill(
                  child: BikePhotoFade(
                    video: video,
                    child: PageView.builder(
                      controller: _pc,
                      itemCount: imgs.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) {
                        // CB-14: the first photo flies into the detail hero;
                        // CB-28: Ken Burns once on the first card of the list.
                        Widget img = MgHeroPhoto(
                          tag: mgHeroTagMoto(m.id),
                          enabled: i == 0,
                          child: MgImage(
                            imgs[i],
                            thumbWidth: 900,
                            fit: BoxFit.contain,
                            alignment: photoAlign,
                            width: double.infinity,
                            placeholder: const SizedBox.expand(),
                            error: _fallback(),
                          ),
                        );
                        if (i == 0 && widget.live) img = MgKenBurns(sessionKey: 'motorky-card-${m.id}', child: img);
                        return GestureDetector(onTap: widget.onOpen, child: img);
                      },
                    ),
                  ),
                ),
              if (m.videos.isNotEmpty) Positioned.fill(child: BikeVideoLayer(video: video, alignment: photoAlign)),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          MgColors.nightA(0.55),
                          MgColors.nightA(0),
                          MgColors.nightA(0),
                          MgColors.nightA(0.6),
                          MgColors.nightA(0.96),
                        ],
                        stops: const [0, 0.15, 0.5, 0.7, 1],
                      ),
                    ),
                  ),
                ),
              ),
              if (multi) ...[
                Positioned(
                  top: top + 8,
                  left: 12,
                  right: 12,
                  child: ExcludeSemantics(
                    child: Row(children: [
                      for (var i = 0; i < imgs.length; i++)
                        Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i == _page ? MgColors.onDark : MgColors.white(0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                _zone(left: true, label: tr.tr('v2CatPhotoPrev')),
                _zone(left: false, label: tr.tr('v2CatPhotoNext')),
              ],
              if (widget.availability != null)
                Positioned(top: top + 20, left: 12, child: BikeCardAvailabilityPill(text: widget.availability!, live: widget.live)),
              // Where the bike is (owner v5.0.1): the neon chip, top right.
              if (branch != null)
                Positioned(
                  top: top + 21,
                  right: 12,
                  child: IgnorePointer(child: MgBranchChip(label: branch, shortLabel: short, maxWidth: chipMax)),
                ),
              // Off the bike: top right, under the chip.
              if (m.videos.isNotEmpty)
                Positioned(
                  top: top + (branch == null ? 17 : 55),
                  right: 12,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 24),
                    child: BikeVideoPlayButton(video: video),
                  ),
                ),
              // With the bars shown the body is a nav row shorter than the
              // card: the caption rides above the nav (and the strips).
              MgChromeLift(
                room: widget.height,
                extra: widget.liftExtra,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, top + 60, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    IgnorePointer(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (m.category != null && m.category!.isNotEmpty)
                            BikeCardTag(catCategoryLabel(tr, m.category!).toUpperCase(), neon: true),
                          if (lic.isNotEmpty)
                            // J5: red + "tvůj ŘP nestačí" when the licence
                            // does not cover the bike (list / filter unchanged).
                            Consumer(
                              builder: (context, ref, _) => catLicenceFails(ref, m)
                                  ? BikeCardTag('$lic · ${tr.tr('coLicNotEnough')}', bad: true)
                                  : BikeCardTag(lic),
                            ),
                          // The old card's "{kW} KW" badge.
                          if (m.powerKw != null) BikeCardTag('${m.powerKw} KW'),
                          if (modeTag != null) BikeCardTag(modeTag),
                        ]),
                        const SizedBox(height: 8),
                        Text(m.model,
                            style: MgType.h1.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 18)])),
                        if (specs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in specs) BikeCardSpecChip(s)]),
                        ],
                        const SizedBox(height: 10),
                      ]),
                    ),
                    LayoutBuilder(builder: (context, c) {
                      // Price + CTA side by side only when the price ("2 727 Kč
                      // /Tag") fits next to the button; otherwise the button goes
                      // full width under the price (no number split in half).
                      final narrow = _priceWidth(context, widget.price) + 12 + _ctaWidth(context, widget.ctaLabel) > c.maxWidth;
                      Widget cta(bool expand) => MgFabAvoid(
                            child: MgCta(
                              label: widget.ctaLabel,
                              onTap: widget.onCta ?? widget.onOpen,
                              size: MgCtaSize.sm48,
                              expand: expand,
                              arrow: true,
                              loop: widget.live,
                              semanticLabel: '${widget.ctaLabel} · ${m.model}',
                            ),
                          );
                      if (narrow) {
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                          IgnorePointer(child: BikeCardPriceBlock(price: widget.price)),
                          const SizedBox(height: 12),
                          cta(true),
                        ]);
                      }
                      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(child: IgnorePointer(child: BikeCardPriceBlock(price: widget.price))),
                        const SizedBox(width: 12),
                        cta(false),
                      ]);
                    }),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// [BikeCardAvailabilityPill]: 12 + ping 8 + 8 + text + 12.
  static double _pillWidth(BuildContext context, String text) =>
      catLineWidth(context, text, DefaultTextStyle.of(context).style.merge(MgType.small.copyWith(fontWeight: FontWeight.w700))) + 40;

  static double _priceWidth(BuildContext context, CatCardPrice p) {
    final base = DefaultTextStyle.of(context).style;
    return catLineWidth(context, p.value, base.merge(MgType.tab(MgType.h1))) +
        (p.unit == null ? 0 : catLineWidth(context, ' ${p.unit}', base.merge(MgType.body.copyWith(fontWeight: FontWeight.w700))));
  }

  /// MgCta sm48: label caps + 2 × 12 padding + border + arrow (+ a rank
  /// glyph allowance).
  static double _ctaWidth(BuildContext context, String label) =>
      catLineWidth(context, label.toUpperCase(), DefaultTextStyle.of(context).style.merge(MgType.ctaCompact)) + 24 + 3 + 26 + 26;

  Widget _zone({required bool left, required String label}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: widget.topInset + 64,
        bottom: widget.height * 0.42,
        width: 72,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _flip(left ? -1 : 1)),
        ),
      );
}

