import { useEffect, useRef, useState } from 'react'

// Sdílené klikací řazení tabulek v Analýze. Sloupec: { label, key, str?, value? }
// — str = textové řazení (česká abeceda, 1. klik A→Z), jinak číselné (1. klik sestupně);
// value(row) = getter, když hodnota není přímo row[key]. Sloupec bez key se neřadí.
// Prázdné hodnoty (null/undefined/NaN) jsou vždy na konci bez ohledu na směr.

export function useTableSort(columns, initial = null) {
  const [sort, setSort] = useState(initial)
  const toggle = key => {
    const c = columns.find(x => x.key === key)
    setSort(s => (s?.key === key ? { key, dir: s.dir === 'desc' ? 'asc' : 'desc' } : { key, dir: c?.str ? 'asc' : 'desc' }))
  }
  return { sort, toggle }
}

export function sortRows(rows, columns, sort) {
  if (!sort?.key) return rows
  const c = columns.find(x => x.key === sort.key) || {}
  const dir = sort.dir === 'asc' ? 1 : -1
  const val = c.value || (r => r[sort.key])
  return [...rows].sort((a, b) => {
    const av = val(a), bv = val(b)
    if (c.str) return dir * String(av ?? '').localeCompare(String(bv ?? ''), 'cs')
    const an = av == null || Number.isNaN(Number(av)) ? null : Number(av)
    const bn = bv == null || Number.isNaN(Number(bv)) ? null : Number(bv)
    if (an == null && bn == null) return 0
    if (an == null) return 1
    if (bn == null) return -1
    return dir * (an - bn)
  })
}

// Mobil/tablet (desktop ≥ 1024 px beze změny). Telefon: tabulka s třídou mg-stack = řádky
// jako karty; STACK_WRAP na obalu zprůhlední bílou kartu a zruší padding (karty jsou řádky).
export const STACK_WRAP = 'mg-stack-wrap p-0 md:p-4'
// Tablet (768–1023 px): široká tabulka se posouvá do strany ve vlastním obalu TAB_SCROLL
// (nadpis karty zůstává na místě) a první sloupec (název) zůstává přilepený vlevo —
// TAB_STICKY na první <td> + SortableHeaderRow stickyFirst. Na desktopu je obal neutrální div.
// Buňky se na tabletu nezalamují (řádky zůstanou jednořádkové, posouvá se do strany).
export const TAB_SCROLL = 'md:max-lg:overflow-x-auto md:max-lg:[&_td]:whitespace-nowrap'
export const TAB_STICKY = 'md:max-lg:sticky md:max-lg:left-0 md:max-lg:bg-white md:max-lg:min-w-[9rem] md:max-lg:shadow-[4px_0_6px_-4px_rgba(0,0,0,.15)]'
// Pruhované tabulky (lichý řádek #f9fdfb): přilepená buňka musí nést barvu svého řádku,
// jinak na tabletu svítí bílá přes pruh. Na desktopu stejná barva jako řádek = beze změny.
export const stickyStripe = i => (i % 2 === 1 ? { background: '#f9fdfb' } : undefined)

// Obal široké tabulky (výchozí TAB_SCROLL): dokud je vpravo další obsah, pravý okraj se
// zprůhlední (maska) — na tabletu je tak vidět, že tabulka pokračuje a dá se posunout.
// Třídy masky platí jen pod 1024 px (tab = 768–1023, all = < 1024), desktop beze změny.
const FADE = {
  tab: 'md:max-lg:[mask-image:linear-gradient(to_right,#000_calc(100%_-_48px),transparent)] md:max-lg:[-webkit-mask-image:linear-gradient(to_right,#000_calc(100%_-_48px),transparent)]',
  all: 'max-lg:[mask-image:linear-gradient(to_right,#000_calc(100%_-_48px),transparent)] max-lg:[-webkit-mask-image:linear-gradient(to_right,#000_calc(100%_-_48px),transparent)]',
}
export function TabScroll({ children, className = TAB_SCROLL, fade = 'tab' }) {
  const ref = useRef(null)
  const [more, setMore] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return undefined
    const upd = () => setMore(el.scrollWidth - el.clientWidth - el.scrollLeft > 4)
    upd()
    el.addEventListener('scroll', upd, { passive: true })
    const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(upd) : null
    if (ro) { ro.observe(el); if (el.firstElementChild) ro.observe(el.firstElementChild) }
    return () => { el.removeEventListener('scroll', upd); ro?.disconnect() }
  }, [])
  return <div ref={ref} className={more ? `${className} ${FADE[fade]}` : className}>{children}</div>
}

// Mobil/tablet (< 1024 px): záhlaví se smí zalomit (užší sloupce → tabulka se vejde),
// v kartovém režimu (mg-stack) z řaditelných th zůstanou „čipy“. Desktop beze změny.
export function SortableHeaderRow({ columns, sort, toggle, thStyle = { color: '#1a2e22' }, stickyFirst = false }) {
  return (
    <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
      {columns.map((c, i) => c.key ? (
        <th key={c.key} className={`text-left font-bold py-2 px-3 lg:whitespace-nowrap${stickyFirst && i === 0 ? ` ${TAB_STICKY}` : ''}`} title={c.title || 'Seřadit dle sloupce'}
            style={{ ...thStyle, cursor: 'pointer', userSelect: 'none' }}
            onClick={() => toggle(c.key)}>
          {c.label}{sort?.key === c.key ? (sort.dir === 'desc' ? ' ▼' : ' ▲') : ''}
        </th>
      ) : (
        <th key={c.label} className="text-left font-bold py-2 px-3" style={thStyle} title={c.title}>{c.label}</th>
      ))}
    </tr>
  )
}
