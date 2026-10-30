import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/booking_rules.dart';
import '../../core/i18n/i18n_provider.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'ride_location.dart' show rideTrOpt;
import 'ride_recorder.dart';

/// Rezervace, u které se má PRÁVĚ TEĎ nahrávat, jinak null.
///
/// Dřív stačil kalendářní den v rozsahu termínu — jenže to je od PŮLNOCI
/// dne vyzvednutí do půlnoci po vrácení. Do stopy tak šla i cesta autem na
/// pobočku a domů (v hustých fixech, tedy jako ujeté kilometry motorkou).
/// Nahrává se proto až od skutečného PŘEVZETÍ (`picked_up_at` — předávací
/// protokol na obsluhované pobočce, kód do boxu na samoobslužné) do VRÁCENÍ
/// (`returned_at`). Pojistka pro rezervaci aktivovanou jen nočním cronem bez
/// odbavení: od naplánovaného času vyzvednutí. Výpůjčka JEN výbavy
/// (`booking_kind = 'gear'`) se nikdy nenahrává — není to jízda na motorce
/// a nesmí ani ukončit pozastavenou vlastní cestu. [now] jen pro testy.
///
/// [prefer] = výpůjčka, do které se právě nahrává: zůstává, dokud běží
/// i po dnešku (`_rideKeepsRental`). Dvě motorky na jednom účtu (kamarád
/// si dnes převzal druhou) tak jezdcovu cestu nerozdělí a jeho km nepadnou
/// do cizí výpůjčky (seznam je řazený od nejnovějšího začátku).
String? rideActiveBookingId(List<Reservation> list, {DateTime? now, String? prefer}) {
  final at = now ?? DateTime.now();
  if (prefer != null && _rideKeepsRental(list, prefer, at)) return prefer;
  for (final r in list) {
    if (r.isGearOnly) continue; // výbava ≠ motorka
    if (!r.inRentalTerm) continue; // kalendářně; vydání řeší issuedAt níže
    if (r.returnedAt != null) continue; // vráceno → dál se nenahrává
    // převzato → nahrávat; `issuedAt` = kód + podepsaný protokol na pobočce
    // (same-day platba dřív nastavila picked_up_at už při potvrzení, 2026-09-28)
    if (r.issuedAt != null) return r.id;
    if (r.status == 'active' && !at.isBefore(_ridePickupAt(r))) return r.id;
  }
  return null;
}

/// Nahrávaná výpůjčka [id] jede dál: převzatá, nevrácená, neukončená (ani
/// SOS), termín běží a končí AŽ PO dnešku a žádná jiná ji nenahradila (SOS
/// výměna motorky). Končí-li dnes, rozhoduje pořadí seznamu — navazující
/// výpůjčka převzatá dnes ji vystřídá (vrácení zapsané obsluhou později).
bool _rideKeepsRental(List<Reservation> list, String id, DateTime at) {
  Reservation? r;
  for (final x in list) {
    if (x.id == id) r = x;
    if (x.replacementForBookingId == id && x.status != 'cancelled') return false;
  }
  if (r == null || r.isGearOnly || !r.inRentalTerm || r.returnedAt != null) return false;
  if (r.status == 'completed' || r.endedBySos) return false;
  if (r.issuedAt == null && r.status != 'active') return false;
  final end = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
  return end.isAfter(DateTime(at.year, at.month, at.day));
}

/// Kdy zákazník výpůjčku [id] převzal (`picked_up_at`, jinak vydání /
/// naplánované vyzvednutí). Záznamník podle toho dělí body při výměně
/// motorky (SOS) a navazující výpůjčce.
DateTime? ridePickupOf(List<Reservation> list, String? id) {
  if (id == null) return null;
  for (final r in list) {
    if (r.id == id) return r.pickedUpAt ?? r.issuedAt ?? _ridePickupAt(r);
  }
  return null;
}

