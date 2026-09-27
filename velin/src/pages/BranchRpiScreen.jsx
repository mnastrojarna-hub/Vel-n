import { useState, useEffect, useRef, useCallback } from 'react'
import { createPortal } from 'react-dom'
import { Btn } from './BranchRpiUi'
import { startSession, keepalive, setControl, endSession, fetchFrame, subscribeFrames, pointInImage, fmtMb, KEEPALIVE_MS, SESSION_TTL_S } from './screenMirrorHelpers'

// Tlačítko „Obrazovka“ na kartě jednotky + overlay přes celou obrazovku (CONTRACT §29). Zrcadlí displej kiosku
// (JPEG snímky z jednotky, jen při změně, ≤ 1 fps); s přepínačem „Ovládat“ klepnutí do obrazu = dotyk na kiosku.
export function ScreenMirrorButton({ dev, online, onCommand }) {
  const [open, setOpen] = useState(false)
  return (
    <>
      <Btn tone="blue" disabled={!online}
        title={online
          ? 'Ukáže živě obrazovku displeje pobočky (jen když je panel otevřený; snímky jen při změně obrazu, ~50 kB, nejvýš 1/s, max 10 min). S přepínačem „Ovládat“ klepnutí do obrazu = dotyk na kiosku. Zákazník na displeji nic nepozná.'
          : 'Jednotka je offline — obrazovku nelze zrcadlit.'}
        onClick={() => setOpen(true)}>🖥 Obrazovka</Btn>
      {open && <ScreenMirrorOverlay dev={dev} onCommand={onCommand} onClose={() => setOpen(false)} />}
    </>
  )
}

