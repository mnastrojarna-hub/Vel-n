import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'onboarding_parts_v2.dart';

/// First-run language picker in the v2 look (board Prihlaseni "Jazyk"):
/// dark page, logo tile 64, "MOTO GO 24" 22/900, the bilingual pick line,
/// a 2-column grid of 52 px glass tiles (drawn flag 28 + native name
/// 15/800, never broken inside a word) and the footnote. [onPick] = the
/// old overlay's `_selectLang` (same code, same effects); nothing here
/// decides anything. Content enters once (`enter` 450).
class OnboardingLangV2 extends StatelessWidget {
  /// (code, native name) in the old overlay's order.
  final List<(String, String)> langs;
  final ValueChanged<String> onPick;
  const OnboardingLangV2({super.key, required this.langs, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final pad = MediaQuery.paddingOf(context);
    return OnbDarkPage(
      child: LayoutBuilder(builder: (context, box) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 24, 16, pad.bottom + 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (box.maxHeight - pad.top - pad.bottom - 48).clamp(0, double.infinity)),
            child: IntrinsicHeight(
              child: MgEnter(
                child: Column(children: [
                  const Spacer(flex: 2),
                  const OnbLogoTile(size: 64),
                  const SizedBox(height: 16),
                  Text('MOTO GO 24',
                      textAlign: TextAlign.center,
                      style: MgType.h2.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark, letterSpacing: 1.5)),
                  const SizedBox(height: 36),
                  Semantics(
                    header: true,
                    child: Text(tr.tr('v2UxShLangPick'),
                        textAlign: TextAlign.center,
                        style: MgType.small.copyWith(fontSize: 13, color: MgColors.onDarkLead)),
                  ),
                  const SizedBox(height: 28),
                  for (var row = 0; row < (langs.length + 1) ~/ 2; row++) ...[
                    if (row > 0) const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _tile(langs[row * 2])),
                      const SizedBox(width: 12),
                      Expanded(child: row * 2 + 1 < langs.length ? _tile(langs[row * 2 + 1]) : const SizedBox()),
                    ]),
                  ],
                  const Spacer(flex: 3),
                  const SizedBox(height: 24),
                  Text(tr.tr('v2UxShLangNote'),
                      textAlign: TextAlign.center,
                      style: MgType.small.copyWith(color: MgColors.onDarkMeta)),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _tile((String, String) l) => _LangTile(code: l.$1, name: l.$2, onTap: () => onPick(l.$1));
}

class _LangTile extends StatelessWidget {
  final String code, name;
  final VoidCallback onTap;
  const _LangTile({required this.code, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: name,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: Container(
            key: ValueKey('onb-lang-$code'),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.white(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.white(0.14)),
            ),
            child: Row(children: [
              OnbFlag(code),
              const SizedBox(width: 10),
              Expanded(
                child: MgWordFit(
                  minScale: 0.7,
                  child: Text(name, style: MgType.title.copyWith(color: MgColors.onDark)),
                ),
              ),
            ]),
          ),
        ),
      );
}
