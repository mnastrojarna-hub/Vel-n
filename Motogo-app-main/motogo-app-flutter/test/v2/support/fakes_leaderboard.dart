// "Žebříček jezdců" fixtures (flag `loyalty_leaderboard` ON): podium,
// list rows (one is "me"), last month's winner, or the empty month.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/features/loyalty/loyalty_leaderboard_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_levels_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';

import 'fakes_home.dart' show loyaltyAt;
import 'fakes_profile_sub.dart' show levels;

LeaderboardEntry _e(int pos, String nick, int level, double km, {int gain = 0, bool me = false}) =>
    LeaderboardEntry(position: pos, nickname: nick, days: 4, km: km, rankGain: gain, level: level, percent: level, colorHex: '#9CA3AF', isMe: me);

LeaderboardData kLeaderboard({bool empty = false}) => LeaderboardData(
      month: '2026-11',
      entries: empty
          ? const []
          : [
              _e(1, 'Jezdec1', 12, 812, gain: 2),
              _e(2, 'Jan', 6, 410, me: true),
              _e(3, 'Kuba', 3, 288),
              _e(4, 'Petra', 9, 201, gain: 1),
              _e(5, 'Motomilan', 2, 96),
            ],
      lastWinner: const LeaderboardWinner(nickname: 'Jezdec1', days: 9, month: '2026-10'),
    );

/// Everything `/loyalty` reads, with the leaderboard ON.
List<Override> leaderboardOverrides({bool empty = false, bool optIn = true, String? nick = 'Jan'}) {
  final st = loyaltyAt(6);
  return [
    loyaltyStatusProvider.overrideWith((ref) async => LoyaltyStatus(
          level: st.level,
          percent: st.percent,
          rankName: st.rankName,
          colorHex: st.colorHex,
          qualifyingCount: st.qualifyingCount,
          nextRankName: st.nextRankName,
          nextPercent: st.nextPercent,
          bookingsToNext: st.bookingsToNext,
          leaderboardOptIn: optIn,
          serverNickname: nick,
        )),
    loyaltyLevelsProvider.overrideWith((ref) async => levels()),
    loyaltyLeaderboardEnabledProvider.overrideWith((ref) async => true),
    loyaltyLeaderboardProvider.overrideWith((ref) async => kLeaderboard(empty: empty)),
  ];
}