/// Naplánované vyzvednutí = den začátku + `pickup_time` (HH:MM); bez času
/// se bere konec dne, aby se bez odbavení nenahrávalo předčasně.
DateTime _ridePickupAt(Reservation r) {
  final d = r.startDate;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(r.pickupTime ?? '');
  // Stará značka 00:01 (= „kdykoliv během prvního dne“, ne plán) → jako bez
  // času; zvolený čas vyzvednutí (i na samoobsluze) se používá.
  final noPlan = isLegacyAllDayPickupTime(r.pickupTime);
  if (m == null || noPlan) return DateTime(d.year, d.month, d.day, 23, 59);
  return DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// Neviditelný hlídač (sedí v app shellu vedle `LoyaltyLevelUpWatcher`):
/// jakmile má zákazník běžící výpůjčku a povolenou polohu, rozjede se záznam
/// jízdy; po skončení výpůjčky se jízda uzavře. Nic nevykresluje — jen
/// ukáže jednorázovou hlášku záznamníku (`notice`) jako snackbar.
class RideRecorderWatcher extends ConsumerStatefulWidget {
  const RideRecorderWatcher({super.key});

  @override
  ConsumerState<RideRecorderWatcher> createState() => _RideRecorderWatcherState();
}

class _RideRecorderWatcherState extends ConsumerState<RideRecorderWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final n = ref.read(rideRecorderProvider.notifier);
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      // Do pozadí → nasbírané body rovnou odešleme (OS může stream uspat).
      n.flush();
    } else if (s == AppLifecycleState.resumed) {
      // Zpět v popředí → zkontrolovat GPS stream (jen teď ho Android smí
      // znovu spustit) a doposlat, co se nasbíralo.
      n.onAppResumed();
    }
  }

  /// Jednorázová hláška záznamníku (navázání cesty, uložená vlastní cesta…).
  void _showNotice(String key, Map<String, String>? args) {
    if (ref.read(rideRecorderProvider).notice != key) return; // už ukázaná
    final n = ref.read(rideRecorderProvider.notifier);
    final tr = AppTranslations.of(ref.read(localeProvider).languageCode);
    final text = rideTrOpt(tr, key, args ?? const {});
    final m = ScaffoldMessenger.maybeOf(context);
    if (text != null && m != null) {
      // Delší hláška (otázka „cesta stojí od …") potřebuje čas na přečtení.
      final secs = (text.length / 15).round().clamp(6, 12);
      m.showSnackBar(SnackBar(content: Text(text), duration: Duration(seconds: secs)));
    }
    n.consumeNotice();
  }

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(reservationsProvider);
    final st = ref.watch(rideRecorderProvider);
    // Dokud rezervace nedorazily, NIC nerozhodujeme — prázdný seznam při
    // načítání by jinak vypadal jako „výpůjčka skončila" a rozjetou jízdu
    // by zbytečně uzavřel (a po dojetí seznamu by vznikla druhá).
    if (!res.hasValue) return const SizedBox.shrink();
    final list = res.value ?? const <Reservation>[];
    // Nahrávaná výpůjčka má přednost, dokud běží (dvě motorky na účtu).
    final bookingId = rideActiveBookingId(list, prefer: st.manual ? null : st.bookingId);
    final pickup = ridePickupOf(list, bookingId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = ref.read(rideRecorderProvider.notifier);
      // Převzatá výpůjčka → ruční start se přiřadí k ní (ne podle data).
      n.setActiveBooking(bookingId, pickedUpAt: pickup);
      // Hláška záznamníku (i obnovená z relace po restartu) — jednou.
      if (st.notice != null) _showNotice(st.notice!, st.noticeArgs);
      if (bookingId != null) {
        if (n.stopPending) {
          // Předchozí jízdu nešlo uložit (offline) — nejdřív ji dořešit.
          if (n.canRetryStop) n.stop();
        } else if (st.recording && st.manual && st.bookingId != bookingId && st.isPaused) {
          // Vlastní cesta stojí a zákazník převzal výpůjčku → vlastní uložit,
          // nahrávat výpůjčku. Jedoucí vlastní jízdu nepřerušujeme.
          n.finishOwnForRental(bookingId);
        } else if (!st.manual && st.bookingId != null && st.bookingId != bookingId &&
            (st.recording || st.rideId != null)) {
          // Nahrává se do JINÉ výpůjčky (SOS výměna motorky, navazující
          // výpůjčka) → starou uložit, body nové motorky do nové jízdy.
          n.switchRental(bookingId);
        } else {
          // Pozastavená cesta má recording = true → ensureRecording nic nedělá.
          n.ensureRecording(bookingId);
        }
      } else if (st.manual && n.stopPending && n.canRetryStop) {
        // Ruční jízdu jezdec ukončil, ale server to nevzal (offline) —
        // dokud ji nikdo neuloží, zkoušíme to dál. Jinak by lokálně visela
        // navždy a jezdec viděl „příliš krátká", i když jel 80 km.
        n.stop();
      } else if (!st.manual &&
          (st.recording || st.rideId != null || n.stopPending) &&
          n.canRetryStop) {
        // Výpůjčka skončila (i když appka mezitím neběžela) → jízdu uzavři
        // — v kterékoli fázi (i pozastavenou), i když ji server ještě nemá
        // (celá bez dat). `canRetryStop` drží odstup po neúspěchu (offline).
        n.stop();
      }
    });

    return const SizedBox.shrink();
  }
}
