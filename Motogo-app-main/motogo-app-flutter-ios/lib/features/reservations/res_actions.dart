import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/offline_guard.dart';
import '../../core/router.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_models.dart';
import '../booking/booking_provider.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/v2/catalog_mode_sync.dart' show catBeforeToday;
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
/// motorky (vybrat termín), bez motorky → Domů. v2 (majitel 2026-10-22
/// „nic nevyplňovat dvakrát“): filtr katalogu se nečistí — termín, který
/// zákazník už zadal pro další jízdu (Domů, Motorky, kalkulačka), detail
/// převezme stejně jako z katalogu (minulý termín sám zahodí) a výzva
/// „Vyber termín“ přijde jen bez použitelného termínu. Starý vzhled beze změny.
void rebookSameMoto(BuildContext context, WidgetRef ref, Reservation res) {
  final v2 = MgV2.peek(context);
  ref.read(bookingDraftProvider.notifier).state = BookingDraft();
  ref.read(bookingMotoProvider.notifier).state = null;
  if (!v2) ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
  final f = ref.read(catalogFilterProvider);
  final s = f.startDate;
  final hasDates = v2 && s != null && f.endDate != null && !catBeforeToday(s);
  if (res.motoId != null) {
    context.push('/moto/${res.motoId}');
    if (!hasDates) {
      showMotoGoToast(context, icon: '🏍️', title: t(context).reservations, message: t(context).tr('selectDateSameMoto'));
    }
  } else {
    context.go(Routes.home);
    showMotoGoToast(context, icon: '🏍️', title: t(context).reservations, message: t(context).tr('selectMotorcycle'));
  }
}
