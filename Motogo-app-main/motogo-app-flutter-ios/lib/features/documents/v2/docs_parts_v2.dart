import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../profile/v2/profile_fit.dart';
import '../../profile/v2/profile_v2_parts.dart' show PfAnimatedSize;

/// How a [DocCardV2] is laid out: [column] = illustration on top (two cards
/// side by side, or one per row when a word would not fit the half), [row]
/// = compact illustration left of the texts (one card per row).
enum DocCardLayout { column, row }

/// Document card in the dark docs hero (board `.dcard`): illustration,
/// title, Ověřeno / Neověřeno chip and the action (Smazat / Skenovat) —
/// the same callbacks as today's status rows.
class DocCardV2 extends StatelessWidget {
  final String icon;
  final String title;
  final bool verified;
  final VoidCallback onReset;
  final VoidCallback? onScan;
  final DocCardLayout layout;
  const DocCardV2({
    super.key,
    required this.icon,
    required this.title,
    required this.verified,
    required this.onReset,
    this.onScan,
    this.layout = DocCardLayout.column,
  });

  static const _minScale = 0.85;
  static final _titleStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark);
  static final _chipStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800);
  static final _actionStyle = MgType.small.copyWith(fontWeight: FontWeight.w800);

  bool get _hasAction => verified || onScan != null;

  /// true when title, chip and action keep whole words in a card [width]
  /// wide (verify:render — "Zweryfiko|wano", "Führersch|ein" at 320 dp).
  bool fits(BuildContext context, double width) {
    final tr = t(context);
    // 12 padding + 1 border each side; row: 72 illustration + 12 gap.
    final w = width - 26 - (layout == DocCardLayout.row ? 84 : 0);
    bool ok(String text, TextStyle style, double room) => pfWordsFit(context, text, style, room, minScale: _minScale);
    return ok(title, _titleStyle, w) &&
        ok(verified ? tr.tr('verified') : tr.tr('notVerified'), _chipStyle, w - 34) &&
        (!_hasAction || ok(verified ? tr.tr('deleteDoc') : tr.tr('scan'), _actionStyle, w - 20));
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final texts = <Widget>[
      MgWordFit(minScale: _minScale, child: Text(title, style: _titleStyle)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: verified ? MgColors.neonA(0.18) : MgColors.warnDark.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIcon(verified ? MgIcons.check : MgIcons.warn,
              size: 14, color: verified ? MgColors.neonText : MgColors.warnDark),
          const SizedBox(width: 4),
          Flexible(
            child: MgWordFit(
              minScale: _minScale,
              child: Text(verified ? tr.tr('verified') : tr.tr('notVerified'),
                  style: _chipStyle.copyWith(color: verified ? MgColors.neonText : MgColors.warnDark)),
            ),
          ),
        ]),
      ),
      if (_hasAction)
        Semantics(
          button: true,
          child: MgPress(
            onTap: verified ? onReset : onScan,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MgIcon(verified ? MgIcons.trash : MgIcons.camera,
                    size: 16, color: verified ? MgColors.errDark : MgColors.neonText),
                const SizedBox(width: 4),
                Flexible(
                  child: MgWordFit(
                    minScale: _minScale,
                    child: Text(verified ? tr.tr('deleteDoc') : tr.tr('scan'),
                        style: _actionStyle.copyWith(color: verified ? MgColors.errDark : MgColors.neonText)),
                  ),
                ),
              ]),
            ),
          ),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: verified ? MgColors.neonA(0.35) : MgColors.warnDark.withValues(alpha: 0.45)),
      ),
      child: layout == DocCardLayout.row
          ? Row(children: [
              SizedBox(width: 72, child: _Illustration(icon: icon, ok: verified, compact: true)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: texts)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Illustration(icon: icon, ok: verified),
              const SizedBox(height: 8),
              ...texts,
            ]),
    );
  }
}

class _Illustration extends StatelessWidget {
  final String icon;
  final bool ok;
  final bool compact;
  const _Illustration({required this.icon, required this.ok, this.compact = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [MgColors.glow, Color(0xFF13301F)]),
        ),
        child: compact
            ? Center(child: MgIcon(icon, size: 28, color: ok ? MgColors.neon : MgColors.warnDark))
            : Stack(children: [
                Positioned(left: 12, top: 12, child: MgIcon(icon, size: 28, color: ok ? MgColors.neon : MgColors.warnDark)),
                for (final (l, t, r) in const [(48.0, 16.0, 12.0), (48.0, 30.0, 34.0), (12.0, 48.0, 48.0)])
                  Positioned(
                    left: l,
                    top: t,
                    right: r,
                    child: Container(
                        height: 6,
                        decoration: BoxDecoration(color: MgColors.white(0.18), borderRadius: BorderRadius.circular(2))),
                  ),
              ]),
      );
}

/// Skeleton pair of doc cards while the status loads.
class DocCardsSkeletonV2 extends StatelessWidget {
  const DocCardsSkeletonV2({super.key});

  @override
  Widget build(BuildContext context) => const Row(children: [
        Expanded(child: MgSkeleton(height: 150, radius: 14, dark: true)),
        SizedBox(width: 10),
        Expanded(child: MgSkeleton(height: 150, radius: 14, dark: true)),
      ]);
}

/// "Tipy pro focení" — the scan tips behind ⓘ (expands in place).
class DocTipsV2 extends StatefulWidget {
  const DocTipsV2({super.key});

  @override
  State<DocTipsV2> createState() => _DocTipsV2State();
}

class _DocTipsV2State extends State<DocTipsV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: _open,
        child: MgPress(
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              const MgIcon(MgIcons.info, size: 18, color: MgColors.neonText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr.tr('v2DocTips'),
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: MgMotion.of(context, MgMotion.pop),
                child: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.neonText),
              ),
            ]),
          ),
        ),
      ),
      PfAnimatedSize(
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr.tr('scanTips'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
