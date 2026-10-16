import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/widgets/net_image.dart';
import '../moto_model.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';

/// Full-screen photo card of the v2 Motorky list (board `MotoKatalog` `.kc`):
/// photo pager (swipe / side tap zones, segments), availability pill,
/// category · licence · branch, name, "Základní údaje" chips, the card price
/// and the rank CTA. EVERY tap target opens the detail through [onOpen] —
/// the caller's existing logic (sibling ids + `context.push('/moto/:id')`).
class MotoCardFullV2 extends StatefulWidget {
  final Motorcycle moto;
  final CatCardPrice price;

  /// Pill text ("Volná v termínu" / "Dnes volná") or null.
  final String? availability;

  /// The live ping on the availability dot + looping CTA (first card only).
  final bool live;
  final String ctaLabel;
  final VoidCallback onOpen;
  final double height;

  const MotoCardFullV2({
    super.key,
    required this.moto,
    required this.price,
    required this.availability,
    required this.ctaLabel,
    required this.onOpen,
    this.live = false,
    this.height = 560,
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
    final specs = m.shortDescItems(tr.tr).take(4).map((e) => e.card).toList();
    final lic = catLicenseLabel(tr, m);
    final branch = m.branchName ?? m.branchCity;
    return Semantics(
      container: true,
      label: m.model,
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: MgColors.night,
          child: Stack(fit: StackFit.expand, children: [
            // Darkened cover copy behind the whole (contain) photo — no blur
            // filter in lists (low-end Android, PLAN §6.2 #10).
            if (imgs.isNotEmpty)
              ExcludeSemantics(
                child: Stack(fit: StackFit.expand, children: [
                  MgImage(imgs[_page.clamp(0, imgs.length - 1)], thumbWidth: 400, fit: BoxFit.cover, error: _fallback()),
                  ColoredBox(color: MgColors.nightA(0.62)),
                ]),
              ),
            if (imgs.isEmpty)
              GestureDetector(onTap: widget.onOpen, child: _fallback())
            else
              PageView.builder(
                controller: _pc,
                itemCount: imgs.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: widget.onOpen,
                  child: MgImage(
                    imgs[i],
                    thumbWidth: 900,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    placeholder: const SizedBox.expand(),
                    error: _fallback(),
                  ),
                ),
              ),
            IgnorePointer(
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
            if (multi) ...[
              Positioned(
                top: 8,
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
              Positioned(top: 20, left: 12, child: _AvailabilityPill(text: widget.availability!, live: widget.live)),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                IgnorePointer(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (m.category != null && m.category!.isNotEmpty)
                        _Tag(catCategoryLabel(tr, m.category!).toUpperCase(), neon: true),
                      if (lic.isNotEmpty) _Tag(lic),
                      if (branch != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          MgIcon(MgIcons.pin, size: 16, color: MgColors.neon),
                          const SizedBox(width: 4),
                          Text(branch, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.white(0.94))),
                        ]),
                    ]),
                    const SizedBox(height: 8),
                    Text(m.model,
                        style: MgType.h1.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 18)])),
                    if (specs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in specs) _SpecChip(s)]),
                    ],
                    const SizedBox(height: 10),
                  ]),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: IgnorePointer(child: _PriceBlock(price: widget.price))),
                  const SizedBox(width: 12),
                  MgFabAvoid(
                    child: MgCta(
                      label: widget.ctaLabel,
                      onTap: widget.onOpen,
                      size: MgCtaSize.sm48,
                      expand: false,
                      arrow: true,
                      loop: widget.live,
                      semanticLabel: '${widget.ctaLabel} · ${m.model}',
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _zone({required bool left, required String label}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 64,
        bottom: widget.height * 0.42,
        width: 72,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _flip(left ? -1 : 1)),
        ),
      );
}

class _AvailabilityPill extends StatelessWidget {
  final String text;
  final bool live;
  const _AvailabilityPill({required this.text, required this.live});

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(child: MgPing(size: 8, color: MgColors.neon, active: live)),
          const SizedBox(width: 8),
          Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark, height: 1)),
        ]),
      );
}

class _Tag extends StatelessWidget {
  final String text;
  final bool neon;
  const _Tag(this.text, {this.neon = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: neon ? MgColors.neon : MgColors.nightA(0.72),
          borderRadius: BorderRadius.circular(6),
          border: neon ? null : Border.all(color: MgColors.white(0.18)),
        ),
        child: Text(text,
            style: MgType.micro.copyWith(
                fontWeight: FontWeight.w800, color: neon ? MgColors.onNeon : MgColors.onDark, letterSpacing: neon ? 0.4 : 0)),
      );
}

class _SpecChip extends StatelessWidget {
  final String text;
  const _SpecChip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: MgColors.white(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.14)),
        ),
        child: Text(text, maxLines: 1, style: MgType.meta.copyWith(color: MgColors.onDarkBody)),
      );
}

class _PriceBlock extends StatelessWidget {
  final CatCardPrice price;
  const _PriceBlock({required this.price});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(price.label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.neonText, fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, runSpacing: 2, children: [
          Text.rich(TextSpan(children: [
            TextSpan(
              text: price.value,
              style: MgType.tab(MgType.h1.copyWith(
                  color: MgColors.neon, height: 1, shadows: [Shadow(color: MgColors.neonA(0.25), blurRadius: 18)])),
            ),
            if (price.unit != null)
              TextSpan(text: ' ${price.unit}', style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
          ])),
          if (price.struck != null)
            Text(price.struck!,
                style: MgType.tab(MgType.small.copyWith(
                    color: MgColors.white(0.66), decoration: TextDecoration.lineThrough, decorationColor: MgColors.white(0.66)))),
        ]),
        const SizedBox(height: 4),
        Text(price.sub, style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.onDarkLead))),
      ]);
}
