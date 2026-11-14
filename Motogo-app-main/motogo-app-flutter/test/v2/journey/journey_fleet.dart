// Journey rig — the 12-bike fleet of the 5.0.1 states (README "Fleet").
// Real models of the MotoGo24 fleet on the two real branches (ids, names,
// cities and modes as in the live `branches` table): MotoGo24 Mezná
// (staffed) and MotoGo24 Velké Němčice (self-service). Photos are
// `shotUrl('moto', n)` (real photos with MG_SHOT_IMG_DIR, see
// test/v2/support/shot_images.dart); prices are plausible day prices.
import 'package:motogo_app/features/catalog/moto_model.dart';

import '../support/shot_images.dart' show shotUrl;

const kBranchMeznaId = '11111111-1111-1111-1111-111111111111';
const kBranchVnId = '22222222-2222-2222-2222-222222222222';

DayPrices _p(int wd, int fri, int sat, int sun) =>
    DayPrices(mon: wd * 1.0, tue: wd * 1.0, wed: wd * 1.0, thu: wd * 1.0, fri: fri * 1.0, sat: sat * 1.0, sun: sun * 1.0);

String _video(String id, int n) => 'https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public/media/shot/video/$id-$n.mp4';

Motorcycle _bike(String id, String model, int photo,
    {required bool vn,
    required String cat,
    required List<String> lic,
    required int kw,
    required DayPrices prices,
    int? seat,
    int? kg,
    int? cc,
    required bool today,
    List<int> morePhotos = const [],
    int videos = 0}) {
  final imgs = [shotUrl('moto', photo), for (final n in morePhotos) shotUrl('moto', n)];
  return Motorcycle(
    id: id,
    model: model,
    category: cat,
    licenseGroups: lic,
    licenseRequired: lic.first,
    powerKw: kw,
    powerHp: (kw * 1.36).round(),
    engineCc: cc,
    seatHeightMm: seat,
    weightKg: kg,
    transmission: '6 st.',
    hasAbs: true,
    imageUrl: imgs.first,
    images: imgs,
    videos: [for (var i = 1; i <= videos; i++) _video(id, i)],
    status: 'active',
    branchId: vn ? kBranchVnId : kBranchMeznaId,
    branchName: vn ? 'MotoGo24 Velké Němčice' : 'MotoGo24 Mezná',
    branchCity: vn ? 'Brno - Velké Němčice' : 'Pelhřimov',
    branchType: vn ? 'samoobslužná' : 'obslužná',
    branchIsOpen: true,
    prices: prices,
    availableToday: today,
  );
}

/// 12 bikes, licence A / A2 / A1. Media: BMW 3 photos + 2 videos,
/// Husqvarna 1 photo + 1 video, Z 900 and Africa Twin 1 video each,
/// Shotgun photos and no video. `availableToday` (a column the server
/// fills) = not in [busyToday], so it matches the fake backend's
/// bookings / closures of the state.
List<Motorcycle> journeyFleet({Set<String> busyToday = const {}}) => [
  _bike('f-bmw', 'BMW R 1200 GS Adventure', 1,
      today: !busyToday.contains('f-bmw'), vn: false, cat: 'cestovni', lic: const ['A'], kw: 92, cc: 1170, seat: 850, kg: 268,
      morePhotos: const [13, 14], videos: 2, prices: _p(3514, 3514, 4882, 3865)),
  _bike('f-husq', 'Husqvarna 701 SM', 2,
      today: !busyToday.contains('f-husq'), vn: true, cat: 'supermoto', lic: const ['A2', 'A'], kw: 55, cc: 693, seat: 890, kg: 147,
      videos: 1, prices: _p(3543, 3600, 4100, 3900)),
  _bike('f-shot', 'Royal Enfield Shotgun 650', 3,
      today: !busyToday.contains('f-shot'), vn: false, cat: 'chopper', lic: const ['A2'], kw: 35, cc: 648, seat: 795, kg: 240, prices: _p(1833, 1990, 2190, 2190)),
  _bike('f-z900', 'Kawasaki Z 900', 4,
      today: !busyToday.contains('f-z900'), vn: true, cat: 'naked', lic: const ['A'], kw: 92, cc: 948, seat: 820, kg: 212,
      videos: 1, prices: _p(2690, 2890, 3290, 3090)),
  _bike('f-mt09', 'Yamaha MT-09 Street Rally', 5,
      today: !busyToday.contains('f-mt09'), vn: false, cat: 'naked', lic: const ['A'], kw: 85, cc: 890, seat: 825, kg: 193, prices: _p(2790, 2990, 3390, 3190)),
  _bike('f-africa', 'Honda CRF 1000 Africa Twin', 6,
      today: !busyToday.contains('f-africa'), vn: true, cat: 'cestovni', lic: const ['A'], kw: 70, cc: 998, seat: 850, kg: 232, videos: 1,
      prices: _p(2990, 3190, 3590, 3390)),
  _bike('f-trk502', 'Benelli TRK 502 X', 7,
      today: !busyToday.contains('f-trk502'), vn: true, cat: 'cestovni', lic: const ['A2'], kw: 35, cc: 500, seat: 800, kg: 213,
      prices: _p(1690, 1890, 2190, 1990)),
  _bike('f-vstrom', 'Suzuki DL 650 V-strom', 8,
      today: !busyToday.contains('f-vstrom'), vn: true, cat: 'cestovni', lic: const ['A'], kw: 52, cc: 645, seat: 835, kg: 216, prices: _p(1990, 2190, 2490, 2290)),
  _bike('f-tiger', 'Triumph Tiger 1200 Explorer', 9,
      today: !busyToday.contains('f-tiger'), vn: false, cat: 'cestovni', lic: const ['A'], kw: 100, cc: 1215, seat: 850, kg: 259, prices: _p(3290, 3490, 3990, 3790)),
  _bike('f-jawa', 'Jawa RVM 500 Adventure', 10,
      today: !busyToday.contains('f-jawa'), vn: true, cat: 'cestovni', lic: const ['A2'], kw: 32, cc: 471, seat: 820, kg: 198, prices: _p(1490, 1690, 1990, 1790)),
  _bike('f-vtx', 'Honda VTX 1800', 11,
      today: !busyToday.contains('f-vtx'), vn: false, cat: 'chopper', lic: const ['A'], kw: 71, cc: 1795, seat: 695, kg: 340, prices: _p(2490, 2690, 2990, 2790)),
  _bike('f-sr125', 'Aprilia SR GT 125', 12,
      today: !busyToday.contains('f-sr125'), vn: true, cat: 'scootery', lic: const ['A1'], kw: 11, cc: 125, seat: 799, kg: 148, prices: _p(890, 990, 1190, 1090)),
];

/// Ids of the fleet (for bookings in the states).
const kFleetIds = ['f-bmw', 'f-husq', 'f-shot', 'f-z900', 'f-mt09', 'f-africa', 'f-trk502', 'f-vstrom', 'f-tiger', 'f-jawa', 'f-vtx', 'f-sr125'];
