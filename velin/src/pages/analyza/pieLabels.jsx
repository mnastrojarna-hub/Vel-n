import { Curve } from 'recharts'

// Popisky hodnot koláčů Analýzy (AI traffic „Rozpad podle zdroje“, Návštěvnost „Zdroj návštěv“
// a „Zařízení“) bez vzájemného překryvu. Recharts kreslí popisek každé výseče zvlášť, takže
// u malých sousedních výsečí (např. 100 a 400 vedle sebe) se čísla přepíšou přes sebe.
// Pozice všech popisků se dopočítají z dat stejně jako v Recharts (0° vpravo, proti směru
// hodinek, popisek 20 px vně výseče, svisle na střed); od největší výseče se popisek, který
// by překryl už umístěný, vynechá i s čarou — hodnota zůstává v tooltipu a legendě barvou.
// Nepřekrývající se popisky se vykreslí přesně jako výchozí (`label` vrací jen hodnotu).
const OFFSET = 20 // výchozí offsetRadius Recharts
const FONT = 16 // popisky dědí písmo stránky
const CHAR_W = 0.68 * FONT // číslice Montserrat ~0,65 em (+ rezerva)
const LINE_H = 1.25 * FONT // výška rámečku textu
const RAD = Math.PI / 180

function visibleIdx(data, cx, cy, r) {
  const vals = data.map(d => { const v = Number(d.value); return Number.isFinite(v) ? v : 0 })
  const sum = vals.reduce((s, v) => s + v, 0)
  if (!(sum > 0)) return new Set()
  let start = 0
  const boxes = vals.map((v, i) => {
    const mid = start + (v / sum) * 180
    start += (v / sum) * 360
    const x = cx + Math.cos(-mid * RAD) * (r + OFFSET), y = cy + Math.sin(-mid * RAD) * (r + OFFSET)
    const w = String(data[i].value).length * CHAR_W
    const l = x > cx ? x : x < cx ? x - w : x - w / 2
    return { i, v, l, r: l + w, t: y - LINE_H / 2, b: y + LINE_H / 2 }
  })
  const shown = []
  for (const b of [...boxes].sort((a, c) => c.v - a.v || a.i - c.i)) {
    if (!shown.some(s => b.l < s.r && s.l < b.r && b.t < s.b && s.t < b.b)) shown.push(b)
  }
  return new Set(shown.map(b => b.i))
}

// Použití: <Pie data={d} dataKey="value" … {...pieLabels(d)}> (místo holého `label`)
export function pieLabels(data) {
  const show = p => visibleIdx(data, p.cx, p.cy, p.outerRadius).has(p.index)
  return {
    label: p => (show(p) ? p.value : <g />),
    labelLine: ({ key, ...p }) => (show(p) ? <Curve {...p} type="linear" className="recharts-pie-label-line" /> : null), // eslint-disable-line no-unused-vars
  }
}
