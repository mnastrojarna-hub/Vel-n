import { useRef, useEffect, useImperativeHandle, forwardRef, useState } from 'react'

// Podpisové pole perem pro tablet — Pointer Events sjednocují pero / dotyk / myš.
// touchAction:'none' brání scrollu při podpisu. Vrací PNG data URL přes ref.
const SignaturePad = forwardRef(function SignaturePad({ height = 170, label }, ref) {
  const canvasRef = useRef(null)
  const drawing = useRef(false)
  const last = useRef({ x: 0, y: 0 })
  const [empty, setEmpty] = useState(true)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ratio = window.devicePixelRatio || 1
    const rect = canvas.getBoundingClientRect()
    canvas.width = Math.max(1, rect.width) * ratio
    canvas.height = Math.max(1, rect.height) * ratio
    const ctx = canvas.getContext('2d')
    ctx.scale(ratio, ratio)
    ctx.lineWidth = 2.2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.strokeStyle = '#0f1a14'
  }, [])

  function pos(e) {
    const rect = canvasRef.current.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  }
  function clear() {
    const c = canvasRef.current
    if (!c) return
    c.getContext('2d').clearRect(0, 0, c.width, c.height)
    setEmpty(true)
  }

  const start = (e) => { e.preventDefault(); drawing.current = true; last.current = pos(e); try { canvasRef.current.setPointerCapture(e.pointerId) } catch {} }
  const move = (e) => {
    if (!drawing.current) return
    e.preventDefault()
    const ctx = canvasRef.current.getContext('2d')
    const p = pos(e)
    ctx.beginPath(); ctx.moveTo(last.current.x, last.current.y); ctx.lineTo(p.x, p.y); ctx.stroke()
    last.current = p
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
        <button type="button" onClick={clear} style={{ fontSize: 11, color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer', marginLeft: 'auto' }}>Smazat podpis</button>
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
