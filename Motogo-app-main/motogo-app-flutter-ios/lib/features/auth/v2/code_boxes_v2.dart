import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Keeps only the digits of a pasted / typed code (max [max]).
String asmDigits(String s, [int max = 8]) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.length > max ? d.substring(0, max) : d;
}

/// 8 code boxes (Prihlaseni "Obnovení hesla 2/3") over ONE text field
/// driven by the screen's own controller: typing, SMS / e-mail autofill
/// (`oneTimeCode`) and paste all land in [controller]; the boxes only show
/// it. Focused box = 2 px `#0D6E0D` + neon ring.
class CodeBoxesV2 extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool error;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String semanticLabel;
  const CodeBoxesV2({
    super.key,
    required this.controller,
    this.length = 8,
    this.error = false,
    this.onSubmitted,
    this.onChanged,
    required this.semanticLabel,
  });

  @override
  State<CodeBoxesV2> createState() => _CodeBoxesV2State();
}

class _CodeBoxesV2State extends State<CodeBoxesV2> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.color);
    return SizedBox(
      height: 56,
      child: Stack(children: [
        Positioned.fill(
          child: ListenableBuilder(
            listenable: Listenable.merge([widget.controller, _focus]),
            builder: (context, _) {
              final text = widget.controller.text;
              final at = text.length.clamp(0, widget.length - 1);
              return Row(children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: d,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MgColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.error
                              ? MgColors.err
                              : (_focus.hasFocus && i == at ? MgColors.focusLight : MgColors.lineInput),
                          width: _focus.hasFocus && i == at ? 2 : 1.5,
                        ),
                        boxShadow: _focus.hasFocus && i == at
                            ? [BoxShadow(color: MgColors.neonA(0.28), blurRadius: 0, spreadRadius: 4)]
                            : null,
                      ),
                      child: Text(i < text.length ? text[i] : '',
                          style: MgType.tab(MgType.h3.copyWith(color: MgColors.ink))),
                    ),
                  ),
                ],
              ]);
            },
          ),
        ),
        // The real input: invisible, full size, so a tap anywhere focuses it.
        Positioned.fill(
          child: Semantics(
            label: widget.semanticLabel,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.done,
              maxLength: widget.length,
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
                isCollapsed: true,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
