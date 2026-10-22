import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/offline_guard.dart';
import '../../core/router.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_models.dart';
import '../booking/booking_provider.dart';
import '../catalog/catalog_provider.dart';
import '../documents/booking_doc_viewer.dart';
import '../documents/doc_open_runner.dart';
import 'reservation_models.dart';

/// Akce detailu rezervace sdílené starým (`ResDetailTabContent`) i v2
/// vzhledem (`ResDetailV2View`) — PŘESUNUTO beze změny (PLAN §0.5 PM-5).

/// Otevře reálný dokument rezervace 1:1 (podepsaný protokol / smlouva) —
/// průběh (po 15 s „Zrušit"), pojistka proti dvojímu klepnutí; offline
/// skutečný důvod + „Zkusit znovu", jinak „zatím není k dispozici".
Future<void> openBookingDoc(BuildContext context, Reservation res, String type, String title) {
  final tr = t(context);
  return runDocOpen(context,
      what: tr.tr('eoDocLoadFail'),
      where: 'res_doc_open',
      op: (wanted) async {
        final opened = await openBookingDocument(context,
            bookingId: res.id, type: type, title: title, wanted: wanted);
        if (opened) return;
        if (!await OfflineGuard.pingSupabase()) throw const SocketException('offline');
        if (!context.mounted || !wanted()) return;
        showMotoGoToast(context, icon: '📄', title: title, message: tr.tr('docNotAvailableYet'));
      });
}

/// „Znovu rezervovat" (dokončená rezervace): čistý formulář → detail stejné
/// motorky (vybrat termín), bez motorky → Domů.
void rebookSameMoto(BuildContext context, WidgetRef ref, Reservation res) {
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
}
