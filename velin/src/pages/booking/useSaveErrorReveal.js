import { useEffect, useRef, useState } from 'react'
import { useIsMobile } from '../../hooks/useIsMobile'

// Telefon/tablet (< 1024 px): dlouhé modaly (Upravit rezervaci, elektronický protokol) mají chybu
// uložení nahoře — na telefonu 1 200–2 800 px nad tlačítkem „Uložit", takže operátor nevidí, proč se
// nic neuložilo. Po každé chybě (i opakované stejné) posuneme scroll modalu k cíli:
//   'actions' → chyba vykreslená nad tlačítky + tlačítka (ref `actionsRef` na řádek tlačítek),
//   'top'     → horní chyba (ref `topRef`) — např. kolonka „Kód k motorce" hned pod ní.
// Desktop (≥ 1024 px) se nemění: `at` se tam ignoruje a chyba zůstává nahoře beze změny.
export function useSaveErrorReveal() {
  const isMobile = useIsMobile()
  const [hit, setHit] = useState(null) // { at: 'actions' | 'top', n } — n vynutí posun i u stejné chyby
  const topRef = useRef(null)
  const actionsRef = useRef(null)

  useEffect(() => {
    if (!isMobile || !hit) return
    if (hit.at === 'top') scrollWithinScroller(topRef.current, 'start')
    else scrollWithinScroller(actionsRef.current, 'nearest')
  }, [hit, isMobile])

  return {
    isMobile,
    // true = chybu kreslit u tlačítek (jen < lg); jinak nahoře jako na desktopu
    nearActions: isMobile && hit?.at === 'actions',
    reveal: (at = 'actions') => setHit(h => ({ at, n: (h?.n || 0) + 1 })),
    clear: () => setHit(null),
    topRef,
    actionsRef,
  }
}

// Posun jen uvnitř nejbližšího scrollujícího předka (modal / jeho obsah) — scrollIntoView by mohl
// posunout i stránku pod modalem (iOS Safari). 'start' = prvek k hornímu okraji, 'nearest' = jen dovidět.
function scrollWithinScroller(el, block) {
  if (!el) return
  let sc = el.parentElement
  while (sc && !(sc.scrollHeight > sc.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(sc).overflowY))) sc = sc.parentElement
  if (!sc) return
  const r = el.getBoundingClientRect()
  const s = sc.getBoundingClientRect()
  const pad = 12
  let d = 0
  if (block === 'start' || r.top < s.top + pad) d = r.top - s.top - pad
  else if (r.bottom > s.bottom - pad) d = r.bottom - s.bottom + pad
  if (Math.abs(d) > 1) sc.scrollBy({ top: d, behavior: 'smooth' })
}
