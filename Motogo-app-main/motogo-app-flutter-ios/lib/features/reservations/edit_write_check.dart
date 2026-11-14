// Ověření, že přímý zápis úpravy rezervace (`bookings` UPDATE) opravdu
// prošel. Pojistka DB `_guard_customer_booking_pricing` u ZAPLACENÉ
// rezervace tiše ponechá původní termín, motorku a cenu, když by zápis dal
// zákazníkovi víc dní / vyšší ceníkovou hodnotu (např. +1 den a zároveň
// zrušené přistavení = nižší cena). UPDATE pak skončí bez chyby, ale nic se
// nezměnilo. Stejné porovnání slouží po ztracené odpovědi (výpadek sítě).

/// Údaje, které úprava mění a které pojistka hlídá.
const editCheckedKeys = ['start_date', 'end_date', 'moto_id', 'total_price'];

String _d(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

bool _same(String k, Object? a, Object? b) {
  if (k == 'total_price') {
    final x = (a as num?)?.toDouble(), y = (b as num?)?.toDouble();
    if (x == null || y == null) return x == y;
    return (x - y).abs() <= 0.5;
  }
  if (k == 'moto_id') return '${a ?? ''}' == '${b ?? ''}';
  return _d(a) == _d(b);
}

/// [row] = rezervace načtená po zápisu, [changes] = co úprava zapisovala,
/// [original] = stav před úpravou (stejné klíče, viz [editCheckedKeys]).
/// true = rozlišující údaje nesou nové hodnoty (uloženo), false = všechny
/// rozlišující údaje mají pořád PŮVODNÍ hodnoty (neuloženo), null = nejde
/// rozlišit (úprava žádný z nich nemění, nebo je stav smíšený / cizí).
bool? editWriteApplied(Map<String, dynamic> row, Map<String, dynamic> changes, Map<String, dynamic> original) {
  var distinguishing = 0, wanted = 0, orig = 0;
  for (final k in editCheckedKeys) {
    if (!changes.containsKey(k) || _same(k, changes[k], original[k])) continue;
    distinguishing++;
    if (_same(k, row[k], changes[k])) {
      wanted++;
    } else if (_same(k, row[k], original[k])) {
      orig++;
    }
  }
  if (distinguishing == 0) return null;
  if (wanted == distinguishing) return true;
  if (orig == distinguishing) return false;
  return null;
}
