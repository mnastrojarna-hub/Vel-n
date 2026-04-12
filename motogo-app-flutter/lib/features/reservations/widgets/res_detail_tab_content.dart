import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../booking/booking_provider.dart';
import '../../booking/booking_models.dart';
import '../../catalog/catalog_provider.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import 'res_detail_card.dart';
import 'res_detail_row.dart';
import 'res_detail_button.dart';
import 'res_location_row.dart';

/// Sliver list content for the "Podrobnosti" tab in reservation detail.
class ResDetailTabContent extends ConsumerWidget {
  final Reservation res;
  final int rating;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final Color statusColor;
  final String statusTitle;
  final String? branchFullAddress;
  final VoidCallback onShowCancelDialog;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final ValueChanged<int> onRatingChanged;

  const ResDetailTabContent({
    super.key,
    required this.res,
    required this.rating,
    required this.doorCodesAsync,
    required this.statusColor,
    required this.statusTitle,
    required this.branchFullAddress,
    required this.onShowCancelDialog,
    required this.onOpenFinalInvoice,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = res.displayStatus;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.list(
        children: [
          ResDetailCard(children: [
            // Motorcycle name + ID
            Text(res.motoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            const SizedBox(height: 2),
            Text('#${res.shortId}', style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
            const SizedBox(height: 10),

            // Status badge
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  statusTitle,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Info rows
            ResDetailRow(label: t(context).tr('resCategory'), value: res.category ?? '–'),
            ResDetailRow(label: '${res.category ?? ""} – ${res.branchName ?? ""}', value: ''),
            ResDetailRow(label: t(context).date, value: res.dateRange),
            ResDetailRow(label: t(context).tr('resDuration'), value: '${res.dayCount} ${res.dayCount == 1 ? t(context).tr("day1") : res.dayCount < 5 ? t(context).tr("days24") : t(context).tr("days5")}'),
            ResDetailRow(label: t(context).tr('resDurationTotal'), value: '${res.dayCount} ${t(context).tr("days5")}'),
            if (res.pickupTime != null) ResDetailRow(label: t(context).pickupTime, value: res.pickupTime!),
            ResLocationRow(
              label: t(context).pickup,
              isDelivery: res.pickupMethod == 'delivery',
              address: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
              lat: res.pickupMethod == 'delivery' ? res.pickupLat : res.branchLat,
              lng: res.pickupMethod == 'delivery' ? res.pickupLng : res.branchLng,
              fallbackAddress: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
            ),
            ResLocationRow(
              label: t(context).returnLabel,
              isDelivery: res.returnMethod == 'delivery',
              address: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
              lat: res.returnMethod == 'delivery' ? res.returnLat : res.branchLat,
              lng: res.returnMethod == 'delivery' ? res.returnLng : res.branchLng,
              fallbackAddress: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
            ),
          ]),
          const SizedBox(height: 12),

          // ===== PRICE CARD =====
          ResDetailCard(children: [
            Text(t(context).tr('financialSummary'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            ResDetailRow(label: t(context).tr('totalPrice'), value: '${res.totalPrice.toStringAsFixed(0)} Kč', bold: true),
            if (res.deliveryFee != null && res.deliveryFee! > 0)
              ResDetailRow(label: t(context).tr('deliveryFee'), value: '${res.deliveryFee!.toStringAsFixed(0)} Kč'),
            if (res.extrasPrice != null && res.extrasPrice! > 0)
              ResDetailRow(label: t(context).tr('addons'), value: '${res.extrasPrice!.toStringAsFixed(0)} Kč'),
            if (res.discountAmount != null && res.discountAmount! > 0)
              ResDetailRow(
                label: '${t(context).tr('discountLabel')} ${res.discountCode ?? ""}',
                value: '−${res.discountAmount!.toStringAsFixed(0)} Kč',
                valueColor: MotoGoColors.greenDarker,
              ),
            ResDetailRow(
              label: t(context).tr('payment'),
              value: res.paymentStatus == 'paid' ? '✓ ${t(context).tr('paid')}' : res.paymentStatus.toUpperCase(),
            ),
          ]),
          const SizedBox(height: 12),

          // ===== DOOR CODES (Active only) =====
          doorCodesAsync.when(
            data: (codes) {
              if (codes.isEmpty || st != ResStatus.aktivni) return const SizedBox.shrink();
              return Column(
                children: [
                  ResDetailCard(children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Text('🔑', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(t(context).tr('accessCodes'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                        ],
                      ),
                    ),
                    ...codes.map((c) => ResDetailRow(
                      label: c.codeType == 'motorcycle' ? t(context).motorcycle : t(context).tr('accessories'),
                      value: c.sentToCustomer ? c.doorCode : (c.withheldReason ?? t(context).tr('awaitingDocs')),
                      bold: c.sentToCustomer,
                    )),
                  ]),
                  const SizedBox(height: 12),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // ===== RATING (Completed only) =====
          if (st == ResStatus.dokoncene) ...[
            ResDetailCard(children: [
              Row(
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(t(context).tr('ratingTitle'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  final selected = star <= rating;
                  return GestureDetector(
                    onTap: () async {
                      onRatingChanged(star);
                      await rateBooking(res.id, star);
                      if (context.mounted) showMotoGoToast(context, icon: '⭐', title: t(context).tr('thanks'), message: t(context).tr('starsCount').replaceAll('{n}', '$star'));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AnimatedScale(
                        scale: selected ? 1.25 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          Icons.star_rounded,
                          size: 36,
                          color: selected ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (rating == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t(context).tr('tapToRate'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400),
                  ),
                ),
              if (rating > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t(context).tr('starsCount').replaceAll('{n}', '$rating'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                  ),
                ),
            ]),
            const SizedBox(height: 12),

            // Action buttons for completed — documents section
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t(context).tr('documentsSection'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
            ),
            ResDetailButton.outlined(
              emoji: '💰',
              label: t(context).tr('finalInvoice'),
              onTap: () => onOpenFinalInvoice(context, res.id),
            ),
            const SizedBox(height: 8),
            ResDetailButton.outlined(
              emoji: '📄',
              label: t(context).tr('rentalContract'),
              onTap: () => context.push(Routes.contracts),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t(context).tr('ratingSection'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
            ),
            ResDetailButton.primary(
              emoji: '⭐',
              label: t(context).tr('reviewOnGoogle'),
              onTap: () => launchUrl(Uri.parse('https://g.page/r/motogo24/review')),
            ),
            const SizedBox(height: 12),
            ResDetailButton.primary(
              emoji: '🔁',
              label: t(context).tr('bookAgain'),
              onTap: () {
                ref.read(bookingDraftProvider.notifier).state = BookingDraft();
                ref.read(bookingMotoProvider.notifier).state = null;
                ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
                if (res.motoId != null) {
                  context.push('/moto/${res.motoId}');
                  showMotoGoToast(context, icon: '🏍️', title: t(context).reservations, message: t(context).tr('selectDateSameMoto'));
                } else {
                  context.go(Routes.home);
                  showMotoGoToast(context, icon: '🏍️', title: t(context).reservations, message: t(context).tr('selectMotorcycle'));
                }
              },
            ),
          ],

          // ===== CANCELLED SPECIFIC =====
          if (st == ResStatus.cancelled) ...[
            ResDetailCard(children: [
              ResDetailRow(label: t(context).tr('stornoFee'), value: '${res.stornoFee?.toStringAsFixed(0) ?? "0"} Kč'),
              ResDetailRow(label: t(context).tr('refundedAmount'), value: '${res.refundAmount?.toStringAsFixed(0) ?? "0"} Kč', valueColor: MotoGoColors.greenDarker),
            ]),
            const SizedBox(height: 12),
            ResDetailButton.primary(
              emoji: '🔄',
              label: t(context).tr('restoreBooking'),
              onTap: () => context.go(Routes.search),
            ),
          ],

          // ===== ACTIVE ACTIONS =====
          if (st == ResStatus.aktivni) ...[
            ResDetailButton.primary(
              emoji: '✏️',
              label: t(context).tr('extendShorten'),
              onTap: () => context.push('/reservations/${res.id}/edit'),
            ),
            const SizedBox(height: 8),
            ResDetailButton.sos(
              emoji: '🆘',
              label: t(context).sosTitle,
              onTap: () => context.push(Routes.sos),
            ),
            const SizedBox(height: 8),
            ResDetailButton.outlined(
              emoji: '📝',
              label: t(context).tr('handoverProtocol'),
              onTap: () => context.push(Routes.protocol),
            ),
          ],

          // ===== UPCOMING ACTIONS =====
          if (st == ResStatus.nadchazejici) ...[
            ResDetailButton.primary(
              emoji: '✏️',
              label: t(context).tr('editReservation'),
              onTap: () => context.push('/reservations/${res.id}/edit'),
            ),
            const SizedBox(height: 8),
            ResDetailButton.danger(
              emoji: '🗑️',
              label: t(context).tr('cancelReservationBtn'),
              onTap: onShowCancelDialog,
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Sliver list content for the "Platební karta" tab in reservation detail.
class ResPaymentCardTabContent extends StatelessWidget {
  final Reservation res;
  const ResPaymentCardTabContent({super.key, required this.res});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.list(
        children: [
          ResDetailCard(children: [
            Text(t(context).tr('paymentCardTab'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 12),
            ResDetailRow(label: t(context).tr('reservationNumber'), value: res.shortId),
            ResDetailRow(label: t(context).tr('paymentMethodLabel'), value: 'Stripe'),
            ResDetailRow(label: t(context).tr('paymentStatusLabel'), value: res.paymentStatus == 'paid' ? t(context).tr('paid') : res.paymentStatus),
            ResDetailRow(label: t(context).tr('totalAmount'), value: '${res.totalPrice.toStringAsFixed(0)} Kč', bold: true),
          ]),
          const SizedBox(height: 12),
          if (res.paymentStatus == 'paid')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: MotoGoColors.greenDark),
                  const SizedBox(width: 8),
                  Text(
                    t(context).tr('paymentProcessed'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
