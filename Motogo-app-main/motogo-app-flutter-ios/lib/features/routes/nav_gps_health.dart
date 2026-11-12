// Slabý GPS signál v navigaci. GPS stream navigace má distanceFilter 4 m,
// takže STOJÍCÍ telefon (semafor, tankování, focení) fixy neposílá — stáří
// fixu samo o sobě slabý signál neznamená. Varování jen když fix chybí déle
// než 20 s a jezdec se při posledním fixu pohyboval (> 5 km/h, stejný práh
// jako „v pohybu“ navigace).

const navGpsWeakAfter = Duration(seconds: 20);
const navGpsMovingKmh = 5.0;

/// [sinceFix] = stáří posledního fixu (null = ještě žádný fix),
/// [lastSpeedKmh] = rychlost z posledního fixu.
bool navGpsWeak({required Duration? sinceFix, required double lastSpeedKmh}) =>
    sinceFix != null && sinceFix > navGpsWeakAfter && lastSpeedKmh > navGpsMovingKmh;
