import { useEffect, useMemo, useRef } from 'react'
import { MAPY_CZ_API_KEY } from '../lib/mapyCz'

// Náhled projeté jízdy zákazníka ve Velíně — stopa GPS + značky start / cíl
// / zastávky. Read-only (moderace, ne editace bodů v mapě). Leaflet běží
// v iframe (bez npm závislosti), stav se posílá přes postMessage — stejný
// vzor jako TrasyMapPicker, jen bez klikání do mapy.
//
// Props:
//   track  [[lat,lng],…]                    – stopa jízdy
//   points [{kind,name,lat,lng}]            – start / cíl / zastávky
//   height number                           – výška mapy (px)
export default function TrasyJizdaMapa({ track = [], points = [], height = 320 }) {
  const iframeRef = useRef(null)
  const readyRef = useRef(false)

  const initial = useRef(null)
  if (!initial.current) {
    const pts = track.length ? track : points.map(p => [p.lat, p.lng])
    if (pts.length) {
      const lat = pts.reduce((s, p) => s + Number(p[0]), 0) / pts.length
      const lng = pts.reduce((s, p) => s + Number(p[1]), 0) / pts.length
      initial.current = { lat, lng, z: 11 }
    } else {
      initial.current = { lat: 49.8175, lng: 15.4730, z: 7 }
    }
  }

  const tileUrl = `https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`

  function push() {
    const win = iframeRef.current?.contentWindow
    if (!win || !readyRef.current) return
    win.postMessage({
      __mg: 'jizda-map',
      type: 'render',
      track: (track || []).filter(p => Array.isArray(p) && p.length >= 2)
        .map(p => [Number(p[0]), Number(p[1])]),
      points: (points || []).filter(p => p.lat != null && p.lng != null)
        .map(p => ({ lat: Number(p.lat), lng: Number(p.lng), kind: p.kind || 'stop', name: p.name || '' })),
    }, '*')
  }

  useEffect(() => {
    function onMsg(e) {
      const d = e.data
      if (!d || d.__mg !== 'jizda-map' || d.type !== 'ready') return
      readyRef.current = true
      push()
    }
    window.addEventListener('message', onMsg)
    return () => window.removeEventListener('message', onMsg)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => { push() })

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
.lg-credit{position:absolute;left:8px;bottom:4px;z-index:500}.lg-credit img{width:80px}</style></head>
<body><div id="m"></div>
<a class="lg-credit" href="https://mapy.cz/" target="_blank"><img src="https://api.mapy.cz/img/api/logo.svg" alt="Mapy.cz"/></a>
<script>
var map=L.map("m",{zoomControl:true}).setView([${initial.current.lat},${initial.current.lng}],${initial.current.z});
L.tileLayer(${JSON.stringify(tileUrl)},{minZoom:0,maxZoom:19,attribution:'<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>'}).addTo(map);
var layer=L.layerGroup().addTo(map);
function icon(cls,txt){return L.divIcon({html:'<div class="pin '+cls+'">'+txt+'</div>',className:'',iconSize:[28,28],iconAnchor:[14,14]});}
function send(o){o.__mg='jizda-map';parent.postMessage(o,'*');}
window.addEventListener('message',function(e){
  var d=e.data; if(!d||d.__mg!=='jizda-map'||d.type!=='render') return;
  layer.clearLayers();
  var pts=[];
  if(d.track&&d.track.length>1){
    L.polyline(d.track,{color:'#1a2e22',weight:7,opacity:.35}).addTo(layer);
    L.polyline(d.track,{color:'#1a8a18',weight:4,opacity:.95}).addTo(layer);
    for(var i=0;i<d.track.length;i++) pts.push(d.track[i]);
  }
  var n=0;
  (d.points||[]).forEach(function(p){
    pts.push([p.lat,p.lng]);
    var cls=p.kind==='start'?'start':(p.kind==='end'?'end':'stop');
    var txt=p.kind==='start'?'S':(p.kind==='end'?'C':String(++n));
    L.marker([p.lat,p.lng],{icon:icon(cls,txt)}).addTo(layer)
      .bindTooltip(p.name||(p.kind==='start'?'Start':(p.kind==='end'?'Cíl':'Zastávka '+n)));
  });
  if(pts.length>1){try{map.fitBounds(pts,{padding:[26,26],maxZoom:15});}catch(err){}}
  else if(pts.length===1){map.setView(pts[0],13);}
}, false);
send({type:'ready'});
<\/script></body></html>`, [])

  return (
    <div className="rounded-card overflow-hidden" style={{ border: '1px solid #d4e8e0' }}>
      <iframe ref={iframeRef} title="Mapa jízdy" srcDoc={srcDoc}
        style={{ width: '100%', height, border: 'none', display: 'block' }} />
    </div>
  )
}
