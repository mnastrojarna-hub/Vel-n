import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import 'rt_v2_text.dart';

/// Lead line on canvas under the hub header (the old header subtitle).
class TrasyLeadV2 extends StatelessWidget {
  final String text;
  const TrasyLeadV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Text(text, style: MgType.small.copyWith(color: MgColors.lead, fontWeight: FontWeight.w700)),
      );
}

/// "Zapni polohu…" — white card with the SAME action as the old prompt.
class PlacesLocationPromptV2 extends StatelessWidget {
  final VoidCallback onTap;
  const PlacesLocationPromptV2({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: Row(children: [
          const MgIconTileLight(MgIcons.near),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr.tr('poiLocationPrompt'), style: MgType.small.copyWith(color: MgColors.ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          MgBtnInk(label: tr.tr('poiLocationEnable'), onTap: onTap, height: 44, expand: false),
        ]),
      ),
    );
  }
}

/// Map preview card: the screen's EXISTING map widget (same gestures) in a
/// white rounded frame, a light expand disc and the gesture hint.
class PlacesMapCardV2 extends StatelessWidget {
  final Widget map;
  final VoidCallback onExpand;
  final String hint;
  const PlacesMapCardV2({super.key, required this.map, required this.onExpand, required this.hint});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 172,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Positioned.fill(child: map),
              Positioned(
                right: 4,
                top: 4,
                child: MgIconButton(
                  icon: MgIcons.full,
                  onTap: onExpand,
                  style: MgIconButtonStyle.light,
                  semanticLabel: tr.tr('placesMapTitle'),
                ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(children: [
            const MgIcon(MgIcons.finger, size: 16, color: MgColors.lead),
            const SizedBox(width: 6),
            Expanded(child: Text(hint, style: MgType.meta.copyWith(color: MgColors.meta))),
          ]),
        ),
      ]),
    );
  }
}

/// One category chip of the visible category row.
class PlacesCatV2 {
  final String key;
  final String label;
  final int count;
  final bool selected;
  final Widget icon;
  const PlacesCatV2({required this.key, required this.label, required this.count, required this.selected, required this.icon});
}

/// Toolbar chip of the white filter band (white + line; on = tint ✓).
class TrasyToolChipV2 extends StatelessWidget {
  final String label;
  final String? icon;
  final Widget? iconWidget;
  final bool on;
  final int? count;
  final bool caret;
  final bool danger;
  final VoidCallback onTap;

  const TrasyToolChipV2({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.on = false,
    this.count,
    this.caret = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? MgColors.err : (on ? MgColors.onTintOk : MgColors.ink);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: on,
        label: count == null ? label : '$label, $count',
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: danger ? MgColors.errBg : (on ? MgColors.tintOk : MgColors.surface),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: danger ? MgColors.errBorder : (on ? MgColors.tintOkBorder : MgColors.line),
                width: on ? 1.5 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (iconWidget != null) ...[iconWidget!, const SizedBox(width: 7)],
              if (icon != null) ...[MgIcon(icon!, size: 16, color: danger ? MgColors.err : MgColors.link), const SizedBox(width: 7)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
              ),
              if (count != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: MgColors.well,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MgColors.line),
                  ),
                  child: Text(rtThousands(count!), style: MgType.tab(MgType.meta.copyWith(color: MgColors.ink))),
                ),
              ],
              if (caret) ...[const SizedBox(width: 4), MgIcon(MgIcons.chevronDown, size: 16, color: fg)],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Horizontal chip rail with the 16 px gutter.
class TrasyChipRailV2 extends StatelessWidget {
  final List<Widget> children;
  const TrasyChipRailV2({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: children),
      );
}

/// "Našli jsme i trasy · n" — the same jump to the routes list.
class PlacesRoutesBannerV2 extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const PlacesRoutesBannerV2({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = '${t(context).tr('searchAlsoRoutes')} · ${rtThousands(count)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MgColors.tintFeatureA, MgColors.tintFeatureB],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.tintOkBorder),
            ),
            child: Row(children: [
              const MgIconTileDark(MgIcons.route, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: MgType.title.copyWith(color: MgColors.ink))),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.link),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "12 míst · Od mé polohy" above the list.
class TrasyListHeaderV2 extends StatelessWidget {
  final String count;
  final String? sort;
  const TrasyListHeaderV2({super.key, required this.count, this.sort});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: count, style: MgType.tab(MgType.section.copyWith(color: MgColors.ink))),
            if (sort != null)
              TextSpan(text: '  ·  $sort', style: MgType.meta.copyWith(color: MgColors.meta)),
          ]),
        ),
      );
}

/// Empty / nothing-matches state of a list (light), optional action.
class TrasyEmptyV2 extends StatelessWidget {
  final String icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionInk;

  const TrasyEmptyV2({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.actionInk = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MgPop(playOnMount: true, child: MgIconTileDark(icon, size: 56)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.lead)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            actionInk
                ? MgBtnInk(label: actionLabel!, onTap: onAction, expand: false)
                : MgBtnGhostLight(label: actionLabel!, onTap: onAction, icon: MgIcons.close, expand: false),
          ],
        ]),
      );
}

/// Loading of the place list (skeleton cards, shimmer once per frame
/// budget; static under reduced motion via MgSkeleton).
class PlacesLoadingV2 extends StatelessWidget {
  const PlacesLoadingV2({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: t(context).tr('placesMapLoading'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MgColors.line),
                ),
                child: const Row(children: [
                  MgSkeleton(width: 84, height: 84, radius: 12),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MgSkeleton(width: 170, height: 16),
                      SizedBox(height: 10),
                      MgSkeleton(width: 110, height: 12),
                      SizedBox(height: 8),
                      MgSkeleton(width: 80, height: 12),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      );
}
