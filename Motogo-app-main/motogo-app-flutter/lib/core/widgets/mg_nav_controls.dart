import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../i18n/i18n_provider.dart';
import '../theme.dart';

/// Ovladač „zpět" / „zavřít" (požadavek majitele 2026-10-16: tlačítko zpět
/// musí být vždy dobře viditelné a dobře trefitelné).
///
/// Obalí stávající vzhled šipky / křížku (nic na něm nemění) a přidá:
/// * dotykovou plochu aspoň [minSize] × [minSize] (výchozí 48 — Material /
///   Apple doporučení) BEZ změny rozvržení — plocha přesahuje kreslený prvek,
///   pokud kolem něj je volné místo (viz [MgHitSlop]);
/// * popisek pro TalkBack / VoiceOver („Zpět" / „Zavřít") s akcí klepnutí.
class MgBackTap extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  /// true = křížek „Zavřít", jinak šipka „Zpět".
  final bool close;

  /// Vlastní popisek pro čtečku (např. „Ukončit jízdu").
  final String? label;
  final double minSize;

  const MgBackTap({
    super.key,
    required this.onTap,
    required this.child,
    this.close = false,
    this.label,
    this.minSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label ?? (close ? tr.tr('close') : tr.back),
      onTap: onTap,
      excludeSemantics: true,
      child: MgHitSlop(
        minSize: minSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

/// Zvětší dotykovou plochu potomka na aspoň [minSize] × [minSize] (vystředěně),
/// aniž by změnil jeho velikost v rozvržení. Klepnutí kousek vedle malé šipky
/// se tak počítá jako klepnutí na ni (rodič ho ale musí pustit dál — plocha
/// nepřesáhne hranice rodiče a nepřebije sourozence, který bod sám zachytí).
class MgHitSlop extends SingleChildRenderObjectWidget {
  final double minSize;
  const MgHitSlop({super.key, this.minSize = 48, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlop(minSize);

  @override
  void updateRenderObject(BuildContext context, _RenderHitSlop renderObject) {
    renderObject.minSize = minSize;
  }
}

class _RenderHitSlop extends RenderProxyBox {
  _RenderHitSlop(this.minSize);
  double minSize;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final s = size;
    final dx = math.max(0.0, (minSize - s.width) / 2);
    final dy = math.max(0.0, (minSize - s.height) / 2);
    if (position.dx < -dx ||
        position.dy < -dy ||
        position.dx >= s.width + dx ||
        position.dy >= s.height + dy) {
      return false;
    }
    final c = child;
    if (c == null || s.isEmpty) return false;
    // Bod v přesahu → nejbližší bod uvnitř potomka (ten testuje vlastní hranice).
    final inside = Offset(
      position.dx.clamp(0.0, s.width - 0.01),
      position.dy.clamp(0.0, s.height - 0.01),
    );
    if (c.hitTest(result, position: inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Viditelný křížek „Zavřít" pro bottom sheety a celoobrazovkové prohlížeče.
/// Na iPhonu není systémové tlačítko zpět a stažení sheetu dolů nikdo nemusí
/// znát — křížek je vždy vidět. Bez [onTap] zavře nejbližší trasu přes
/// `maybePop` (respektuje PopScope — např. probíhající platbu).
class MgSheetClose extends StatelessWidget {
  final VoidCallback? onTap;

  /// Tmavé pozadí sheetu → světlý křížek.
  final bool dark;
  final double size;
  const MgSheetClose({super.key, this.onTap, this.dark = false, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return MgBackTap(
      close: true,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.16) : MotoGoColors.g200,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close,
            size: size * 0.56, color: dark ? Colors.white : MotoGoColors.black),
      ),
    );
  }
}

/// Sheet s křížkem vpravo nahoře — obal obsahu sheetu, který vlastní hlavičku
/// s místem na křížek nemá. Křížek leží NAD obsahem (nic neposouvá).
class MgSheetWithClose extends StatelessWidget {
  final Widget child;
  final bool dark;
  final VoidCallback? onClose;
  final double top;
  final double right;
  const MgSheetWithClose({
    super.key,
    required this.child,
    this.dark = false,
    this.onClose,
    this.top = 8,
    this.right = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      // passthrough = obsah sheetu dostane stejné rozměry jako bez křížku.
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          top: top,
          right: right,
          child: MgSheetClose(onTap: onClose, dark: dark),
        ),
      ],
    );
  }
}

/// Úchyt sheetu (šedá čárka) s křížkem „Zavřít" vpravo — náhrada samotného
/// úchytu `Container(width: 40, height: 4)` v horní části sheetu.
class MgSheetHandle extends StatelessWidget {
  final Color? barColor;
  final bool dark;
  final bool showBar;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry margin;
  const MgSheetHandle({
    super.key,
    this.barColor,
    this.dark = false,
    this.showBar = true,
    this.onClose,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showBar)
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: barColor ?? MotoGoColors.g200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: MgSheetClose(onTap: onClose, dark: dark),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titulek sheetu s křížkem „Zavřít" vpravo. [center] = titulek uprostřed
/// (vlevo stejně široká mezera), jinak zarovnaný vlevo.
class MgSheetTitleRow extends StatelessWidget {
  final Widget title;
  final bool center;
  final bool dark;
  final VoidCallback? onClose;
  const MgSheetTitleRow({
    super.key,
    required this.title,
    this.center = true,
    this.dark = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (center) const SizedBox(width: 40),
        Expanded(child: center ? Center(child: title) : title),
        const SizedBox(width: 8),
        MgSheetClose(onTap: onClose, dark: dark),
      ],
    );
  }
}
