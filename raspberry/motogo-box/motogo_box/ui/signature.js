/* MotoGo24 kiosk — podpis prstem (canvas) pro předávací protokol (handover.js).
   Pointer Events (prst / stylus / myš), tahy se drží v CSS px plátna a překreslují při změně velikosti.
   Export = pomocný canvas 800×260 px, bílé pozadí, černá čára, PNG data-URL ≤ 150 kB (kontrakt §22 / edge 413).
   Vanilla JS, bez závislostí. */
'use strict';
window.MG = window.MG || {};

MG.Signature = (function () {
  const EXPORT_W = 800, EXPORT_H = 260, MAX_BYTES = 150 * 1024, LINE_W = 3, MIN_LEN = 12;

  /** Délka lomené čáry (CSS px) — proti náhodnému ťuknutí jako „podpisu“. */
  function pathLength(strokes) {
    let len = 0;
    strokes.forEach((s) => { for (let i = 1; i < s.length; i++) len += Math.hypot(s[i].x - s[i - 1].x, s[i].y - s[i - 1].y); });
    return len;
  }

  /** Vykreslí tahy do kontextu: `scale` + posun (letterbox), čára zaoblená. */
  function paint(ctx, strokes, scale, dx, dy, width) {
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#0F1A14';
    ctx.fillStyle = '#0F1A14';
    ctx.lineWidth = width;
    strokes.forEach((s) => {
      if (!s.length) return;
      if (s.length === 1) {   // tečka (i, háček) — samotný bod by se čárou nevykreslil
        ctx.beginPath(); ctx.arc(s[0].x * scale + dx, s[0].y * scale + dy, width / 2, 0, Math.PI * 2); ctx.fill();
        return;
      }
      ctx.beginPath();
      ctx.moveTo(s[0].x * scale + dx, s[0].y * scale + dy);
      for (let i = 1; i < s.length; i++) ctx.lineTo(s[i].x * scale + dx, s[i].y * scale + dy);
      ctx.stroke();
    });
  }

  /**
   * create(canvas, { onStroke }) → { clear, isEmpty, toPng, resize, destroy }
   * `onStroke` se volá při každém pohybu prstu (dotyk = prodloužení relace, přepočet tlačítek).
   */
  function create(canvas, opts) {
    const o = Object.assign({ onStroke() {} }, opts || {});
    const ctx = canvas.getContext('2d');
    let strokes = [], cur = null, pointerId = null, w = 0, h = 0, dpr = 1;

    function pos(e) {
      const r = canvas.getBoundingClientRect();
      return { x: Math.max(0, Math.min(w, e.clientX - r.left)), y: Math.max(0, Math.min(h, e.clientY - r.top)) };
    }
    function redraw() {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      paint(ctx, strokes, 1, 0, 0, LINE_W);
    }
    /** Plátno = velikost svého boxu (CSS px) × devicePixelRatio; tahy se přepočítávají poměrem šířek.
        Skrytý overlay (display:none → 0×0) rozměry nemění — přepočet až po zobrazení (handover.open → resize). */
    function resize() {
      const r = canvas.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) return;
      const nw = Math.max(1, Math.round(r.width)), nh = Math.max(1, Math.round(r.height));
      if (w && (nw !== w || nh !== h)) {
        const k = nw / w;
        strokes = strokes.map((s) => s.map((p) => ({ x: p.x * k, y: p.y * k })));
      }
      w = nw; h = nh; dpr = Math.min(2, window.devicePixelRatio || 1);
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
      redraw();
    }
    function down(e) {
      if (pointerId !== null || (e.button != null && e.button !== 0)) return;
      e.preventDefault();
      pointerId = e.pointerId;
      try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* noop */ }
      cur = [pos(e)];
      strokes.push(cur);
      paint(ctx, [cur], 1, 0, 0, LINE_W);
      o.onStroke();
    }
    function move(e) {
      if (e.pointerId !== pointerId || !cur) return;
      e.preventDefault();
      const p = pos(e), q = cur[cur.length - 1];
      if (Math.hypot(p.x - q.x, p.y - q.y) < 0.8) return;   // šum senzoru
      cur.push(p);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#0F1A14'; ctx.lineWidth = LINE_W;
      ctx.beginPath(); ctx.moveTo(q.x, q.y); ctx.lineTo(p.x, p.y); ctx.stroke();
      o.onStroke();
    }
    function up(e) {
      if (e.pointerId !== pointerId) return;
      pointerId = null; cur = null;
      try { canvas.releasePointerCapture(e.pointerId); } catch (err) { /* noop */ }
      o.onStroke();
    }
    canvas.addEventListener('pointerdown', down);
    canvas.addEventListener('pointermove', move);
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', up);
    window.addEventListener('resize', resize);
    // Výška rámečku se mění i bez změny okna (delší popisky po přepnutí jazyka, jiná mřížka bez pole kódu) —
    // bitmapa musí sledovat box, jinak pos() ořezává podle starých rozměrů a tah se kreslí posunutě.
    const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(() => resize()) : null;
    if (ro) ro.observe(canvas.parentElement || canvas);

    /** PNG data-URL 800×260 (bílé pozadí); přes limit → menší export; stále přes limit → null (UI: ho.sigTooLarge). */
    function toPng() {
      if (isEmpty()) return null;
      const attempt = (ew, eh) => {
        const c = document.createElement('canvas');
        c.width = ew; c.height = eh;
        const x = c.getContext('2d');
        x.fillStyle = '#FFFFFF'; x.fillRect(0, 0, ew, eh);
        const scale = Math.min((ew - 16) / w, (eh - 16) / h);
        const dx = (ew - w * scale) / 2, dy = (eh - h * scale) / 2;
        paint(x, strokes, scale, dx, dy, Math.max(2, LINE_W * scale));
        const url = c.toDataURL('image/png');
        const bytes = Math.floor((url.length - url.indexOf(',') - 1) * 3 / 4);
        return bytes <= MAX_BYTES ? url : null;
      };
      return attempt(EXPORT_W, EXPORT_H) || attempt(Math.round(EXPORT_W * 0.75), Math.round(EXPORT_H * 0.75));
    }
    function isEmpty() { return !strokes.length || pathLength(strokes) < MIN_LEN; }
    function clear() { strokes = []; cur = null; pointerId = null; redraw(); o.onStroke(); }
    function destroy() {
      canvas.removeEventListener('pointerdown', down); canvas.removeEventListener('pointermove', move);
      canvas.removeEventListener('pointerup', up); canvas.removeEventListener('pointercancel', up);
      window.removeEventListener('resize', resize);
      if (ro) ro.disconnect();
    }
    return { clear, isEmpty, toPng, resize, destroy, get strokes() { return strokes.length; } };
  }

  return { create, EXPORT_W, EXPORT_H, MAX_BYTES };
})();
