import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Filter values of the list — the SAME values and order as the old screen
/// (`resFilterProvider`: all / aktivni / nadchazejici / dokoncene /
/// cancelled) and the same i18n words.
const kResFilterKeys = ['all', 'aktivni', 'nadchazejici', 'dokoncene', 'cancelled'];
const kResFilterI18n = ['all', 'active', 'upcoming', 'completed', 'cancelled'];

/// Filter track (V22 `.ls-seg` on a `well` track): one segment per filter
/// with its count; the selected one is ink with white text. Scrolls
/// sideways when the 8-language labels do not fit. Under it the swipe hint
/// with ‹ › (= the same filter step as the horizontal swipe).
class ResFilterTabsV2 extends StatefulWidget {
  final String value;

  /// Count per filter; null while the list is loading (no false "0").
  final Map<String, int>? counts;
  final ValueChanged<String> onSelect;
  final ValueChanged<int> onStep;

  /// Body swipe progress (`MgSwipeSegments.progress`, + toward the next
  /// filter): the dark selection passes from the current tab to its
  /// neighbour with the finger (design G4 b).
  final ValueListenable<double>? dragProgress;

  const ResFilterTabsV2({
    super.key,
    required this.value,
    required this.counts,
    required this.onSelect,
    required this.onStep,
    this.dragProgress,
  });

  @override
  State<ResFilterTabsV2> createState() => _ResFilterTabsV2State();
}

class _ResFilterTabsV2State extends State<ResFilterTabsV2> {
  final _keys = {for (final k in kResFilterKeys) k: GlobalKey()};
  final _scroll = ScrollController();
  final _rowKey = GlobalKey();

  /// Measured tab boxes in the row (for the ONE sliding thumb).
  List<Rect>? _rects;

  void _measure() {
    if (!mounted) return;
    final row = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || !row.hasSize) return;
    final out = <Rect>[];
    for (final k in kResFilterKeys) {
      final b = _keys[k]?.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.hasSize) return;
      out.add(b.localToGlobal(Offset.zero, ancestor: row) & b.size);
    }
    final old = _rects;
    final same = old != null && old.length == out.length && [for (var i = 0; i < out.length; i++) old[i] == out[i]].every((x) => x);
    if (!same) setState(() => _rects = out);
  }

  /// Edge fades: a tab cut by the track edge reads as "more this way", not
  /// as a layout bug (V22 `.ls-seg`).
  bool _fadeStart = false, _fadeEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_edges);
    // The selected filter (e.g. after a swipe on another visit) is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edges() {
    if (!_scroll.hasClients || !mounted) return;
    final p = _scroll.position;
    final s = p.pixels > 1, e = p.pixels < p.maxScrollExtent - 1;
    if (s == _fadeStart && e == _fadeEnd) return;
    setState(() {
      _fadeStart = s;
      _fadeEnd = e;
    });
  }

  void _reveal({bool animate = true}) {
    final c = _keys[widget.value]?.currentContext;
    if (c == null || !mounted) return;
    Scrollable.ensureVisible(c,
        alignment: 0.5,
        duration: animate ? MgMotion.of(context, MgMotion.tab) : Duration.zero,
        curve: MgMotion.out);
    _edges();
  }

  @override
  void didUpdateWidget(ResFilterTabsV2 old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final idx = kResFilterKeys.indexOf(widget.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.line),
        ),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _edges());
            return false;
          },
          child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            colors: [
              _fadeStart ? const Color(0x00000000) : const Color(0xFF000000),
              const Color(0xFF000000),
              const Color(0xFF000000),
              _fadeEnd ? const Color(0x00000000) : const Color(0xFF000000),
            ],
            stops: const [0, 0.08, 0.92, 1],
          ).createShader(r),
          child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: ValueListenableBuilder<double>(
            valueListenable: widget.dragProgress ?? _zero,
            builder: (context, p, _) {
              // JEDEN palec pod záložkami (jako MgSegmented): s prstem jede
              // z aktuální záložky k sousední, po puštění dosedne (300,
              // spring; reduced = hned). Popisek je bílý jen pod palcem.
              final target = (idx + (p > 0 ? 1 : (p < 0 ? -1 : 0))).clamp(0, kResFilterKeys.length - 1);
              final t = target == idx ? 0.0 : p.abs().clamp(0.0, 1.0);
              double fill(int i) => i == idx ? 1 - t : (i == target ? t : 0);
              WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
              final r = _rects;
              final dragging = p != 0;
              final row = Row(key: _rowKey, children: [
                for (var i = 0; i < kResFilterKeys.length; i++)
                  _Tab(
                    key: _keys[kResFilterKeys[i]],
                    label: tr.tr(kResFilterI18n[i]),
                    count: widget.counts?[kResFilterKeys[i]],
                    selected: kResFilterKeys[i] == widget.value,
                    on: i == idx ? t < 0.5 : (i == target && t >= 0.5),
                    // Before the first measure: the old per-tab fill.
                    fill: r == null ? fill(i) : 0,
                    dragging: dragging,
                    onTap: () => widget.onSelect(kResFilterKeys[i]),
                  ),
              ]);
              if (r == null || idx < 0) return row;
              final a = r[idx], b = r[target];
              final at = Rect.lerp(a, b, t)!;
              return Stack(children: [
                AnimatedPositioned(
                  key: const ValueKey('res-filter-thumb'),
                  duration: dragging ? Duration.zero : MgMotion.of(context, MgMotion.thumb),
                  curve: MgMotion.spring,
                  left: at.left,
                  top: at.top,
                  width: at.width,
                  height: at.height,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: MgColors.panel,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                              color: MgColors.panel.withValues(alpha: 0.5),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                              spreadRadius: -6)
                        ],
                      ),
                    ),
                  ),
                ),
                row,
              ]);
            },
          ),
          ),
          ),
        ),
      ),
      SizedBox(
        height: 44,
        child: Row(children: [
          _Step(
            icon: MgIcons.chevronLeft,
            label: tr.tr('v2ResPrevFilter'),
            onTap: idx > 0 ? () => widget.onStep(-1) : null,
          ),
          Expanded(
            child: Text(tr.tr('v2ResSwipeHint'),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: MgType.meta.copyWith(color: MgColors.meta)),
          ),
          _Step(
            icon: MgIcons.chevronRight,
            label: tr.tr('v2ResNextFilter'),
            onTap: idx < kResFilterKeys.length - 1 ? () => widget.onStep(1) : null,
          ),
        ]),
      ),
    ]);
  }
}

