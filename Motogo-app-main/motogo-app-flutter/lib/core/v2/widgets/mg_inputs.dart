import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// v2 text-field decoration (light): white fill, 1.5 px `#7C958A` border
/// (3.22 : 1), focus 2 px `#0D6E0D`, error `#B42318` + message. Use with the
/// existing controllers / validators — logic stays where it is.
InputDecoration mgInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? error,
  String? helper,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool filledWell = false,
}) {
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(MgRadius.button),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    // Dlouhý popisek (de / fr „Nouveau mot de passe (min. 8 caractères)") se
    // zmenší, nezkrátí; nápověda smí na 2 řádky.
    label: label == null
        ? null
        : MgWordFit(
            minScale: 0.75,
            child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
          ),
    hintText: hint,
    hintMaxLines: 2,
    errorText: error,
    helperText: helper,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: filledWell ? MgColors.well : MgColors.surface,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    labelStyle: MgType.body.copyWith(color: MgColors.lead),
    floatingLabelStyle: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link),
    hintStyle: MgType.body.copyWith(color: MgColors.meta),
    helperStyle: MgType.small.copyWith(color: MgColors.meta),
    errorStyle: MgType.small.copyWith(color: MgColors.err, fontWeight: FontWeight.w700),
    errorMaxLines: 3,
    helperMaxLines: 3,
    border: b(MgColors.lineInput, 1.5),
    enabledBorder: b(MgColors.lineInput, 1.5),
    focusedBorder: b(MgColors.focusLight, 2),
    errorBorder: b(MgColors.err, 1.5),
    focusedErrorBorder: b(MgColors.err, 2),
    disabledBorder: b(MgColors.line, 1.5),
  );
}

/// Switch row (44+): title + optional sub, switch on the right.
class MgSwitchRow extends StatelessWidget {
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool dark;
  const MgSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.sub,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: MgSpace.s8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  MgWordFit(
                    minScale: 0.8,
                    child: Text(title, style: MgType.title.copyWith(color: dark ? MgColors.onDark : MgColors.ink)),
                  ),
                  if (sub != null)
                    MgWordFit(
                      minScale: 0.85,
                      child: Text(sub!, style: MgType.small.copyWith(color: dark ? MgColors.onDarkMeta : MgColors.meta)),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: MgColors.onNeon,
                activeTrackColor: MgColors.neon,
                inactiveThumbColor: dark ? MgColors.onDarkSecondary : MgColors.meta,
                inactiveTrackColor: dark ? MgColors.white(0.12) : MgColors.well,
                trackOutlineColor: WidgetStatePropertyAll(dark ? MgColors.white(0.25) : MgColors.lineInput),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Consent / check row (44 tall hit): square check + wrapping label (text
/// or rich widget). The tick pops when it changes.
class MgCheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? labelWidget;
  final bool error;
  final bool dark;
  const MgCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.labelWidget,
    this.error = false,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = error ? MgColors.err : (dark ? MgColors.white(0.5) : MgColors.lineInput);
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: value ? (dark ? MgColors.neon : MgColors.ink) : (dark ? MgColors.white(0.06) : MgColors.surface),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: value ? (dark ? MgColors.neon : MgColors.ink) : border, width: 1.5),
      ),
      child: value
          ? MgPop(trigger: value, child: Center(child: MgIcon(MgIcons.check, size: 16, color: dark ? MgColors.onNeon : MgColors.neon, stroke: 2.6)))
          : null,
    );
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      label: label,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: MgSize.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: MgSpace.s8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: box),
              const SizedBox(width: 12),
              Expanded(
                child: labelWidget ??
                    Text(label ?? '',
                        style: MgType.small.copyWith(color: dark ? MgColors.onDarkBody : MgColors.body2)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
