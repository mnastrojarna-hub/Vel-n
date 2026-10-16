import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/booking_rules.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'ride_recorder.dart';

/// Neviditelný hlídač (sedí v app shellu vedle `LoyaltyLevelUpWatcher`):
/// jakmile má zákazník běžící výpůjčku a povolenou polohu, rozjede se záznam
/// jízdy; po skončení výpůjčky se jízda uzavře. Nic nevykresluje, UI nemění.
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

  /// Rezervace, u které se má PRÁVĚ TEĎ nahrávat, jinak null.
  ///
  /// Dřív stačil kalendářní den v rozsahu termínu — jenže to je od PŮLNOCI
  /// dne vyzvednutí do půlnoci po vrácení. Do stopy tak šla i cesta autem na
  /// pobočku a domů (v hustých fixech, tedy jako ujeté kilometry motorkou).
  /// Nahrává se proto až od skutečného PŘEVZETÍ (`picked_up_at` — předávací
  /// protokol na obsluhované pobočce, kód do boxu na samoobslužné) do VRÁCENÍ
  /// (`returned_at`). Pojistka pro rezervaci aktivovanou jen nočním cronem bez
  /// odbavení: od naplánovaného času vyzvednutí.
  String? _activeBookingId(List<Reservation> list) {
    final now = DateTime.now();
    for (final r in list) {
      if (!r.inRentalTerm) continue; // kalendářně; vydání řeší issuedAt níže
      if (r.returnedAt != null) continue; // vráceno → dál se nenahrává
      // převzato → nahrávat; `issuedAt` = kód + podepsaný protokol na pobočce
      // (same-day platba dřív nastavila picked_up_at už při potvrzení, 2026-09-28)
      if (r.issuedAt != null) return r.id;
      if (r.status == 'active' && !now.isBefore(_pickupAt(r))) return r.id;
    }
    return null;
  }

  /// Naplánované vyzvednutí = den začátku + `pickup_time` (HH:MM); bez času
  /// se bere konec dne, aby se bez odbavení nenahrávalo předčasně.
  static DateTime _pickupAt(Reservation r) {
    final d = r.startDate;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(r.pickupTime ?? '');
    // Stará značka 00:01 (= „kdykoliv během prvního dne“, ne plán) → jako bez
    // času; zvolený čas vyzvednutí (i na samoobsluze) se používá.
    final noPlan = isLegacyAllDayPickupTime(r.pickupTime);
    if (m == null || noPlan) return DateTime(d.year, d.month, d.day, 23, 59);
    return DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(reservationsProvider);
    final st = ref.watch(rideRecorderProvider);
    // Dokud rezervace nedorazily, NIC nerozhodujeme — prázdný seznam při
    // načítání by jinak vypadal jako „výpůjčka skončila" a rozjetou jízdu
    // by zbytečně uzavřel (a po dojetí seznamu by vznikla druhá).
    if (!res.hasValue) return const SizedBox.shrink();
    final bookingId = _activeBookingId(res.value ?? const <Reservation>[]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = ref.read(rideRecorderProvider.notifier);
      if (bookingId != null) {
        n.ensureRecording(bookingId);
      } else if (st.manual && st.rideId != null && !st.recording &&
          n.canRetryStop) {
        // Ruční jízdu jezdec ukončil, ale server to nevzal (offline) —
        // dokud ji nikdo neuloží, zkoušíme to dál. Jinak by lokálně visela
        // navždy a jezdec viděl „příliš krátká", i když jel 80 km.
        n.stop();
      } else if (!st.manual &&
          (st.recording || st.rideId != null) &&
          n.canRetryStop) {
        // Výpůjčka skončila (i když appka mezitím neběžela) → jízdu uzavři.
        // `canRetryStop` drží odstup po neúspěchu (offline), ať se to
        // nezkouší při každém překreslení.
        n.stop();
      }
    });

    return const SizedBox.shrink();
  }
}
