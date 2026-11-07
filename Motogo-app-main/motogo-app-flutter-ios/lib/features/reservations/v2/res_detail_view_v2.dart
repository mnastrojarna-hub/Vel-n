import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/shell_actions.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../documents/booking_doc_viewer.dart' show bookingDocsProvider;
import '../../routes/ride_booking_section.dart';
import '../../routes/ride_provider.dart' show bookingRidesProvider;
import '../res_actions.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/paid_change_banner.dart';
import '../widgets/res_rating_card.dart';
import 'res_action_tiles_v2.dart';
import 'res_coted_v2.dart';
import 'res_detail_hero_v2.dart';
import 'res_docs_v2.dart';
import 'res_money_v2.dart';
import 'res_sections_v2.dart';
import 'res_status_v2.dart';
import 'res_timeline_v2.dart';

/// Reservation detail, v2 look (PLAN §2.4.2, seam S). DUMB view: the old
/// `_DetailState` keeps the 5 s refresh, realtime listener, loading / error
/// views and every action; it passes them here. Both old tabs (Podrobnosti
/// / Platba) become sections of one page — nothing dropped.
class ResDetailV2View extends ConsumerStatefulWidget {
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
  ConsumerState<ResDetailV2View> createState() => _ResDetailV2ViewState();
}

class _ResDetailV2ViewState extends ConsumerState<ResDetailV2View> {
  // Cíle dlaždic „Dokumenty" / „Hodnotit" / „Jízdy" (posun na sekci).
  final _docsKey = GlobalKey(debugLabel: 'res-docs');
  final _ratingKey = GlobalKey(debugLabel: 'res-rating');
  final _ridesKey = GlobalKey(debugLabel: 'res-rides');

  Reservation get res => widget.res;

  void _reveal(GlobalKey key) =>
      resRevealSection(context, key, MgMotion.of(context, MgMotion.sheet), MgMotion.out);

  /// Dlaždice pod CO TEĎ (Reservation board) — jen akce, které detail má:
  /// úprava, navigace (jako „Kdy a kde"), posun na dokumenty / hodnocení /
  /// jízdy, storno (jen nadcházející), znovu rezervovat, konečná faktura.
  List<ResActionTile> _tiles(AppTranslations tr, ResCoCta cta, VoidCallback edit) {
    final st = res.displayStatus;
    final docs = ref.watch(bookingDocsProvider(res.id)).valueOrNull ?? const {};
    final hasDocs = ResDocsV2.hasItems(res, docs);
    final pickupNav = resNavTarget(res, widget.branchFullAddress, pickup: true);
    final returnNav = resNavTarget(res, widget.branchFullAddress, pickup: false);
    bool canNav(({double? lat, double? lng, String? fallback}) n) =>
        (n.lat != null && n.lng != null) || (n.fallback ?? '').isNotEmpty;
    // „Upravit" je dlaždice, pokud není hlavním tlačítkem CO TEĎ (přistavení).
    final editTile = cta != ResCoCta.edit;
    switch (st) {
      case ResStatus.nadchazejici:
        return [
          if (editTile) ResActionTile(ResTileIcons.edit, tr.tr('edit'), edit),
          if (canNav(pickupNav))
            ResActionTile(ResTileIcons.navigate, tr.tr('v2ResNavigate'),
                () => resNavigate(res, widget.branchFullAddress, pickup: true)),
          if (hasDocs) ResActionTile(ResTileIcons.docs, tr.tr('v2UxRpTileDocs'), () => _reveal(_docsKey)),
          ResActionTile(ResTileIcons.cancel, tr.tr('cancel'), widget.onShowCancelDialog, destructive: true),
        ];
      case ResStatus.aktivni:
        return [
          if (editTile) ResActionTile(ResTileIcons.edit, tr.tr('edit'), edit),
          if (canNav(returnNav))
            ResActionTile(ResTileIcons.navigate, tr.tr('v2ResNavigate'),
                () => resNavigate(res, widget.branchFullAddress, pickup: false)),
          if (hasDocs) ResActionTile(ResTileIcons.docs, tr.tr('v2UxRpTileDocs'), () => _reveal(_docsKey)),
        ];
      case ResStatus.dokoncene:
        final rides = ref.watch(bookingRidesProvider(res.id)).valueOrNull ?? const [];
        return [
          ResActionTile(ResTileIcons.rate, tr.tr('rateBtn'), () => _reveal(_ratingKey)),
          ResActionTile(ResTileIcons.again, tr.tr('v2HomeFnAgain'), () => rebookSameMoto(context, ref, res)),
          ResActionTile(ResTileIcons.invoice, tr.tr('invoiceLabel'), () => widget.onOpenFinalInvoice(context, res.id)),
          if (rides.isNotEmpty) ResActionTile(ResTileIcons.rides, tr.tr('v2RideSubRides'), () => _reveal(_ridesKey)),
        ];
      case ResStatus.cancelled:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final st = res.displayStatus;
    final pending = ref.watch(pendingBookingFabProvider).valueOrNull;
    final pay = resPayFlag(res, pending);
    final co = resCoState(res, pay);
    void edit() => context.push('/reservations/${res.id}/edit');
    final doorCodesAsync = widget.doorCodesAsync;
    final onBack = widget.onBack;
    final tiles = _tiles(tr, resCoCta(res, co, doorCodesAsync.valueOrNull), edit);

    final sheet = Container(
      decoration: const BoxDecoration(
        color: MgColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.onStaleRetry != null) MgStaleNote(onRetry: widget.onStaleRetry!),
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
                onRestore: () => widget.onRestoreBooking(context, res),
                onRebook: () => rebookSameMoto(context, ref, res),
                onPay: pending == null ? null : () => openPendingPayment(context, ref, pending),
                onNavigatePickup: () => resNavigate(res, widget.branchFullAddress, pickup: true),
                onNavigateReturn: () => resNavigate(res, widget.branchFullAddress, pickup: false),
                pickupAddress: widget.branchFullAddress,
                // Hodnocení jízdy (jen dokončená) — tmavá karta uvnitř CO TEĎ
                // nad „Znovu rezervovat" (V21 §5.3), tytéž volby i zápis.
                rating: st == ResStatus.dokoncene
                    ? KeyedSubtree(key: _ratingKey, child: ResRatingCard(res: res, look: RatingLook.dark))
                    : null,
              ),
            ),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              ResActionTilesV2(tiles: tiles),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ResWhenWhereV2(res: res, branchFullAddress: widget.branchFullAddress),
            ResGearV2(res: res, doorCodes: doorCodesAsync.valueOrNull),
            const SizedBox(height: 12),
            ResMoneyV2(res: res),
          ]),
        ),
        KeyedSubtree(
          key: _docsKey,
          child: ResDocsV2(res: res, onOpenFinalInvoice: widget.onOpenFinalInvoice, onOpenContract: widget.onOpenContract),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ResHistoryV2(res: res),
            // Projeté jízdy z této výpůjčky — dnešní sekce beze změny.
            KeyedSubtree(key: _ridesKey, child: BookingRidesSection(bookingId: res.id)),
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