final _zero = ValueNotifier<double>(0);

class _Tab extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;

  /// 0..1 share of the dark selection (1 = selected, between = mid-swipe).
  final double fill;

  /// The thumb is under this tab (≥ half) → light label.
  final bool on;
  final bool dragging;
  final VoidCallback onTap;
  const _Tab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.fill,
    required this.on,
    required this.dragging,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Během tahu bez zpoždění (výběr drží prst), jinak plynulý přechod.
    final dur = dragging ? Duration.zero : MgMotion.of(context, MgMotion.tab);
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: dur,
          curve: MgMotion.out,
          constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MgColors.panel.withValues(alpha: fill),
            borderRadius: BorderRadius.circular(10),
            boxShadow: fill > 0
                ? [
                    BoxShadow(
                        color: MgColors.panel.withValues(alpha: 0.5 * fill),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                        spreadRadius: -6)
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Label colour switches (180 ms) only when the thumb is under it
            // — never white on a half-faded panel.
            AnimatedDefaultTextStyle(
              duration: MgMotion.of(context, MgMotion.color),
              style: DefaultTextStyle.of(context).style.merge(
                  MgType.small.copyWith(fontWeight: FontWeight.w800, color: on ? MgColors.onDark : MgColors.meta)),
              child: Text(label),
            ),
            // Počet až s daty — při načítání žádná falešná „0".
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? MgColors.neonA(0.18) : MgColors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count',
                    style: MgType.tab(MgType.micro.copyWith(
                        fontWeight: FontWeight.w800, height: 1, color: on ? MgColors.neon : MgColors.body2))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  const _Step({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: onTap == null ? 0.3 : 1,
              child: MgIcon(icon, size: 22, color: MgColors.link),
            ),
          ),
        ),
      ),
    );
  }
}
