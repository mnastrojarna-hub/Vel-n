import 'package:flutter/material.dart';

import '../theme.dart';

/// Rozklikávací karta (výchozí stav ZABALENÁ): hlavička s ikonou, nadpisem
/// a šipkou, po klepnutí se rozbalí obsah. Vzhled karty ([decoration],
/// [padding]) dodá volající, aby seděl k sousedním kartám obrazovky
/// (detail rezervace, detail pobočky).
class CollapsibleSection extends StatefulWidget {
  final String emoji;
  final String title;
  final List<Widget> children;
  final BoxDecoration decoration;
  final EdgeInsets padding;
  final TextStyle titleStyle;
  final bool initiallyExpanded;

  const CollapsibleSection({
    super.key,
    required this.emoji,
    required this.title,
    required this.children,
    required this.decoration,
    this.padding = const EdgeInsets.all(14),
    this.titleStyle = const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black),
    this.initiallyExpanded = false,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.decoration,
      clipBehavior: Clip.antiAlias,
      // průhledný Material nad pozadím karty → odezva klepnutí je vidět
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: widget.padding,
              child: Row(children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(child: Text(widget.title, style: widget.titleStyle)),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more, color: MotoGoColors.g400),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: widget.padding.copyWith(top: 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}
