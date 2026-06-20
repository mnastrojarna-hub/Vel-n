import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'loyalty_provider.dart';
import 'loyalty_leaderboard_provider.dart';

/// Sekce „Žebříček jezdců" na stránce ranků.
///
/// Veřejná měsíční soutěž — jezdci (přezdívky) podle počtu rezervovaných dnů
/// v měsíci. Top 3 stojí na stupních vítězů, zbytek v seznamu. Vítěz měsíce
/// získá hlavní cenu: postup o 2 ranky. Každý se může v nastavení odhlásit
/// (přestane se zobrazovat a ztrácí nárok na výhru). Fail-open: bez backendu
/// (RPC zatím chybí) se celá sekce skryje.
class LoyaltyLeaderboardSection extends ConsumerWidget {
  const LoyaltyLeaderboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(loyaltyLeaderboardProvider).valueOrNull;
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    String tr(String key) => t(context).tr(key);

    // Bez backendu (null) se nic nevykreslí.
    if (data == null) return const SizedBox.shrink();

    final top3 = data.entries.take(3).toList();
    final rest = data.entries.skip(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('loyaltyLeaderboardTitle'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            tr('loyaltyLeaderboardSub'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          // Minulý vítěz — motivační banner.
          if (data.lastWinner != null) ...[
            _winnerBanner(data.lastWinner!, tr),
            const SizedBox(height: 14),
          ],

          if (data.isEmpty)
            _emptyState(tr)
          else ...[
            _Podium(top3: top3, tr: tr),
            if (rest.isNotEmpty) const SizedBox(height: 6),
            for (var i = 0; i < rest.length; i++)
              StaggeredReveal(
                index: i.clamp(0, 8),
                baseDelay: const Duration(milliseconds: 120),
                child: _ListRow(entry: rest[i], tr: tr),
              ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 18, color: Colors.white24),
          if (status != null) _optInToggle(context, ref, status, tr),
        ],
      ),
    );
  }

  Widget _winnerBanner(LeaderboardWinner w, String Function(String) tr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: legendGradientColors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('👑', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('loyaltyLastWinner')
                  .replaceAll('{nick}', w.nickname)
                  .replaceAll('{days}', '${w.days}'),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A14),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String Function(String) tr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          const Text('🏁', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            tr('loyaltyLeaderboardEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optInToggle(
    BuildContext context,
    WidgetRef ref,
    LoyaltyStatus status,
    String Function(String) tr,
  ) {
    final on = status.leaderboardOptIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('loyaltyShowMe'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            Switch(
              value: on,
              activeColor: MotoGoColors.green,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setLeaderboardOptIn(ref, v);
              },
            ),
          ],
        ),
        Text(
          on ? tr('loyaltyShowMeOn') : tr('loyaltyShowMeOff'),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: on
                ? Colors.white.withValues(alpha: 0.5)
                : MotoGoColors.amber,
            height: 1.35,
          ),
        ),
        if (on && (status.serverNickname == null ||
            status.serverNickname!.trim().isEmpty)) ...[
          const SizedBox(height: 6),
          Text(
            tr('loyaltyNeedNickname'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: MotoGoColors.green.withValues(alpha: 0.9),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PODIUM — stupně vítězů (top 3)
// ════════════════════════════════════════════════════════════════════

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  final String Function(String) tr;
  const _Podium({required this.top3, required this.tr});

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? at(int pos) {
      for (final e in top3) {
        if (e.position == pos) return e;
      }
      return null;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _pillar(at(2), 64)),
        const SizedBox(width: 8),
        Expanded(child: _pillar(at(1), 86)),
        const SizedBox(width: 8),
        Expanded(child: _pillar(at(3), 50)),
      ],
    );
  }

  Widget _pillar(LeaderboardEntry? e, double height) {
    if (e == null) return const SizedBox.shrink();
    final medal = e.position == 1
        ? '🥇'
        : e.position == 2
            ? '🥈'
            : '🥉';
    final color = e.color;
    final card = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(medal, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        _avatar(e, color),
        const SizedBox(height: 5),
        Text(
          e.nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: e.isMe ? color : Colors.white,
          ),
        ),
        Text(
          tr('loyaltyDays').replaceAll('{n}', '${e.days}'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0.12),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text(
            '#${e.position}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );

    if (e.isMe) {
      return GlowPulse(
        color: color,
        borderRadius: BorderRadius.circular(12),
        minBlur: 6,
        maxBlur: 20,
        child: card,
      );
    }
    return card;
  }

  Widget _avatar(LeaderboardEntry e, Color color) {
    final nick = e.nickname.trim();
    final initial = nick.isNotEmpty ? nick.substring(0, 1).toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: e.isLegend ? null : color,
        gradient: e.isLegend
            ? const LinearGradient(colors: legendGradientColors)
            : null,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: color.computeLuminance() > 0.5
              ? const Color(0xFF0F1A14)
              : Colors.white,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// LIST ROW — pozice 4+
// ════════════════════════════════════════════════════════════════════

class _ListRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final String Function(String) tr;
  const _ListRow({required this.entry, required this.tr});

  @override
  Widget build(BuildContext context) {
    final color = entry.color;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: entry.isMe
            ? color.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isMe
              ? color.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${entry.position}.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: entry.isMe ? color : Colors.white,
              ),
            ),
          ),
          Text(
            tr('loyaltyDays').replaceAll('{n}', '${entry.days}'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
