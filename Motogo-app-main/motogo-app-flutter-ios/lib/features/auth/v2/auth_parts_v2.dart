import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Shared pieces of the v2 auth screens (Prihlaseni board): caps label
/// ABOVE the input (never a cut floating label in de / uk), lineInput field
/// with the inline error of the SAME validator, eye toggle, 3-segment step
/// bar, step chip, dark carrier around the primary CTA and the "nebo" rule.

/// Caps label 11.5/800 `#55705F` (board `.lbl`).
class AsmLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const AsmLabel(this.text, {super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: MgWordFit(
          minScale: 0.65,
          child: Text(text.toUpperCase(),
            style: MgType.meta.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: dark ? MgColors.onDarkMeta : MgColors.meta)),
        ),
      );
}

/// Label + input + inline error. [obscure] non-null = password with an eye
/// toggle kept in this widget (display only).
class AsmField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final bool? obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final FocusNode? focusNode;
  const AsmField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.obscure,
    this.keyboardType,
    this.autofillHints,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.formatters,
    this.capitalization = TextCapitalization.none,
    this.focusNode,
  });

  @override
  State<AsmField> createState() => _AsmFieldState();
}

class _AsmFieldState extends State<AsmField> {
  late bool _hidden = widget.obscure ?? false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final eye = widget.obscure == null
        ? null
        : Semantics(
            button: true,
            label: tr.tr(_hidden ? 'v2UxAsmShowPassword' : 'v2UxAsmHidePassword'),
            excludeSemantics: true,
            child: IconButton(
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22, color: MgColors.lead),
            ),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AsmLabel(widget.label),
      TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: _hidden,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        textInputAction: widget.action,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        inputFormatters: widget.formatters,
        textCapitalization: widget.capitalization,
        style: MgType.body.copyWith(color: MgColors.ink, fontSize: 15),
        decoration: mgInputDecoration(context, hint: widget.hint, error: widget.error, suffixIcon: eye)
            .copyWith(errorMaxLines: 6),
      ),
    ]);
  }
}

/// 3-segment progress (done / active neon gradient, todo line). Width and
/// colour animate over `sticky` 300 emphasized (instant when reduced).
class AsmStepBar extends StatelessWidget {
  final int step;
  final int total;
  final bool dark;
  const AsmStepBar({super.key, required this.step, this.total = 3, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.sticky);
    return Semantics(
      label: '$step / $total',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: d,
              curve: MgMotion.emphasized,
              height: 6,
              decoration: BoxDecoration(
                gradient: i <= step ? const LinearGradient(colors: [MgColors.neonLo, MgColors.neon]) : null,
                color: i <= step ? null : (dark ? MgColors.white(0.14) : MgColors.line),
                borderRadius: BorderRadius.circular(3),
                boxShadow: i == step ? [BoxShadow(color: MgColors.neonA(dark ? 0.45 : 0.3), blurRadius: 8)] : null,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "1/3" pill next to the bar title.
class AsmStepChip extends StatelessWidget {
  final String text;
  final bool dark;
  const AsmStepChip(this.text, {super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: dark ? MgColors.white(0.10) : MgColors.tintOk,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: dark ? MgColors.white(0.18) : MgColors.line),
        ),
        child: Text(text,
            style: MgType.tab(MgType.micro.copyWith(
                fontSize: 12, fontWeight: FontWeight.w800, color: dark ? MgColors.neonText : MgColors.link))),
      );
}

/// Dark carrier (night r18, 8 px) holding the screen's primary CTA on a
/// light sheet — a rank / neon CTA never sits on white (R5.8).
class AsmCarrier extends StatelessWidget {
  final Widget child;
  const AsmCarrier({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MgColors.night,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
        ),
        child: child,
      );
}

/// "nebo" hairline divider.
class AsmOrDivider extends StatelessWidget {
  final String label;
  const AsmOrDivider(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider(color: MgColors.line, height: 1, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: MgType.micro.copyWith(fontSize: 12, color: MgColors.meta)),
        ),
        const Expanded(child: Divider(color: MgColors.line, height: 1, thickness: 1)),
      ]);
}
