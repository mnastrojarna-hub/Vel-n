import 'package:flutter/material.dart';
import '../theme.dart';

/// QWERTY klávesnice + vedle numerická — plně responzivní.
/// Řady se rozprostřou přes dostupnou výšku (Expanded), klávesy se škálují,
/// takže layout NIKDY nepřeteče bez ohledu na velikost/poměr tabletu.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _qwerty()),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: _numeric()),
      ],
    );
  }

  Widget _qwerty() {
    return Column(
      children: [
        for (final row in _rows)
          _KeyRow(children: [
            for (final ch in row.split(''))
              _Key(label: ch.toUpperCase(), enabled: enabled, onTap: () => onChar(ch)),
          ]),
        _KeyRow(children: [
          _Key(label: 'SMAZAT', flex: 3, color: MG.amber, enabled: enabled, onTap: onClear),
          _Key(icon: Icons.backspace_outlined, flex: 2, enabled: enabled, onTap: onBackspace),
        ]),
      ],
    );
  }

  Widget _numeric() {
    Widget keys(List<Widget> ks) => _KeyRow(children: ks);
    return Column(
      children: [
        keys([for (final n in ['1', '2', '3']) _Key(label: n, enabled: enabled, onTap: () => onChar(n))]),
        keys([for (final n in ['4', '5', '6']) _Key(label: n, enabled: enabled, onTap: () => onChar(n))]),
        keys([for (final n in ['7', '8', '9']) _Key(label: n, enabled: enabled, onTap: () => onChar(n))]),
        keys([
          _Key(icon: Icons.backspace_outlined, enabled: enabled, onTap: onBackspace),
          _Key(label: '0', enabled: enabled, onTap: () => onChar('0')),
          _Key(icon: Icons.check_rounded, color: MG.green, fg: MG.black, enabled: enabled, onTap: onEnter),
        ]),
      ],
    );
  }
}

/// Jedna řada — vyplní rovnoměrný díl výšky (Expanded) a roztáhne klávesy.
class _KeyRow extends StatelessWidget {
  final List<Widget> children;
  const _KeyRow({required this.children});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Key extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool enabled;
  final Color? color;
  final Color? fg;

  const _Key({
    this.label,
    this.icon,
    required this.onTap,
    this.flex = 1,
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
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MG.white.withValues(alpha: 0.10)),
              ),
              // FittedBox = obsah se vždy zmenší tak, aby se vešel (žádný overflow).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: icon != null
                    ? Icon(icon, color: foreground, size: 30)
                    : Text(
                        label ?? '',
                        style: TextStyle(
                          color: foreground,
                          fontSize: (label != null && label!.length > 2) ? 22 : 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
