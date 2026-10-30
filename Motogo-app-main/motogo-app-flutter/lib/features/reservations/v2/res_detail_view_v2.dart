import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/shell_actions.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/state_views.dart';
import '../../routes/ride_booking_section.dart';
import '../res_actions.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/paid_change_banner.dart';
import '../widgets/res_rating_card.dart';
import 'res_coted_v2.dart';
import 'res_detail_hero_v2.dart';
import 'res_docs_v2.dart';
import 'res_fit_v2.dart';
import 'res_money_v2.dart';
import 'res_sections_v2.dart';
import 'res_status_v2.dart';
import 'res_timeline_v2.dart';

/// Reservation detail, v2 look (PLAN §2.4.2, seam S). DUMB view: the old
/// `_DetailState` keeps the 5 s refresh, realtime listener, loading / error
/// views and every action; it passes them here. Both old tabs (Podrobnosti
/// / Platba) become sections of one page — nothing dropped.
class ResDetailV2View extends ConsumerWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final String? branchFullAddress;
  final VoidCallback? onStaleRetry;
  final VoidCallback onBack;
  final VoidCallback onShowCancelDialog;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final Future<void> Function(BuildContext, String) onOpenContract;
  final Future<void> Function(BuildContext, Reservation) onRestoreBooking;

  const ResDetailV2View({
    super.key,
    required this.res,
    required this.doorCodesAsync,
    required this.branchFullAddress,
    required this.onStaleRetry,
    required this.onBack,
    required this.onShowCancelDialog,
    required this.onOpenFinalInvoice,
    required this.onOpenContract,
    required this.onRestoreBooking,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = res.displayStatus;
    final pending = ref.watch(pendingBookingFabProvider).valueOrNull;
    final pay = resPayFlag(res, pending);
    final co = resCoState(res, pay);
    void edit() => context.push('/reservations/${res.id}/edit');

    // Akce pod CO TEĎ: úpravy / storno jako dnes u nadcházející; „Upravit"
    // jen když není hlavním tlačítkem CO TEĎ.
    final tiles = <(String, String, VoidCallback, bool)>[
      if (st == ResStatus.nadchazejici && (co == ResCoState.unpaid || co == ResCoState.verifying))
        (MgIcons.edit, tr.tr('editReservation'), edit, false),
      if (st == ResStatus.nadchazejici) (MgIcons.calendarX, tr.tr('cancelReservationBtn'), onShowCancelDialog, true),
    ];

    final sheet = Container(
      decoration: const BoxDecoration(
        color: MgColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (onStaleRetry != null) MgStaleNote(onRetry: onStaleRetry!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Zaplacená výměna / úprava se ještě zapisuje (D6) — beze změny.
            PaidChangeBanner(bookingId: res.id),
            MgReveal(index: 0, child: ResTitleBlockV2(res: res)),
            const SizedBox(height: 24),
            MgReveal(index: 1, child: ResJourneyV2(res: res)),
            const SizedBox(height: 24),
            MgEnter(
              child: ResCoTedV2(
                res: res,
                doorCodesAsync: doorCodesAsync,
                state: co,
                payTimeLeft: co == ResCoState.unpaid ? pending?.timeLabel : null,
                onEdit: edit,
                onRestore: () => onRestoreBooking(context, res),
                onRebook: () => rebookSameMoto(context, ref, res),
                onPay: pending == null ? null : () => openPendingPayment(context, ref, pending),
              ),
            ),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Vedle sebe jen když se popisky vejdou celými slovy (de
              // „Reservierung bearbeiten" na 320 dp) — jinak pod sebou.
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 8 * (tiles.length - 1)) / tiles.length - _ActionTile.chrome;
                final row = tiles.every((x) => resWordsFit(context, x.$2, _ActionTile.style, w, minScale: 0.85));
                Widget tile(int i) =>
                    _ActionTile(icon: tiles[i].$1, label: tiles[i].$2, onTap: tiles[i].$3, destructive: tiles[i].$4);
                if (!row) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: 8), tile(i)],
                  ]);
                }
                return Row(children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: tile(i)),
                  ],
                ]);
              }),
            ],
          ]),
        ),
        // Hodnocení jízdy (jen dokončená) — dnešní karta s oběma volbami.
        if (st == ResStatus.dokoncene) ...[
          const SizedBox(height: 16),
          ResRatingCard(res: res, look: RatingLook.light),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ResWhenWhereV2(res: res, branchFullAddress: branchFullAddress),
            ResGearV2(res: res),
            const SizedBox(height: 12),
            ResMoneyV2(res: res),
          ]),
        ),
        ResDocsV2(res: res, onOpenFinalInvoice: onOpenFinalInvoice, onOpenContract: onOpenContract),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ResHistoryV2(res: res),
            // Projeté jízdy z této výpůjčky — dnešní sekce beze změny.
            BookingRidesSection(bookingId: res.id),
            const SizedBox(height: 16),
            const MgSupportRow(),
          ]),
        ),
      ]),
    );

    // Hero + list v JEDNOM sloupci: list (−24 px přes fotku, V22 `.sht`) se
    // kreslí nad hero. (Overlap MgPage mezi slivery viewport kreslí pod
    // hlavičkou — první sliver je navrchu.)
    return MgPage(
      overlapHero: false,
      pinnedBack: onBack,
      pinnedTitle: res.motoName,
      sections: [
        ResDetailHeroV2(res: res, onBack: onBack),
        Transform.translate(offset: const Offset(0, -24), child: sheet),
      ],
    );
  }
}

/// Light action tile under CO TEĎ (V22 `.at`), red when destructive.
class _ActionTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionTile({required this.icon, required this.label, required this.onTap, required this.destructive});

  static final style = MgType.small.copyWith(fontWeight: FontWeight.w800);

  /// Horizontal padding + border + icon + gap around the label.
  static const chrome = 24 + 2 + 20 + 8.0;

  @override
  Widget build(BuildContext context) {
    final c = destructive ? MgColors.err : MgColors.link;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: destructive ? MgColors.errBorder : MgColors.line),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            MgIcon(icon, size: 20, color: c),
            const SizedBox(width: 8),
            Flexible(
              child: MgWordFit(
                minScale: 0.85,
                alignment: Alignment.center,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: destructive ? MgColors.err : MgColors.ink)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
