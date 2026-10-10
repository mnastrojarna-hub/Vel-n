// Mobil/tablet (< 1024 px): kalendář a detail dne jsou pod sebou — po klepnutí na den
// posuň detail do zorného pole, jen když je celý pod spodním okrajem obrazovky.
// Desktop (detail vedle kalendáře) se nikdy neposouvá.
export function revealBelowOnMobile(el) {
  if (!el || typeof window === 'undefined' || !window.matchMedia?.('(max-width: 1023px)').matches) return
  requestAnimationFrame(() => {
    const r = el.getBoundingClientRect()
    if (r.top > window.innerHeight - 120) el.scrollIntoView({ behavior: 'smooth', block: 'start' })
  })
}
