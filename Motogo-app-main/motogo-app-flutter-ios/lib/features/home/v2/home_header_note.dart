import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../auth/auth_provider.dart';
import 'home_state.dart';

/// Concierge note under the motto (compact: one small line, scales first):
/// birthday → state note (S3 / S6 / S7 / S8 / S9) → S0 / S10 idle line
/// (only when [idle]: the header has no Velín banner line).
/// An unread message is NOT repeated here — "MotoGo ti píše" right below
/// the hero shows it (compact header, V22 §2.4 #1). Nothing to say →
/// nothing drawn.
class HomeHeaderNote extends ConsumerWidget {
  final HomeSnapshot snap;
  final String nick;
  final bool idle;
  const HomeHeaderNote({super.key, required this.snap, required this.nick, this.idle = true});

  static bool _birthday(Map<String, dynamic>? profile, DateTime now) {
    final raw = profile?['date_of_birth'];
    final d = raw is String ? DateTime.tryParse(raw) : null;
    return d != null && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final now = DateTime.now();
    final bike = snap.res?.motoName ?? '';
    final String? text;
    if (_birthday(profile, now)) {
      text = tr.trArgs('v2HomeNoteBirthday', {'nick': nick});
    } else {
      text = switch (snap.ticket) {
        HomeTicket.s3 => tr.tr('v2HomeNoteDocs'),
        HomeTicket.s6 => tr.tr('v2HomeNoteReady'),
        HomeTicket.s7 => tr.trArgs('v2HomeNoteToday', {'bike': bike}),
        HomeTicket.s8 => tr.tr('v2HomeNoteRide'),
        HomeTicket.s9 => tr.tr('v2HomeNoteReturn'),
        HomeTicket.s0 || HomeTicket.s10 => idle ? tr.tr('v2HomeNoteIdle') : null,
        _ => null,
      };
    }
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: MgEnter(
        delay: const Duration(milliseconds: 150),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: rank.uiDark, width: 1.5),
              boxShadow: rank.softGlow(blur: 8, dy: 0),
            ),
            child: Center(child: MgIcon(MgIcons.spark, size: 12, color: rank.uiDark)),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Kompaktní hlavička (V22 §2.4 #1): nejdřív JEDEN řádek (text se
            // zmenší do 75 %); delší vzkaz se zalomí v mezeře — celý, nikdy
            // useknutý „…" (verify:render).
            child: MgWordFit(
              minScale: 0.75,
              fitLines: 1,
              child: Text(text, style: MgType.small.copyWith(height: 1.3, color: MgColors.onDarkLead)),
            ),
          ),
        ]),
      ),
    );
  }
}
