import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'ride_provider.dart';

/// Automatický záznam jízdy během výpůjčky („Moje jízdy").
///
/// Nahrává se POUZE když jsou splněné VŠECHNY podmínky:
///   1. zákazník je přihlášený a má právě běžící rezervaci (aktivní výpůjčku),
///   2. má POVOLENOU POLOHU (oprávnění už udělené — appka si o ně kvůli
///      záznamu sama NEŘÍKÁ) a zapnuté polohové služby,
///   3. záznam si v „Mých zážitcích" nevypnul přepínačem.
/// Body se hromadí lokálně a po dávkách se posílají do `user_rides`. Rozjetý
/// záznam přežije zavření appky (id + nedoručená dávka v SharedPreferences).
/// Jízda končí spolu s výpůjčkou (nebo ručně) a kratší než 1 km se zahodí.

const String kRideAutoRecordKey = 'mg_ride_autorecord'; // přepínač jezdce
const String kRideRecIdKey = 'mg_ride_rec_id'; // id rozjeté nahrávky
const String kRideRecBufKey = 'mg_ride_rec_buf'; // neodeslané GPS body

const int _kFlushPoints = 20; // dávka bodů
const Duration _kFlushEvery = Duration(seconds: 90);
const int _kDistanceFilterM = 20; // hustota stopy

class RideRecorderState {
  final bool enabled; // přepínač „zaznamenávat jízdy"
  final bool recording;
  final String? rideId;
  final String? bookingId;
  final int points; // body poslané + čekající v dávce

  const RideRecorderState({
    this.enabled = true,
    this.recording = false,
    this.rideId,
    this.bookingId,
    this.points = 0,
  });

  RideRecorderState copyWith({
    bool? enabled,
    bool? recording,
    String? rideId,
    String? bookingId,
    int? points,
    bool clearRide = false,
  }) =>
      RideRecorderState(
        enabled: enabled ?? this.enabled,
        recording: recording ?? this.recording,
        rideId: clearRide ? null : (rideId ?? this.rideId),
        bookingId: clearRide ? null : (bookingId ?? this.bookingId),
        points: points ?? this.points,
      );
}

class RideRecorderNotifier extends StateNotifier<RideRecorderState> {
  RideRecorderNotifier(this._ref) : super(const RideRecorderState()) {
    _restore();
  }

  final Ref _ref;
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  final List<List<double>> _buffer = [];
  double _maxSpeedKmh = 0;
  bool _starting = false;

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final enabled = p.getBool(kRideAutoRecordKey) ?? true;
      final id = p.getString(kRideRecIdKey);
      final raw = p.getString(kRideRecBufKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is List && e.length >= 2) {
              _buffer.add([
                for (final v in e)
                  if (v is num) v.toDouble(),
              ]);
            }
          }
        }
      }
      state = state.copyWith(enabled: enabled, rideId: id);
    } catch (_) {/* poškozený cache → začneme načisto */}
  }

  /// Přepínač v „Mých zážitcích". Vypnutí rozjetou jízdu rovnou ukončí.
  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kRideAutoRecordKey, value);
    } catch (_) {}
    if (!value) await stop();
  }

  /// Má zákazník polohu povolenou? (NEŽÁDÁ o ni — jen se ptá systému.)
  static Future<bool> hasLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Spustí (nebo po restartu appky obnoví) záznam pro běžící výpůjčku.
  Future<void> ensureRecording(String? bookingId) async {
    if (!state.enabled || state.recording || _starting) return;
    if (MotoGoSupabase.currentUser == null) return;
    if (!await hasLocationPermission()) return;

    _starting = true;
    try {
      Position? first;
      try {
        first = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      final id = await startUserRide(
        bookingId: bookingId,
        lat: first?.latitude,
        lng: first?.longitude,
      );
      if (id == null) return;

      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(kRideRecIdKey, id);
      } catch (_) {}

      _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _kDistanceFilterM,
        ),
      ).listen(_onPosition, onError: (_) {});
      _timer?.cancel();
      _timer = Timer.periodic(_kFlushEvery, (_) => flush());

      state = state.copyWith(recording: true, rideId: id, bookingId: bookingId);
    } finally {
      _starting = false;
    }
  }

  /// Bod stopy = `[lat, lng, čas (epoch s), rychlost km/h, výška m]`.
  /// Čas a rychlost potřebuje server na statistiky (čas jízdy vs. čas stání,
  /// průměrná rychlost, nastoupáno). Výška se posílá jen když ji GPS zná —
  /// nula = přijímač výšku nemá a falešně by nafoukla stoupání.
  void _onPosition(Position pos) {
    if (!state.recording) return;
    var kmh = pos.speed * 3.6;
    if (!kmh.isFinite || kmh < 0 || kmh > 300) kmh = 0;
    final alt = pos.altitude;
    final point = <double>[
      double.parse(pos.latitude.toStringAsFixed(5)),
      double.parse(pos.longitude.toStringAsFixed(5)),
      (DateTime.now().millisecondsSinceEpoch / 1000).roundToDouble(),
      double.parse(kmh.toStringAsFixed(1)),
      if (alt.isFinite && alt != 0) double.parse(alt.toStringAsFixed(1)),
    ];
    _buffer.add(point);
    if (kmh > _maxSpeedKmh) _maxSpeedKmh = kmh;
    state = state.copyWith(points: state.points + 1);
    _persistBuffer();
    if (_buffer.length >= _kFlushPoints) flush();
  }

  Future<void> _persistBuffer() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideRecBufKey, jsonEncode(_buffer));
    } catch (_) {}
  }

  /// Odešle nasbíranou dávku bodů (volá se po dávkách, časovačem a při
  /// přechodu appky do pozadí).
  Future<void> flush() async {
    final id = state.rideId;
    if (id == null || _buffer.isEmpty) return;
    final batch = List<List<double>>.from(_buffer);
    final ok = await appendRideTrack(id, batch,
        maxSpeedKmh: _maxSpeedKmh > 0 ? _maxSpeedKmh : null);
    if (!ok) return; // neposlané body zůstanou v dávce na příště
    _buffer.removeRange(0, batch.length);
    await _persistBuffer();
  }

  /// Ukončí jízdu — zbytek dávky se pošle s ukončením, krátkou jízdu server
  /// zahodí. Vrací true, když jízda zůstala uložená.
  Future<bool> stop() async {
    final id = state.rideId;
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(recording: false, points: 0, clearRide: true);

    var kept = false;
    if (id != null) {
      final res = await finishUserRide(id, points: List<List<double>>.from(_buffer));
      kept = res != null && !res.discarded;
    }
    _buffer.clear();
    _maxSpeedKmh = 0;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kRideRecIdKey);
      await p.remove(kRideRecBufKey);
    } catch (_) {}
    _ref.invalidate(myRidesProvider);
    return kept;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final rideRecorderProvider =
    StateNotifierProvider<RideRecorderNotifier, RideRecorderState>(
        (ref) => RideRecorderNotifier(ref));

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
    // Do pozadí → nasbírané body rovnou odešleme (OS může stream uspat).
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      ref.read(rideRecorderProvider.notifier).flush();
    }
  }

  /// Právě běžící (aktivní) rezervace zákazníka, jinak null.
  String? _activeBookingId(List<Reservation> list) {
    for (final r in list) {
      if (r.displayStatus == ResStatus.aktivni) return r.id;
    }
    return null;
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
      } else if (st.recording || st.rideId != null) {
        // Výpůjčka skončila (i když appka mezitím neběžela) → jízdu uzavři.
        n.stop();
      }
    });

    return const SizedBox.shrink();
  }
}