function ScreenMirrorOverlay({ dev, onCommand, onClose }) {
  const [sessionId, setSessionId] = useState(null)
  const [src, setSrc] = useState(null)
  const [frameInfo, setFrameInfo] = useState({ seq: -1, capturedAt: null, meta: {} })
  const [control, setCtrl] = useState(false)
  const [stats, setStats] = useState({ frames: 0, bytes: 0 })
  const [error, setError] = useState(null)
  const [startedAt] = useState(Date.now())
  const [now, setNow] = useState(Date.now())
  const [dialogText, setDialogText] = useState('')
  const [tapMark, setTapMark] = useState(null)
  const imgRef = useRef(null)
  const seqRef = useRef(-1)
  const sidRef = useRef(null)

  const pull = useCallback(async () => {
    if (!sidRef.current) return
    const row = await fetchFrame(dev.id, seqRef.current)
    if (!row) return
    if (row.session_id && row.session_id !== sidRef.current && row.frame === undefined) return
    if (row.frame) {
      seqRef.current = Number(row.seq)
      setSrc('data:image/jpeg;base64,' + row.frame)
      setStats(s => ({ frames: s.frames + 1, bytes: s.bytes + Math.floor(row.frame.length * 0.75) }))
      setFrameInfo({ seq: Number(row.seq), capturedAt: row.captured_at, meta: row.meta || {} })
    } else if (row.meta) {
      setFrameInfo(f => ({ ...f, meta: row.meta || {} }))
    }
  }, [dev.id])

  // Start relace + příkaz jednotce; konec při zavření / odchodu ze stránky.
  useEffect(() => {
    let alive = true
    let unsubscribe = null
    let keep = null, poll = null, clock = null
    ;(async () => {
      try {
        const id = await startSession(dev, { control: false })
        if (!alive) { await endSession(id); return }
        sidRef.current = id
        setSessionId(id)
        const ok = await onCommand(dev, 'screen_mirror', { session_id: id, on: true, control: false, ttl_s: SESSION_TTL_S })
        if (!ok) setError('Příkaz jednotce se nepodařilo odeslat.')
        unsubscribe = subscribeFrames(dev.id, pull)
        keep = setInterval(() => keepalive(id), KEEPALIVE_MS)
        poll = setInterval(() => { if (!document.hidden) pull() }, 4000)
        clock = setInterval(() => setNow(Date.now()), 1000)
        setTimeout(pull, 1500)
      } catch (e) { setError(e.message || String(e)) }
    })()
    const onVisible = () => { if (!document.hidden) pull() }
    document.addEventListener('visibilitychange', onVisible)
    const onUnload = () => { if (sidRef.current) endSession(sidRef.current) }
    window.addEventListener('beforeunload', onUnload)
    return () => {
      alive = false
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('beforeunload', onUnload)
      if (unsubscribe) unsubscribe()
      if (keep) clearInterval(keep)
      if (poll) clearInterval(poll)
      if (clock) clearInterval(clock)
      const id = sidRef.current
      sidRef.current = null
      if (id) { endSession(id); onCommand(dev, 'screen_mirror', { session_id: id, on: false }) }
    }
  }, [dev.id])   // eslint-disable-line react-hooks/exhaustive-deps

  async function toggleControl() {
    const next = !control
    setCtrl(next)
    await setControl(sessionId, next)
    await onCommand(dev, 'screen_mirror', { session_id: sessionId, on: true, control: next, ttl_s: SESSION_TTL_S })
  }
  async function onTap(e) {
    if (!control || !imgRef.current || !sessionId) return
    const p = pointInImage(e, imgRef.current)
    if (!p) return
    setTapMark({ x: e.clientX, y: e.clientY, ts: Date.now() })
    await onCommand(dev, 'screen_input', { session_id: sessionId, kind: 'tap', x: p.x, y: p.y, sent_at: new Date().toISOString() })
  }
  async function answerDialog(text) {
    await onCommand(dev, 'screen_input', { session_id: sessionId, kind: 'dialog', text, sent_at: new Date().toISOString() })
    setDialogText('')
    setFrameInfo(f => ({ ...f, meta: { ...(f.meta || {}), dialog: null } }))
  }

  const age = frameInfo.capturedAt ? Math.max(0, Math.round((now - new Date(frameInfo.capturedAt).getTime()) / 1000)) : null
  const left = Math.max(0, SESSION_TTL_S - Math.round((now - startedAt) / 1000))
  const ended = frameInfo.meta && frameInfo.meta.ended === true && stats.frames > 0
  const dialog = frameInfo.meta && frameInfo.meta.dialog

  return createPortal(
    <div className="fixed inset-0 flex flex-col" style={{ zIndex: 60, background: '#000' }} onClick={e => e.stopPropagation()}>
      <div className="flex items-center gap-3 flex-wrap px-4 py-2 text-[12px]" style={{ background: '#0f1a14', color: '#d4e8e0' }}>
        <span className="font-black uppercase tracking-wide" style={{ color: '#74FB71' }}>🖥 Obrazovka: {dev.name || dev.id}</span>
        <span>{src ? `snímek před ${age ?? '?'} s · ${stats.frames}× · ${fmtMb(stats.bytes)}` : (error ? '' : 'čekám na první snímek (2–10 s)…')}</span>
        <span>· zbývá {Math.floor(left / 60)}:{String(left % 60).padStart(2, '0')}</span>
        {error && <span className="font-bold" style={{ color: '#fca5a5' }}>· {error}</span>}
        {ended && <span className="font-bold" style={{ color: '#fde68a' }}>· relace na jednotce skončila — zavřete a otevřete znovu</span>}
        <label className="ml-auto flex items-center gap-2 cursor-pointer font-bold" style={{ color: control ? '#fca5a5' : '#d4e8e0' }}
          title="Klepnutí do obrazu = dotyk na displeji pobočky (stejné jako prst zákazníka). Zapínejte jen, když víte, co děláte.">
          <input type="checkbox" checked={control} onChange={toggleControl} disabled={!sessionId} /> Ovládat
        </label>
        <button onClick={onClose} className="rounded-btn font-extrabold cursor-pointer border-none" style={{ padding: '5px 12px', background: '#74FB71', color: '#1a2e22' }}>Zavřít</button>
      </div>
      <div className="flex-1 flex items-center justify-center relative" style={{ minHeight: 0, cursor: control ? 'crosshair' : 'default' }}>
        {src
          ? <img ref={imgRef} src={src} alt="obrazovka kiosku" onClick={onTap} draggable={false}
              style={{ width: '100%', height: '100%', objectFit: 'contain', userSelect: 'none' }} />
          : <div className="text-sm" style={{ color: '#6b8c7a' }}>{error ? 'Zrcadlení se nepodařilo spustit.' : 'Jednotka připravuje snímek…'}</div>}
        {tapMark && now - tapMark.ts < 800 && (
          <div className="fixed rounded-full pointer-events-none" style={{ left: tapMark.x - 12, top: tapMark.y - 12, width: 24, height: 24, border: '3px solid #74FB71' }} />
        )}
        {dialog && (
          <div className="absolute left-1/2 -translate-x-1/2 rounded-card p-3" style={{ bottom: 24, background: '#fff', width: 420, maxWidth: '90%', color: '#1a2e22' }}>
            <div className="text-[11px] font-extrabold uppercase" style={{ color: '#b45309' }}>Dialog na displeji ({dialog.type})</div>
            <div className="text-sm mb-2">{dialog.message}</div>
            {control ? (
              <div className="flex gap-2">
                {dialog.type === 'prompt' && <input className="flex-1 rounded-btn px-2 py-1 text-sm" style={{ border: '1px solid #d4e8e0' }} value={dialogText} onChange={e => setDialogText(e.target.value)} placeholder="hodnota" />}
                <Btn tone="green" onClick={() => answerDialog(dialog.type === 'prompt' ? dialogText : '')}>OK</Btn>
                <Btn tone="gray" onClick={() => answerDialog(null)}>Zrušit</Btn>
              </div>
            ) : <div className="text-[11px]" style={{ color: '#6b8c7a' }}>Zapněte „Ovládat“, chcete-li dialog vyřídit odsud.</div>}
          </div>
        )}
      </div>
    </div>,
    document.body,
  )
}
