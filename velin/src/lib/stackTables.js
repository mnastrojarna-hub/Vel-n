// Kartové zobrazení tabulek na telefonu: každé buňce <td> v table.mg-stack doplní
// data-label = text záhlaví sloupce (CSS v index.css ho vypíše jako popisek karty).
// Běží jen na šířce ≤ 1023 px (desktop se nijak nedotkne); buňky s vlastním
// data-label (TD label=…) se nepřepisují. Řaditelné záhlaví (cursor: pointer)
// a záhlaví se zaškrtávátkem dostanou třídu mg-sort → na telefonu zůstanou
// vidět jako „čipy“, takže řazení i „vybrat vše“ dál fungují.

const QUERY = '(max-width: 1023px)'
const ARROWS = /[▲▼↑↓⇅]/g

function headerLabels(table) {
  const head = table.tHead?.rows[0] || [...table.rows].find(r => r.cells[0]?.tagName === 'TH')
  if (!head) return []
  const labels = []
  for (const th of head.cells) {
    const text = (th.innerText || th.textContent || '').replace(ARROWS, '').replace(/\s+/g, ' ').trim()
    if (th.tagName === 'TH' && !th.classList.contains('mg-sort') && (th.querySelector('input[type="checkbox"]') || getComputedStyle(th).cursor === 'pointer')) th.classList.add('mg-sort')
    for (let i = 0; i < (th.colSpan || 1); i++) labels.push(text)
  }
  return labels
}

function labelTable(table) {
  const labels = headerLabels(table)
  if (!labels.length) return
  for (const body of table.tBodies) {
    for (const row of body.rows) {
      let col = 0
      for (const cell of row.cells) {
        if (cell.tagName === 'TD') {
          if (cell.colSpan > 1 && !cell.classList.contains('mg-stack-full')) cell.classList.add('mg-stack-full')
          const label = cell.colSpan > 1 ? '' : (labels[col] || '')
          if (!cell.hasAttribute('data-label') || cell.dataset.mgAuto === '1') {
            if (cell.getAttribute('data-label') !== label) cell.setAttribute('data-label', label)
            cell.dataset.mgAuto = '1'
          }
        }
        col += cell.colSpan || 1
      }
    }
  }
}

export function installStackTables() {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function' || typeof MutationObserver === 'undefined') return
  const mql = window.matchMedia(QUERY)
  let raf = 0
  const run = () => { raf = 0; document.querySelectorAll('table.mg-stack').forEach(labelTable) }
  const schedule = () => { if (!raf) raf = requestAnimationFrame(run) }
  const observer = new MutationObserver(schedule)
  const sync = () => {
    observer.disconnect()
    if (!mql.matches) return
    observer.observe(document.body, { childList: true, subtree: true })
    schedule()
  }
  if (mql.addEventListener) mql.addEventListener('change', sync)
  else mql.addListener(sync)
  sync()
}
