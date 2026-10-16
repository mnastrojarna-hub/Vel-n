import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../messages/messages_provider.dart';
import '../../reservations/reservation_models.dart';
import 'home_reveal.dart';

/// "MotoGo ti píše" (V22 `.msg`, only with unread notices): newest unread
/// title → `/messages?n=<id>` (the same deep-link parameter the push uses).
class HomeMessageRowV2 extends ConsumerWidget {
  const HomeMessageRowV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final msgs = ref.watch(adminMessagesProvider).valueOrNull ?? const <AdminMessage>[];
    AdminMessage? m;
    for (final x in msgs) {
      if (!x.read) {
        m = x;
        break;
      }
    }
    if (m == null) return const SizedBox.shrink();
    final msg = m;
    final title = (msg.titleFor(tr.lang) ?? msg.messageFor(tr.lang) ?? '').trim();
    final gift = msg.type == 'voucher';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: HomeReveal(
        index: 2,
        sessionKey: 'home-msg',
        child: MgFabAvoid(kind: MgAvoidKind.tap, child: MgCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          onTap: () => mgPushOrGo(context, '${Routes.messages}?n=${msg.id}'),
          semanticLabel: '${tr.tr('v2HomeMsgPrefix')} $title',
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              MgIconTileDark(gift ? MgIcons.gift : MgIcons.mail),
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: MgColors.sosDot,
                    shape: BoxShape.circle,
                    border: Border.all(color: MgColors.surface, width: 2),
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (gift)
                  Text(tr.tr('v2HomeMsgGift').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${tr.tr('v2HomeMsgPrefix')} ',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: MgColors.ink)),
                    TextSpan(text: title),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.body.copyWith(height: 1.3, color: MgColors.body2),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      )),
    );
  }
}

/// "Další rezervace (n)" under the ticket (only with 2+ bookings): the next
/// one's bike · number · dates (the second card of today's Home) →
/// Rezervace tab (as today's "VŠE" link).
class HomeMoreBookingsRowV2 extends StatelessWidget {
  final int count;
  final Reservation? next;
  const HomeMoreBookingsRowV2({super.key, required this.count, this.next});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: MgFabAvoid(kind: MgAvoidKind.tap, child: MgCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        onTap: () => GoRouter.maybeOf(context)?.go(Routes.reservations),
        semanticLabel: tr.trArgs('v2HomeMore', {'n': count}),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            const MgIconTileDark(MgIcons.calendarCheck),
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(colors: [MgColors.neonHi, MgColors.neonLo]),
                  border: Border.all(color: MgColors.surface, width: 2),
                ),
                child: Center(
                  child: Text('$count',
                      style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, height: 1, color: MgColors.onNeon))),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // „Kolejne rezerwacje (1)" vedle „Zobacz wszystkie": zmenšit, nedělit.
              MgWordFit(
                minScale: 0.75,
                child: Text(tr.trArgs('v2HomeMore', {'n': count}),
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              ),
              Text(
                  next == null
                      ? tr.tr('homeActiveReservations')
                      : '${next!.motoName} · ${next!.shortId} · ${next!.dateRange}',
                  style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
            ]),
          ),
          Text(tr.tr('homeViewAll'), style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
          const SizedBox(width: 4),
          const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
        ]),
      )),
    );
  }
}
