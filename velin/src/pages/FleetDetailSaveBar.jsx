import { useEffect, useRef, useState } from 'react'
import Button from '../components/ui/Button'
import { useIsMobile } from '../hooks/useIsMobile'

// Mobil/tablet (< 1024 px): formulář záložky Info je na telefonu ~4500–6700 px dlouhý a „Uložit“
// bylo až úplně dole. Lišta s „Uložit“ se přilepí ke spodku obrazovky (sticky uvnitř karty formuláře —
// jakmile karta odjede nahoru, lišta odjede s ní). Stejná akce i stavy (disabled / „Ukládám…“) jako dřív.
// Chyba uložení se v liště ukáže jen když je přilepená (jinak je plný text hned nad ní);
// klepnutí na ni posune na plný text. Desktop: nic se nevykreslí (tlačítko zůstává v řádku pod formulářem).
export default function MobileSaveBar({ onSave, saving, error }) {
  const isMobile = useIsMobile()
  const sentinel = useRef(null)   // přirozená pozice lišty — když je pod spodkem obrazovky, lišta je přilepená
  const [stuck, setStuck] = useState(false)
  const [padBottom, setPadBottom] = useState(0)

  useEffect(() => {
    const el = sentinel.current
    if (!isMobile || !el) return undefined
    // Sticky se drží nad vnitřním odsazením scroll kontejneru (Layout: paddingBottom 60) → lištu o něj
    // posuneme dolů, ať sedí přesně na spodku obrazovky a obsah pod ní neprosvítá.
    // z-[15]: nad štítky fotek/videí (z-10) a lištou editoru (5), pod šuplíkem menu (40), LOG (45) a modály (50).
    let sc = el.parentElement
    while (sc && !/(auto|scroll)/.test(getComputedStyle(sc).overflowY)) sc = sc.parentElement
    if (sc) setPadBottom(parseFloat(getComputedStyle(sc).paddingBottom) || 0)
    // Přilepená = sentinel je pod spodkem viditelné oblasti. Přepočet při scrollu (1× za snímek) i při
    // změně rozvržení (IntersectionObserver) — samotný IO nezachytí skok přes celou obrazovku (např. z konce
    // stránky zpět do formuláře) a lišta by pak zůstala bez chybové hlášky.
    let raf = 0
    const check = () => {
      raf = 0
      const bottom = Math.min(window.innerHeight, sc ? sc.getBoundingClientRect().bottom : Infinity)
      setStuck(el.getBoundingClientRect().top > bottom)
    }
    const schedule = () => { if (!raf) raf = requestAnimationFrame(check) }
    const target = sc || window
    check()
    target.addEventListener('scroll', schedule, { passive: true })
    window.addEventListener('resize', schedule)
    const io = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(schedule)
    io?.observe(el)
    return () => {
      if (raf) cancelAnimationFrame(raf)
      target.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
      io?.disconnect()
    }
  }, [isMobile])

  if (!isMobile) return null
  return (
    <>
      <div className="sticky z-[15] -mx-5 px-5 py-2 mt-6 bg-white"
        style={{ bottom: -padBottom, borderTop: `1px solid ${stuck ? '#e2ece7' : 'transparent'}`, boxShadow: stuck ? '0 -6px 12px -8px rgba(15,26,20,.3)' : 'none' }}>
        {stuck && error && (
          <button type="button" onClick={() => sentinel.current?.scrollIntoView({ block: 'end', behavior: 'smooth' })}
            className="block w-full mb-1.5 text-left text-xs font-bold cursor-pointer"
            style={{ color: '#dc2626', background: 'none', border: 'none', padding: 0 }}>
            <span className="line-clamp-2">{error}</span>
          </button>
        )}
        <Button green onClick={onSave} disabled={saving} className="justify-center align-top min-h-[44px] min-w-[150px]">{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
      <div ref={sentinel} className="h-px -mt-px" aria-hidden="true" />
    </>
  )
}
