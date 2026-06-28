import 'package:flutter/material.dart';
import '../theme.dart';

/// QWERTY klávesnice + vedle numerická — jak požaduje zadání.
/// Emituje znaky / mazání / potvrzení nahoru.
class KioskKeyboards extends StatelessWidget {
  final void Function(String ch) onChar;
  final VoidCallback onBackspace;
  final VoidCallback onEnter;
  final VoidCallback onClear;
  final bool enabled;

  const KioskKeyboards({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onEnter,
    required this.onClear,
    this.enabled = true,
  });

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── QWERTY ──
        Expanded(flex: 5, child: _qwerty()),
        const SizedBox(width: 16),
        // ── Numerická ──
        Expanded(flex: 2, child: _numeric()),
      ],
    );
  }

  Widget _qwerty() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ch in row.split(''))
                  _Key(label: ch.toUpperCase(), enabled: enabled, onTap: () => onChar(ch)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(label: 'SMAZAT', flex: 3, color: MG.amber, enabled: enabled, onTap: onClear),
              _Key(icon: Icons.backspace_outlined, flex: 2, enabled: enabled, onTap: onBackspace),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numeric() {
    Widget numRow(List<String> ns) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final n in ns) _Key(label: n, big: true, enabled: enabled, onTap: () => onChar(n))],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        numRow(['1', '2', '3']),
        numRow(['4', '5', '6']),
        numRow(['7', '8', '9']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(icon: Icons.backspace_outlined, big: true, enabled: enabled, onTap: onBackspace),
              _Key(label: '0', big: true, enabled: enabled, onTap: () => onChar('0')),
              _Key(
                icon: Icons.check_rounded,
                big: true,
                color: MG.green,
                fg: MG.black,
                enabled: enabled,
                onTap: onEnter,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool big;
  final bool enabled;
  final Color? color;
  final Color? fg;

  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
    this.big = false,
    this.enabled = true,
    this.color,
    this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? MG.white.withValues(alpha: 0.08);
    final foreground = fg ?? MG.white;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: enabled ? bg : bg.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Container(
              height: big ? 78 : 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MG.white.withValues(alpha: 0.10)),
              ),
              child: icon != null
                  ? Icon(icon, color: foreground, size: big ? 30 : 24)
                  : Text(
                      label ?? '',
                      style: TextStyle(
                        color: foreground,
                        fontSize: big ? 30 : (label!.length > 2 ? 18 : 24),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
