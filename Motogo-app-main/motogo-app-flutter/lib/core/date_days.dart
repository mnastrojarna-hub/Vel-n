/// Kalendářní počítání dní — odolné vůči přechodu letního/zimního času.
///
/// POZOR: `DateTime.add(Duration(days: 1))` přičte 24 hodin ABSOLUTNÍHO času,
/// ne kalendářní den. Nad lokálními daty se to o víkendu změny času rozbije:
///   • poslední neděle v říjnu má 25 h → +24 h zůstane v TÉMŽE dni
///     (den se naúčtuje dvakrát a jiný vypadne),
///   • poslední neděle v březnu má 23 h → jeden den se přeskočí.
/// Stejně tak `end.difference(start).inDays` počítá absolutní hodiny, takže
/// přes přechod času vyjde o den míň.
///
/// Server (`calc_booking_price_v2`) počítá nad SQL typem DATE, kde posun času
/// neexistuje — tyhle funkce drží appku s ním v souladu.
library;

/// Počet kalendářních dní včetně obou krajních dat (1. 5. – 1. 5. = 1 den).
int calendarDaysInclusive(DateTime start, DateTime end) =>
    DateTime.utc(end.year, end.month, end.day)
        .difference(DateTime.utc(start.year, start.month, start.day))
        .inDays +
    1;

/// Následující kalendářní den v lokální půlnoci.
/// Dart si přetečení dne v měsíci normalizuje sám (31. 12. + 1 → 1. 1.).
DateTime nextCalendarDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
