import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';

/// Section label of the light Profil page (V22 §7.7 #2): dark eyebrow pill
/// with the 16 px gutter (the board rendered MŮJ ÚČET flush at x = 0).
class PfSectionLabel extends StatelessWidget {
  final String text;
  final String? icon;
  final EdgeInsetsGeometry padding;
  const PfSectionLabel(this.text,
      {super.key, this.icon, this.padding = const EdgeInsets.fromLTRB(MgSpace.gutter, 28, MgSpace.gutter, 12)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(header: true, child: MgEyebrowDark(text, icon: icon)),
        ),
      );
}

/// White grouped list r16 (rows ≥ 56, 1 px dividers inset 16).
class PfGroup extends StatelessWidget {
  final List<Widget> rows;
  final EdgeInsetsGeometry margin;
  const PfGroup({super.key, required this.rows, this.margin = const EdgeInsets.symmetric(horizontal: MgSpace.gutter)});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Padding(
          padding: EdgeInsetsDirectional.only(start: 16),
          child: Divider(height: 1, thickness: 1, color: MgColors.line),
        ));
      }
      children.add(rows[i]);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MgRadius.card),
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

enum PfRowTone { normal, sos, danger }

enum PfTrail { chevron, external, none }

/// One row of a grouped list: icon tile 36, title 15/700 (≤ 2 lines, wraps),
/// optional value under the title (12.5/600, warn = amber), trailing
/// chevron / external icon. SOS = red system (never rank), danger = `#B42318`.
class PfRow extends StatelessWidget {
  final String icon;
  final String title;
  final String? value;
  final String? valueIcon;
  final bool valueWarn;
  final VoidCallback? onTap;
  final PfRowTone tone;
  final PfTrail trail;
  final Widget? trailing;

  const PfRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.valueIcon,
    this.valueWarn = false,
    this.tone = PfRowTone.normal,
    this.trail = PfTrail.chevron,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final Widget lead = switch (tone) {
      PfRowTone.sos => _tile(MgColors.sos, MgColors.sos, MgColors.onDark),
      PfRowTone.danger => _tile(MgColors.errBg, MgColors.errBorder, MgColors.err),
      PfRowTone.normal => MgIconTileLight(icon),
    };
    final titleColor = tone == PfRowTone.normal ? MgColors.ink : MgColors.err;
    final valueColor = valueWarn ? MgColors.warn : MgColors.lead;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: MgType.title.copyWith(
                      fontWeight: tone == PfRowTone.normal ? FontWeight.w700 : FontWeight.w800, color: titleColor)),
              if (value != null && value!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  if (valueIcon != null) ...[
                    MgIcon(valueIcon!, size: 16, color: valueColor),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(value!,
                        style: MgType.small.copyWith(
                            color: valueColor, fontWeight: valueWarn ? FontWeight.w700 : FontWeight.w600)),
                  ),
                ]),
              ],
            ]),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 136), child: trailing!),
          ],
          if (trail != PfTrail.none) ...[
            const SizedBox(width: 8),
            MgIcon(trail == PfTrail.external ? MgIcons.external : MgIcons.chevronRight,
                size: 20, color: MgColors.meta),
          ],
        ]),
      ),
    );
    final tappable = Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: row),
    );
    return MgFabAvoid(kind: tone == PfRowTone.sos ? MgAvoidKind.sos : MgAvoidKind.tap, child: tappable);
  }

  Widget _tile(Color bg, Color border, Color fg) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Center(child: MgIcon(icon, size: 20, color: fg)),
      );
}

/// Plural helper for the v2 profile strings: keys `<base>One/Few/Many`
/// (Few only differs in cs / pl / uk).
String pfPlural(AppTranslations tr, String base, int n) {
  final a = n.abs();
  final lang = tr.lang;
  String suffix;
  if (lang == 'cs') {
    suffix = a == 1 ? 'One' : (a >= 2 && a <= 4 ? 'Few' : 'Many');
  } else if (lang == 'pl' || lang == 'uk') {
    final m10 = a % 10, m100 = a % 100;
    if (a == 1 || (lang == 'uk' && m10 == 1 && m100 != 11)) {
      suffix = 'One';
    } else {
      suffix = (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'Few' : 'Many';
    }
  } else {
    suffix = a == 1 ? 'One' : 'Many';
  }
  return tr.trArgs('$base$suffix', {'n': n});
}

/// "d. m. yyyy" from an ISO date string of the profile (null / invalid → null).
String? pfDate(dynamic iso) {
  if (iso == null) return null;
  final d = DateTime.tryParse('$iso'.trim());
  if (d == null) return null;
  return '${d.day}. ${d.month}. ${d.year}';
}

/// AnimatedSize that is skipped under reduced motion (a zero-duration
/// AnimatedSize re-dirties itself during layout when its child changes).
class PfAnimatedSize extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const PfAnimatedSize({super.key, required this.child, this.duration = const Duration(milliseconds: 300)});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return AnimatedSize(duration: duration, alignment: Alignment.topCenter, child: child);
  }
}
