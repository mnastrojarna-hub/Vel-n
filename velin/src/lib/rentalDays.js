/**
 * MotoGo24 Velín — jednotný výpočet délky pronájmu.
 *
 * JEDINÁ kanonická definice „kolik dní pronájmu" napříč celým Velínem
 * (Rezervace, Zákazníci, Analýza, kalkulace ceny). Dříve existovaly tři
 * nekonzistentní vzorce (round+1 / ceil bez +1 / round bez +1), takže stejná
 * rezervace ukazovala jinak v Rezervacích, u Zákazníků i v Analýze.
 *
 * Definice = INKLUZIVNÍ kalendářní dny (počítá první i poslední den), tj. `+1`.
 * Shoduje se s ceníkem/fakturací: `calcDayBreakdown` generuje řádky
 * `while (cur <= endD)` (inkluzivně) a podle toho se účtuje cena —
 * den počítání musí sedět s tím, za co zákazník platí.
 *
 * Příklad: 20. 6. → 27. 6. = 8 dní (kalendářní dny vč. obou krajních).
 */

// Normalizace na lokální půlnoc — eliminuje vliv času i přechodu na letní čas
// (počítáme rozdíl celých kalendářních dnů, ne hodin).
function _midnight(d) {
  if (!d) return null
  const dt = new Date(typeof d === 'string' ? (d.length <= 10 ? d + 'T00:00:00' : d) : d)
  if (isNaN(dt)) return null
  dt.setHours(0, 0, 0, 0)
  return dt
}

/**
 * Vrátí počet dní pronájmu mezi start a end (inkluzivně, min. 1).
 * Přijímá Date i ISO string ('YYYY-MM-DD' i plný timestamp).
 * Při nevalidních vstupech vrací 0 (volající si ošetří fallback '—').
 */
export function rentalDays(start, end) {
  const s = _midnight(start)
  const e = _midnight(end)
  if (!s || !e) return 0
  return Math.max(1, Math.round((e - s) / 86400000) + 1)
}

export default rentalDays
