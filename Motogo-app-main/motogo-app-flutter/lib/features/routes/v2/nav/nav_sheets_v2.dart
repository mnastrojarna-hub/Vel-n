import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../rt_sheet_v2.dart';

/// One row of the stops sheet (the old `NavStopView` + branch row).
class NavStopRowV2 {
  final int? number; // null = the MotoGo24 branch row ("M")
  final String label;
  final String? sub;
  final bool reached;
  final bool isNext;
  final VoidCallback? onNavigate;
  const NavStopRowV2({this.number, required this.label, this.sub, this.reached = false, this.isNext = false, this.onNavigate});
}

/// "Body na trase" (board TrasaDetail): light sheet, the skip hint, rows —
/// reached = ✓ tint disc + muted name, next = ink number disc + "Příští"
/// chip, future = outlined number; "Navigovat" ink 40 on every row (the old
/// pop + navigate), branch row with the "M" disc.
class NavStopsSheetV2 extends StatelessWidget {
  final List<NavStopRowV2> rows;
  const NavStopsSheetV2({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return RtSheetV2(
      title: tr.tr('navStopsTitle'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('navStopsSkipHint'), style: MgType.small.copyWith(color: MgColors.meta)),
        const SizedBox(height: 8),
        for (final r in rows) _Row(r),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final NavStopRowV2 r;
  const _Row(this.r);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final Widget disc;
    if (r.number == null) {
      disc = _disc(MgColors.panel, null, const Text('M', style: TextStyle(fontWeight: FontWeight.w900, color: MgColors.neon)));
    } else if (r.reached) {
      disc = _disc(MgColors.tintOk, MgColors.tintOkBorder, const MgIcon(MgIcons.check, size: 18, color: MgColors.link));
    } else {
      disc = _disc(r.isNext ? MgColors.ink : MgColors.surface, r.isNext ? MgColors.neon : MgColors.lineInput,
          Text('${r.number}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: r.isNext ? MgColors.neon : MgColors.ink))));
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        disc,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(r.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MgType.title.copyWith(color: r.reached ? MgColors.meta : MgColors.ink)),
            if (r.isNext)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: MgColors.tintOk, borderRadius: BorderRadius.circular(999)),
                child: MgWordFit(minScale: 0.7, child: Text(tr.tr('routeNavNext'), style: MgType.meta.copyWith(color: MgColors.onTintOk))),
              ),
            if (r.sub != null) Text(r.sub!, style: MgType.meta.copyWith(color: MgColors.meta)),
          ]),
        ),
        const SizedBox(width: 8),
        MgBtnInk(label: tr.tr('navNavigateHere'), height: 40, expand: false, onTap: r.onNavigate),
      ]),
    );
  }

  Widget _disc(Color bg, Color? ring, Widget child) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: ring == null ? null : Border.all(color: ring, width: 1.5)),
        alignment: Alignment.center,
        child: child,
      );
}

/// "Ukončit trasu?" (T6): safe "Zrušit" left, red "Ukončit" right; pops
/// false / true exactly like the old AlertDialog.
Widget navEndDialogV2(BuildContext dc) {
  final tr = t(dc);
  return MgDialogFrame(
    title: tr.tr('routeEndConfirmTitle'),
    body: tr.tr('routeEndConfirm'),
    safe: MgBtnGhostLight(label: tr.cancel, onTap: () => Navigator.pop(dc, false)),
    action: MgBtnDestructive(label: tr.tr('routeEndBtn'), filled: true, onTap: () => Navigator.pop(dc, true)),
    safeLabel: tr.cancel,
    actionLabel: tr.tr('routeEndBtn'),
  );
}

/// "Uložit trasu" (T6 with the name field): same controller, same pops.
Widget navSaveDialogV2(BuildContext dc, TextEditingController name) {
  final tr = t(dc);
  return MgDialogFrame(
    title: tr.tr('routeSaveTitle'),
    content: TextField(
      controller: name,
      autofocus: true,
      style: MgType.body.copyWith(color: MgColors.ink),
      decoration: mgInputDecoration(dc, label: tr.tr('routeSaveName')),
    ),
    safe: MgBtnGhostLight(label: tr.cancel, onTap: () => Navigator.pop(dc, false)),
    action: MgBtnInk(label: tr.tr('routeSaveBtn'), onTap: () => Navigator.pop(dc, true)),
    safeLabel: tr.cancel,
    actionLabel: tr.tr('routeSaveBtn'),
  );
}

/// Location / GPS / offline note on the map (Stavy 16.22–16.24) as a T3
/// banner: the old sentence split into title (before " – " / ": ") and
/// text, tone by severity, the old action (allow / open settings).
class NavStatusBannerV2 extends StatelessWidget {
  final String sentence;
  final MgTone tone;
  final String icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  const NavStatusBannerV2({
    super.key,
    required this.sentence,
    required this.tone,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final m = RegExp(r' – |: ').firstMatch(sentence);
    final title = m == null ? sentence : sentence.substring(0, m.start);
    var text = m == null ? null : sentence.substring(m.end).trim();
    if (text != null && text.isNotEmpty) text = text[0].toUpperCase() + text.substring(1);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: MgShadows.card),
        child: MgStateBanner(
          tone: tone,
          plain: true,
          icon: icon,
          title: title,
          text: text,
          actions: [
            if (actionLabel != null && onAction != null)
              MgBtnInk(label: actionLabel!, onTap: onAction, height: 40, expand: false),
          ],
        ),
      ),
    );
  }
}
