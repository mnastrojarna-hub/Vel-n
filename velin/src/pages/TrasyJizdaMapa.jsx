import { useEffect, useMemo, useRef } from 'react'
import { MAPY_CZ_API_KEY } from '../lib/mapyCz'
import { splitTrackOnGaps } from '../lib/rideTrack'

// Náhled projeté jízdy zákazníka ve Velíně — stopa GPS + značky start / cíl
// / zastávky (+ volitelně ŽIVÁ poloha u právě nahrávané jízdy). Read-only
// (moderace, ne editace bodů v mapě). Leaflet běží v iframe (bez npm
// závislosti), stav se posílá přes postMessage — stejný vzor jako
// TrasyMapPicker, jen bez klikání do mapy.
//
// PROČ SE STOPA TRHÁ NA ÚSEKY: když appka běžela na pozadí, GPS fixy
// nechodily a mezi dvěma body je klidně hodina a 40 km. Spojit je plnou
// čarou = tvrdit, že tudy zákazník jel. Takový úsek proto kreslíme
// přerušovaně a šedě — „tady trasu neznáme".
//
// Props:
//   track  [[lat,lng,ts,kmh,alt],…]         – stopa jízdy
//   points [{kind,name,lat,lng}]            – start / cíl / zastávky
//   live   {lat,lng,ageSec,isLive} | null   – aktuální poloha (nahrávaná jízda)
//   height number                           – výška mapy (px)
//   fitKey any                              – změna hodnoty = přerámovat mapu
export default function TrasyJizdaMapa({
  track = [], points = [], live = null, height = 320, fitKey = null,
}) {
  const iframeRef = useRef(null)
  const readyRef = useRef(false)

  // Rozdělení stopy na souvislé úseky + mezery počítáme jen při změně stopy.
  const segments = useMemo(() => splitTrackOnGaps(track), [track])

  const cleanPoints = useMemo(() => (points || [])
    .filter(p => p && p.lat != null && p.lng != null)
    .map(p => ({
      lat: Number(p.lat), lng: Number(p.lng),
      kind: p.kind || 'stop', name: p.name || '',
    })), [points])

  // Rozložíme `live` na primitivy — rodič ho typicky skládá jako nový objekt
  // při každém renderu a efekt níž by se pak pouštěl pořád dokola.
  const liveLat = live?.lat, liveLng = live?.lng
  const liveOn = !!live?.isLive, liveLabel = live?.label
  const livePoint = useMemo(() => (
    liveLat != null && liveLng != null
      ? {
        lat: Number(liveLat), lng: Number(liveLng), isLive: liveOn,
        label: liveLabel || 'Aktuální poloha zákazníka',
      }
      : null
  ), [liveLat, liveLng, liveOn, liveLabel])

  // Body `start` / `end` zakládá až ukončení jízdy. U PRÁVĚ NAHRÁVANÉ jízdy
  // by tedy mapa neměla ani jednu značku — jen holou čáru, u které operátor
  // nepozná, kde vyjížďka začala. Dopočítáme je proto ze stopy.
  const markers = useMemo(() => {
    const out = [...cleanPoints]
    const first = segments[0]?.pts?.[0]
    const lastSeg = segments[segments.length - 1]
    const last = lastSeg?.pts?.[lastSeg.pts.length - 1]
    if (first && !out.some(p => p.kind === 'start')) {
      out.unshift({ lat: first[0], lng: first[1], kind: 'start', name: 'Start (ze stopy)' })
    }
    // Konec nedokreslujeme, když je na mapě živá poloha — to je „kde je teď".
    if (last && !livePoint && !out.some(p => p.kind === 'end') &&
        (last[0] !== first?.[0] || last[1] !== first?.[1])) {
      out.push({ lat: last[0], lng: last[1], kind: 'end', name: 'Poslední bod stopy' })
    }
    return out
  }, [cleanPoints, segments, livePoint])

  // Střed mapy při prvním vykreslení. `useMemo` bez deps by se při změně
  // jízdy nepřepočítal — proto počítáme ze VŠECH dostupných bodů a mapa se
  // stejně hned přerámuje přes fitBounds.
  const initial = useMemo(() => {
    const pts = []
    segments.forEach(s => s.pts.forEach(p => pts.push(p)))
    cleanPoints.forEach(p => pts.push([p.lat, p.lng]))
    if (livePoint) pts.push([livePoint.lat, livePoint.lng])
    if (!pts.length) return { lat: 49.8175, lng: 15.4730, z: 7 }
    return {
      lat: pts.reduce((s, p) => s + p[0], 0) / pts.length,
      lng: pts.reduce((s, p) => s + p[1], 0) / pts.length,
      z: 11,
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const tileUrl = `https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`

  // srcDoc se staví JEN jednou — jinak by se iframe při každém renderu
  // znovu načetl a mapa by blikala a zapomínala posun/zoom.
  const srcDoc = useMemo(() => `<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>
<style>html,body{margin:0;padding:0;height:100%}#m{height:100%;width:100%}
.pin{display:flex;align-items:center;justify-content:center;border-radius:50%;border:2px solid #fff;
  box-shadow:0 1px 4px rgba(0,0,0,.4);font-weight:800;color:#fff;font-size:12px;font-family:sans-serif}
.stop{background:#1a8a18;width:26px;height:26px}
.start{background:#13C14E;width:28px;height:28px;color:#0f1a14}
.end{background:#1a2e22;width:28px;height:28px}
.live{background:#dc2626;width:22px;height:22px;font-size:11px}
.live-stale{background:#b45309;width:22px;height:22px;font-size:11px}
@keyframes mgpulse{0%{transform:scale(.6);opacity:.85}100%{transform:scale(2.6);opacity:0}}
.halo{border-radius:50%;background:#dc2626;width:22px;height:22px;animation:mgpulse 1.8s ease-out infinite}
.lg-credit{position:absolute;left:8px;bottom:4px;z-index:500}.lg-credit img{width:80px}</style></head>
<body><div id="m"></div>
<a class="lg-credit" href="https://mapy.cz/" target="_blank"><img src="https://api.mapy.cz/img/api/logo.svg" alt="Mapy.cz"/></a>
<script>
var map=L.map("m",{zoomControl:true}).setView([${initial.lat},${initial.lng}],${initial.z});
L.tileLayer(${JSON.stringify(tileUrl)},{minZoom:0,maxZoom:19,attribution:'<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>'}).addTo(map);
var layer=L.layerGroup().addTo(map);
var lastFit=null;
function icon(cls,txt){return L.divIcon({html:'<div class="pin '+cls+'">'+txt+'</div>',className:'',iconSize:[28,28],iconAnchor:[14,14]});}
function send(o){o.__mg='jizda-map';parent.postMessage(o,'*');}
window.addEventListener('message',function(e){
  var d=e.data; if(!d||d.__mg!=='jizda-map'||d.type!=='render') return;
  layer.clearLayers();
  var pts=[];
  // Souvislé úseky = plná zelená čára. Mezery (appka na pozadí / bez
  // signálu) = šedá přerušovaná — trasu mezi nimi NEZNÁME.
  (d.segments||[]).forEach(function(seg){
    if(!seg.pts||seg.pts.length<1) return;
    for(var i=0;i<seg.pts.length;i++) pts.push(seg.pts[i]);
    if(seg.pts.length<2) return;
    L.polyline(seg.pts,{color:'#1a2e22',weight:7,opacity:.30}).addTo(layer);
    L.polyline(seg.pts,{color:'#1a8a18',weight:4,opacity:.95}).addTo(layer);
  });
  (d.gaps||[]).forEach(function(g){
    L.polyline([g.from,g.to],{color:'#94a3b8',weight:3,opacity:.85,dashArray:'6,8'})
      .addTo(layer).bindTooltip('Bez signálu '+g.label+' — trasa není známá');
  });
  var n=0;
  (d.points||[]).forEach(function(p){
    pts.push([p.lat,p.lng]);
    var cls=p.kind==='start'?'start':(p.kind==='end'?'end':'stop');
    var txt=p.kind==='start'?'S':(p.kind==='end'?'C':String(++n));
    L.marker([p.lat,p.lng],{icon:icon(cls,txt)}).addTo(layer)
      .bindTooltip(p.name||(p.kind==='start'?'Start':(p.kind==='end'?'Cíl':'Zastávka '+n)));
  });
  if(d.live){
    pts.push([d.live.lat,d.live.lng]);
    if(d.live.isLive){
      L.marker([d.live.lat,d.live.lng],{icon:L.divIcon({html:'<div class="halo"></div>',
        className:'',iconSize:[22,22],iconAnchor:[11,11]}),interactive:false}).addTo(layer);
    }
    L.marker([d.live.lat,d.live.lng],{icon:icon(d.live.isLive?'live':'live-stale','')
      ,zIndexOffset:1000}).addTo(layer).bindTooltip(d.live.label||'Aktuální poloha');
  }
  // Přerámujeme jen když o to parent vysloveně požádá (nová jízda / první
  // vykreslení). Jinak by mapa uskakovala při každém přenačtení polohy
  // a operátor by si ji nemohl posunout.
  if(d.fit&&d.fit!==lastFit){
    lastFit=d.fit;
    if(pts.length>1){try{map.fitBounds(pts,{padding:[26,26],maxZoom:15});}catch(err){}}
    else if(pts.length===1){map.setView(pts[0],13);}
  }
}, false);
send({type:'ready'});
<\/script></body></html>`, [initial, tileUrl])

  useEffect(() => {
    function push() {
      const win = iframeRef.current?.contentWindow
      if (!win || !readyRef.current) return
      win.postMessage({
        __mg: 'jizda-map',
        type: 'render',
        segments: segments.map(s => ({ pts: s.pts })),
        gaps: segments.flatMap(s => s.gapBefore ? [s.gapBefore] : []),
        points: markers,
        live: livePoint ? {
          lat: livePoint.lat, lng: livePoint.lng, isLive: livePoint.isLive,
          label: live?.label || 'Aktuální poloha zákazníka',
        } : null,
        fit: fitKey == null ? 'init' : String(fitKey),
      }, '*')
    }

    function onMsg(e) {
      // Zprávy bereme JEN z vlastního iframu — na stránce jich může být víc
      // (seznam jízd + detail) a jinak by si navzájem kradly handshake.
      if (e.source !== iframeRef.current?.contentWindow) return
      const d = e.data
      if (!d || d.__mg !== 'jizda-map' || d.type !== 'ready') return
      readyRef.current = true
      push()
    }
    window.addEventListener('message', onMsg)
    // Iframe mohl poslat „ready" dřív, než jsme listener stihli pověsit
    // (srcDoc se vykresluje synchronně). Pošleme data i rovnou.
    push()
    return () => window.removeEventListener('message', onMsg)
  }, [segments, markers, livePoint, fitKey])

  return (
    <div className="rounded-card overflow-hidden" style={{ border: '1px solid #d4e8e0' }}>
      <iframe ref={iframeRef} title="Mapa jízdy" srcDoc={srcDoc}
        style={{ width: '100%', height, border: 'none', display: 'block' }} />
    </div>
  )
}
