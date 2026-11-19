import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';

/// Poznámka v detailu / úpravě výpůjčky výbavy v obou vzhledech: v2 =
/// `MgStateBanner`, starý vzhled = barevný box jako ostatní poznámky detailu
/// (12:00 výdej, doklady). [actions] = tlačítka pod textem.
class GearNoteBox extends StatelessWidget {
  final MgTone tone;
  final String? title;
  final String text;
  final List<Widget> actions;
  const GearNoteBox({super.key, this.tone = MgTone.info, this.title, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: MgStateBanner(tone: tone, title: title ?? text, text: title == null ? null : text, actions: actions),
      );
    }
    final (Color bg, Color border, Color fg) = switch (tone) {
      MgTone.warn || MgTone.pending => (MotoGoColors.amberBg, MotoGoColors.amberBorder, const Color(0xFF92400E)),
      MgTone.ok => (MotoGoColors.greenPale, MotoGoColors.green, MotoGoColors.greenDarker),
      MgTone.err || MgTone.sos => (MotoGoColors.redBg, const Color(0xFFFCA5A5), MotoGoColors.red),
      MgTone.info => (MotoGoColors.g100, MotoGoColors.g200, MotoGoColors.g600),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Text(title!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 4),
          ],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.4)),
          for (final a in actions) ...[const SizedBox(height: 10), a],
        ]),
      ),
    );
  }
}
