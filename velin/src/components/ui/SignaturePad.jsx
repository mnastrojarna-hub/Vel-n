import { useRef, useEffect, useImperativeHandle, forwardRef, useState } from 'react'

// Podpisové pole perem pro tablet — Pointer Events sjednocují pero / dotyk / myš.
// touchAction:'none' brání scrollu při podpisu. Vrací PNG data URL přes ref.
const SignaturePad = forwardRef(function SignaturePad({ height = 170, label }, ref) {
  const canvasRef = useRef(null)
  const drawing = useRef(false)
  const last = useRef({ x: 0, y: 0 })
  const [empty, setEmpty] = useState(true)

  // Tahy podpisu se ukládají (v souřadnicích plátna při prvním tahu), takže když se plátno změní
  // (otočení telefonu/tabletu, zalomení modálu, zoom), podpis se překreslí CELÝ, úměrně zmenšený
  // či zvětšený — dřív se bitmapa jen zkopírovala a při zúžení se pravá část podpisu ořízla.
  const strokes = useRef([])
  const base = useRef(null)            // { w, h } plátna při prvním tahu
  const size = useRef({ w: 0, h: 0 })  // aktuální CSS rozměr plátna
  const scale = () => (base.current ? Math.min(size.current.w / base.current.w, size.current.h / base.current.h) : 1)

  function redraw() {
    const c = canvasRef.current
    if (!c) return
    const ctx = c.getContext('2d')
    ctx.clearRect(0, 0, size.current.w, size.current.h)
    const k = scale()
    for (const st of strokes.current) {
      if (st.length < 2) continue
      ctx.beginPath(); ctx.moveTo(st[0].x * k, st[0].y * k)
      for (let i = 1; i < st.length; i++) ctx.lineTo(st[i].x * k, st[i].y * k)
      ctx.stroke()
    }
  }

  // Velikost plátna dle skutečné velikosti prvku; při změně se přepočítá a podpis překreslí.
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const setup = (keep) => {
      const ratio = window.devicePixelRatio || 1
      const rect = canvas.getBoundingClientRect()
      const w = Math.max(1, rect.width) * ratio
      const h = Math.max(1, rect.height) * ratio
      if (keep && canvas.width === Math.floor(w) && canvas.height === Math.floor(h)) return
      canvas.width = w
      canvas.height = h
      size.current = { w: Math.max(1, rect.width), h: Math.max(1, rect.height) }
      const ctx = canvas.getContext('2d')
      ctx.scale(ratio, ratio)
      ctx.lineWidth = 2.2
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.strokeStyle = '#0f1a14'
      if (keep) redraw()
    }
    setup(false)
    if (typeof ResizeObserver === 'undefined') return undefined
    const ro = new ResizeObserver(() => setup(true))
    ro.observe(canvas)
    return () => ro.disconnect()
  }, [])

  function pos(e) {
    const rect = canvasRef.current.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  }
  function clear() {
    const c = canvasRef.current
    if (!c) return
    c.getContext('2d').clearRect(0, 0, c.width, c.height)
    strokes.current = []
    base.current = null
    setEmpty(true)
  }

  const start = (e) => {
    e.preventDefault(); drawing.current = true; last.current = pos(e)
    if (!base.current) base.current = { ...size.current }
    const k = scale()
    strokes.current.push([{ x: last.current.x / k, y: last.current.y / k }])
    try { canvasRef.current.setPointerCapture(e.pointerId) } catch {}
  }
  const move = (e) => {
    if (!drawing.current) return
    e.preventDefault()
    const ctx = canvasRef.current.getContext('2d')
    const p = pos(e)
    ctx.beginPath(); ctx.moveTo(last.current.x, last.current.y); ctx.lineTo(p.x, p.y); ctx.stroke()
    last.current = p
    const k = scale()
    strokes.current[strokes.current.length - 1]?.push({ x: p.x / k, y: p.y / k })
    if (empty) setEmpty(false)
  }
  const end = () => { drawing.current = false }

  useImperativeHandle(ref, () => ({
    isEmpty: () => empty,
    clear,
    toDataURL: () => (empty ? null : canvasRef.current.toDataURL('image/png')),
  }))

  return (
    <div>
      <div className="flex items-center justify-between mb-1">
        {label && <span style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22' }}>{label}</span>}
        <button type="button" onClick={clear} className="max-lg:min-h-[36px] max-lg:px-2 max-lg:!text-[13px]" style={{ fontSize: 11, color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer', marginLeft: 'auto' }}>Smazat podpis</button>
      </div>
      <canvas
        ref={canvasRef}
        style={{ width: '100%', height, border: '1px dashed #b6dccb', borderRadius: 10, background: '#fbfdfc', touchAction: 'none', cursor: 'crosshair', display: 'block' }}
        onPointerDown={start}
        onPointerMove={move}
        onPointerUp={end}
        onPointerLeave={end}
        onPointerCancel={end}
      />
    </div>
  )
})

export default SignaturePad
