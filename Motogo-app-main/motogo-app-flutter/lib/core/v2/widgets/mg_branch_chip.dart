import 'package:flutter/material.dart';

import '../../../features/catalog/moto_model.dart';
import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';

/// Branch name without the brand ("MotoGo24 Mezná" → "Mezná", "MotoGo 24 –
/// Velké Němčice" → "Velké Němčice"); the city when the name is only the
/// brand or missing; null when neither is known.
String? mgBranchShortName(String? name, String? city) {
  final brand = RegExp(r'^\s*moto\s*go\s*(24)?\s*[-–—·,:|/]?\s*', caseSensitive: false);
  final short = (name ?? '').replaceFirst(brand, '').trim();
  if (short.isNotEmpty) return short;
  final c = (city ?? '').trim();
  return c.isEmpty ? null : c;
}

/// "Mezná · s obsluhou" / "Velké Němčice · samoobsluha": the short branch
/// name ([mgBranchShortName]) plus the branch mode when [type] is known
/// (`branches.type`: 'samoobslužná' = [self], anything else = [staffed],
/// as `catBranchType`). Null without a branch.
String? mgBranchChipLabel({
  required String? name,
  required String? city,
  required String? type,
  required String self,
  required String staffed,
}) {
  final short = mgBranchShortName(name, city);
  if (short == null) return null;
  final t = (type ?? '').trim();
  if (t.isEmpty) return short;
  return '$short · ${t == 'samoobslužná' ? self : staffed}';
}

/// [mgBranchChipLabel] of a bike in the app language (existing short mode
/// words `v2UxRpTypeSelf` / `v2UxRpTypeStaffed`); pass [mgBranchShortName]
/// of the same bike as the chip's `shortLabel`.
String? mgBikeBranchChipLabel(AppTranslations tr, Motorcycle m) => mgBranchChipLabel(
      name: m.branchName,
      city: m.branchCity,
      type: m.branchType,
      self: tr.tr('v2UxRpTypeSelf'),
      staffed: tr.tr('v2UxRpTypeStaffed'),
    );

/// Widest a branch chip may grow on a photo [photoWidth] wide: the photo
/// minus the insets (12 left, 12 gap, 12 right) and the widest top-left
/// pill [leftPill] (the "1 / 4" pill ≈ 46 px; pass more where a wider pill
/// sits there), 120…280 px — "Velké Němčice · samoobsluha" fits at 320.
double mgBranchChipMaxWidth(double photoWidth, {double leftPill = 46}) =>
    (photoWidth - 36 - leftPill).clamp(120.0, 280.0);

/// Where a bike is (owner v5.0.1: "v horním pravém rohu fotky … důrazně
/// výrazný, třeba zelený"): a brand-neon pill with a place pin and dark
/// text, one line, never wider than [maxWidth]: when [label] does not fit,
/// [shortLabel] (the name without the mode) is shown, and only a name that
/// does not fit either is cut with an ellipsis; a dark drop
/// shadow keeps it readable on a bright photo, a soft neon glow on a dark
/// one. Put it in the photo's top-right corner (below the status bar).
class MgBranchChip extends StatelessWidget {
  final String label;
  final String? shortLabel;
  final double maxWidth;
  const MgBranchChip({super.key, required this.label, this.shortLabel, this.maxWidth = 220});

  static const TextStyle _style = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.2);

  /// Room for the text: [maxWidth] − padding 18 − pin 15 − gap 4 − border 2.
  static double textRoom(double maxWidth) => maxWidth - 39;

  /// [label] when it fits in one line at the chip's style, else [shortLabel].
  String fitted(BuildContext context) {
    final short = shortLabel;
    if (short == null || short == label) return label;
    final tp = TextPainter(
      text: TextSpan(text: label, style: DefaultTextStyle.of(context).style.merge(MgType.small).merge(_style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w <= textRoom(maxWidth) ? label : short;
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          key: const ValueKey('mg-branch-chip'),
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          decoration: BoxDecoration(
            gradient: MgGradients.neon,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.55)),
            boxShadow: [
              ...MgShadows.photoControl,
              BoxShadow(color: MgColors.neonA(0.35), blurRadius: 12),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.pin, size: 15, color: MgColors.onNeon, stroke: 2.4),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                fitted(context),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: MgType.small.merge(_style).copyWith(color: MgColors.onNeon),
              ),
            ),
          ]),
        ),
      );
}
