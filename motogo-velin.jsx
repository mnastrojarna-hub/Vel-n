import { useState, useEffect, useRef } from "react";

/* ═══════════════════════════════════════════════════════════
   MOTOGO24 VELÍN — COMMAND CENTER v2
   Brand-consistent admin dashboard
   Colors: #74FB71 green, #1a2e22 dark, #dff0ec bg, Montserrat
═══════════════════════════════════════════════════════════ */

// ── BRAND COLORS (from MotoGo24 CSS) ──
const C = {
  bg: "#dff0ec", bg2: "#cde8e2", black: "#0f1a14", dark: "#1a2e22",
  green: "#74FB71", gd: "#3dba3a", gdk: "#1a8a18", gp: "#e8ffe8",
  g100: "#f1faf7", g200: "#d4e8e0", g400: "#8aab99", g600: "#4a6357",
  red: "#ef4444", gold: "#f59e0b", blue: "#3b82f6", purple: "#8b5cf6",
  white: "#ffffff", shadow: "0 4px 20px rgba(15,26,20,.1)",
};

// MotoGo SVG Logo
const Logo = ({ size = 48 }) => (
  <svg width={size} height={size} viewBox="0 0 100 100" fill="none">
    <circle cx="50" cy="50" r="46" stroke="#13C14E" strokeWidth="5"/>
    <path d="M22 72 L22 42 L50 20 L78 42 L78 72" stroke="#13C14E" strokeWidth="7" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
    <path d="M50 20 L50 52" stroke="#13C14E" strokeWidth="7" strokeLinecap="round"/>
    <path d="M35 72 Q50 56 65 72" stroke="#13C14E" strokeWidth="6" strokeLinecap="round" fill="none"/>
  </svg>
);

// ── MOCK DATA ──
const MOTOS = [
  { id:"bmw", name:"BMW R 1200 GS Adventure", cat:"cestovní", status:"active", branch:"Mezná", km:42350, spz:"5P2 3456", price:4208, nextSvc:"2026-04-15", util:78, rev:134656, cost:18200 },
  { id:"jawa", name:"Jawa RVM 500 Adventure", cat:"cestovní", status:"active", branch:"Mezná", km:18200, spz:"3J1 2233", price:1986, nextSvc:"2026-05-01", util:65, rev:63552, cost:8400 },
  { id:"benelli", name:"Benelli TRK 702 X", cat:"cestovní", status:"maintenance", branch:"Mezná", km:31400, spz:"2B4 7788", price:2951, nextSvc:"2026-03-10", util:0, rev:47216, cost:24200 },
  { id:"cfmoto", name:"CF MOTO 800 MT", cat:"cestovní", status:"active", branch:"Mezná", km:15800, spz:"6C2 1199", price:3941, nextSvc:"2026-06-20", util:82, rev:126112, cost:12100 },
  { id:"niken", name:"Yamaha Niken GT", cat:"special", status:"active", branch:"Mezná", km:28900, spz:"1Y3 5566", price:3931, nextSvc:"2026-03-28", util:71, rev:110068, cost:15300 },
  { id:"ktm", name:"KTM 1290 Super Adv.", cat:"adventure", status:"active", branch:"Brno", km:52100, spz:"4K7 9900", price:4500, nextSvc:"2026-04-05", util:88, rev:162000, cost:22000 },
  { id:"tiger", name:"Triumph Tiger 1200", cat:"adventure", status:"out_of_service", branch:"Brno", km:67200, spz:"7T8 4411", price:4100, nextSvc:null, util:0, rev:0, cost:35000 },
  { id:"versys", name:"Kawasaki Versys 650", cat:"naked", status:"active", branch:"Brno", km:22700, spz:"8K1 6677", price:2200, nextSvc:"2026-05-15", util:59, rev:52800, cost:9800 },
];
const BOOKINGS = [
  { id:"RES-2026-001", cust:"Jan Novák", moto:"BMW R 1200 GS", from:"2026-03-01", to:"2026-03-04", status:"active", total:16832, paid:true },
  { id:"RES-2026-002", cust:"Petra Dvořáková", moto:"CF MOTO 800 MT", from:"2026-03-02", to:"2026-03-05", status:"active", total:15764, paid:true },
  { id:"RES-2026-003", cust:"Martin Šimek", moto:"KTM 1290 SA", from:"2026-03-05", to:"2026-03-08", status:"pending", total:18000, paid:false },
  { id:"RES-2026-004", cust:"Eva Králová", moto:"Yamaha Niken GT", from:"2026-03-03", to:"2026-03-06", status:"active", total:15724, paid:true },
  { id:"RES-2026-005", cust:"Tomáš Beneš", moto:"Kawasaki Versys", from:"2026-03-10", to:"2026-03-12", status:"pending", total:4400, paid:false },
];
const MSGS = [
  { id:1, from:"Jan Novák", ch:"web", subj:"Dotaz na prodloužení", time:"dnes 14:32", unread:true },
  { id:2, from:"Petra D.", ch:"whatsapp", subj:"Problém s helmetem", time:"dnes 11:15", unread:true },
  { id:3, from:"Martin Šimek", ch:"email", subj:"Potvrzení platby", time:"včera 19:00", unread:false },
  { id:4, from:"Autoservis Havel", ch:"email", subj:"Benelli TRK hotova", time:"dnes 09:00", unread:true },
  { id:5, from:"Eva K.", ch:"instagram", subj:"Fotky z výletu", time:"včera 16:45", unread:false },
];
const INVENTORY = [
  { id:1, name:"Helma Shoei GT-Air II", sku:"HLM-001", stock:8, min:4, cat:"ochranné", price:12500 },
  { id:2, name:"Bunda Alpinestars Andes", sku:"BUN-001", stock:2, min:4, cat:"ochranné", price:8200 },
  { id:3, name:"Motorový olej Motul 10W-40", sku:"OIL-001", stock:24, min:10, cat:"spotřební", price:450 },
  { id:4, name:"Brzdové destičky univerzál", sku:"BRK-001", stock:6, min:8, cat:"spotřební", price:890 },
  { id:5, name:"Řetězová sada 520", sku:"RET-001", stock:3, min:4, cat:"spotřební", price:3200 },
  { id:6, name:"Pneumatiky Michelin Road 6", sku:"PNE-001", stock:4, min:4, cat:"spotřební", price:4800 },
];
const DOCS = [
  { id:1, type:"VOP", name:"Všeobecné obchodní podmínky v2.4", updated:"2026-02-15", status:"active" },
  { id:2, type:"Smlouva", name:"Šablona nájemní smlouvy", updated:"2026-01-20", status:"active" },
  { id:3, type:"Faktura", name:"Šablona faktury", updated:"2026-02-28", status:"active" },
  { id:4, type:"Protokol", name:"Předávací protokol motorky", updated:"2026-02-10", status:"active" },
  { id:5, type:"GDPR", name:"Souhlas se zpracováním údajů", updated:"2025-12-01", status:"review" },
  { id:6, type:"Pojistka", name:"Pojistné podmínky pronájmu", updated:"2026-01-05", status:"active" },
];
const MO = ["Led","Úno","Bře","Dub","Kvě","Čvn","Čvc","Srp","Zář","Říj","Lis","Pro"];
const REV = [82,71,145,198,267,312,345,356,289,178,95,68];
const COST_DATA = [48,42,72,89,112,134,148,152,124,88,52,38];

const STATUS = {
  active:{ l:"Aktivní", c:C.gdk, bg:"#dcfce7" },
  maintenance:{ l:"V servisu", c:"#92400e", bg:"#fef3c7" },
  out_of_service:{ l:"Vyřazena", c:"#991b1b", bg:"#fee2e2" },
  pending:{ l:"Čekající", c:"#92400e", bg:"#fef3c7" },
  completed:{ l:"Dokončena", c:C.blue, bg:"#dbeafe" },
  review:{ l:"K revizi", c:C.purple, bg:"#ede9fe" },
};

const NAV = [
  { id:"dash", l:"Velín", i:"⚡" },
  { id:"fleet", l:"Flotila", i:"🏍️" },
  { id:"book", l:"Rezervace", i:"📅" },
  { id:"crm", l:"Zákazníci", i:"👥" },
  { id:"fin", l:"Finance", i:"💰" },
  { id:"acct", l:"Účetnictví", i:"📒" },
  { id:"docs", l:"Dokumenty", i:"📄" },
  { id:"inv", l:"Sklady", i:"📦" },
  { id:"svc", l:"Servis", i:"🔧" },
  { id:"msg", l:"Zprávy", i:"💬" },
  { id:"cms", l:"Web CMS", i:"🌐" },
  { id:"stats", l:"Statistiky", i:"📊" },
  { id:"buy", l:"Nákupy", i:"🛒" },
  { id:"gov", l:"Státní správa", i:"🏛️" },
  { id:"ai", l:"AI Copilot", i:"🤖" },
];

// ── SHARED COMPONENTS ──
const Badge = ({l,c,bg})=><span style={{display:"inline-block",padding:"4px 12px",borderRadius:50,fontSize:10,fontWeight:800,color:c,background:bg,letterSpacing:.4,textTransform:"uppercase"}}>{l}</span>;
const Btn = ({children,green,outline,onClick,style:s})=><button onClick={onClick} style={{padding:"10px 22px",borderRadius:50,fontSize:12,fontWeight:800,border:outline?`2px solid ${C.green}`:"none",background:green?C.green:outline?"transparent":C.g100,color:green?C.white:outline?C.gd:C.g600,cursor:"pointer",textTransform:"uppercase",letterSpacing:.5,display:"inline-flex",alignItems:"center",gap:6,boxShadow:green?"0 4px 16px rgba(116,251,113,.35)":"none",...s}}>{children}</button>;

const Card = ({children,style:s})=><div style={{background:C.white,borderRadius:18,padding:20,boxShadow:C.shadow,...s}}>{children}</div>;

const Stat = ({icon,label,value,sub,color=C.gdk})=>(
  <Card style={{flex:1,minWidth:160,position:"relative",overflow:"hidden"}}>
    <div style={{position:"absolute",top:-10,right:-10,fontSize:48,opacity:.06}}>{icon}</div>
    <div style={{fontSize:10,fontWeight:800,color:C.g400,textTransform:"uppercase",letterSpacing:1,marginBottom:6}}>{label}</div>
    <div style={{fontSize:24,fontWeight:900,color,letterSpacing:-1}}>{value}</div>
    {sub&&<div style={{fontSize:11,color:C.g400,fontWeight:500,marginTop:4}}>{sub}</div>}
  </Card>
);

const Chart = ({data,color=C.gdk,h=50})=>{const mx=Math.max(...data),mn=Math.min(...data),r=mx-mn||1,w=100/data.length;return(
  <svg viewBox={`0 0 100 ${h}`} style={{width:"100%",height:h}} preserveAspectRatio="none">
    <defs><linearGradient id={`cg${color.slice(1)}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor={color} stopOpacity=".25"/><stop offset="100%" stopColor={color} stopOpacity="0"/></linearGradient></defs>
    <path d={`M0,${h} ${data.map((v,i)=>`L${i*w+w/2},${h-((v-mn)/r)*(h-6)-3}`).join(" ")} L100,${h} Z`} fill={`url(#cg${color.slice(1)})`}/>
    <polyline fill="none" stroke={color} strokeWidth="1.8" strokeLinejoin="round" points={data.map((v,i)=>`${i*w+w/2},${h-((v-mn)/r)*(h-6)-3}`).join(" ")}/>
  </svg>
);};

const ExportBar = ()=>(
  <div style={{display:"flex",gap:8,marginTop:16,paddingTop:12,borderTop:`1px solid ${C.g200}`}}>
    <span style={{fontSize:11,fontWeight:700,color:C.g400,marginRight:4,lineHeight:"30px"}}>EXPORT:</span>
    {["PDF","XLSX","CSV","XML","JSON"].map(f=><Btn key={f} style={{padding:"4px 14px",fontSize:10}}>{f}</Btn>)}
  </div>
);

const TRow = ({children,header})=><tr style={{borderBottom:`1px solid ${C.g200}`,background:header?C.g100:"transparent"}}>{children}</tr>;
const TH = ({children})=><th style={{padding:"10px 14px",textAlign:"left",fontSize:10,fontWeight:800,color:C.g400,textTransform:"uppercase",letterSpacing:.5}}>{children}</th>;
const TD = ({children,bold,color,mono})=><td style={{padding:"10px 14px",fontSize:13,fontWeight:bold?700:500,color:color||C.black,fontFamily:mono?"monospace":"inherit"}}>{children}</td>;

// ── DASHBOARD ──
const Dash = ()=>{
  const actM=MOTOS.filter(m=>m.status==="active").length,totR=MOTOS.reduce((s,m)=>s+m.rev,0),actB=BOOKINGS.filter(b=>b.status==="active").length,penB=BOOKINGS.filter(b=>b.status==="pending").length,unr=MSGS.filter(m=>m.unread).length,low=INVENTORY.filter(i=>i.stock<=i.min).length,avgU=Math.round(MOTOS.filter(m=>m.status==="active").reduce((s,m)=>s+m.util,0)/actM);
  return(<div>
    <div style={{display:"flex",gap:14,marginBottom:20,flexWrap:"wrap"}}>
      <Stat icon="🏍️" label="Aktivní motorky" value={`${actM}/${MOTOS.length}`} sub={`Ø využití ${avgU}%`}/>
      <Stat icon="💰" label="Tržby měsíc" value={`${(totR/1000).toFixed(0)}k Kč`} sub="+18% vs minulý" color={C.gold}/>
      <Stat icon="📅" label="Akt. / Čekající" value={`${actB} / ${penB}`} sub="rezervací" color={C.blue}/>
      <Stat icon="💬" label="Nepřečtené" value={unr} sub="z 5 kanálů" color={C.purple}/>
    </div>
    <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:16}}>
      <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:10}}>📈 Tržby vs náklady (tis. Kč)</div><Chart data={REV} color={C.gdk} h={70}/><Chart data={COST_DATA} color={C.red} h={30}/><div style={{display:"flex",justifyContent:"space-between",marginTop:6}}>{MO.map((m,i)=><span key={i} style={{fontSize:8,color:C.g400,fontWeight:700}}>{m}</span>)}</div><div style={{display:"flex",gap:16,marginTop:8}}><span style={{fontSize:10,color:C.gdk,fontWeight:700}}>● Tržby</span><span style={{fontSize:10,color:C.red,fontWeight:700}}>● Náklady</span></div></Card>
      <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:10}}>🏍️ Flotila</div>{MOTOS.slice(0,5).map(m=><div key={m.id} style={{display:"flex",alignItems:"center",padding:"7px 10px",background:C.g100,borderRadius:12,marginBottom:6,fontSize:12}}><span style={{flex:1,fontWeight:700,color:C.black}}>{m.name}</span><span style={{color:C.g400,fontSize:11,marginRight:10}}>{m.km.toLocaleString()} km</span><Badge {...STATUS[m.status]}/></div>)}</Card>
      <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:10}}>📅 Rezervace</div>{BOOKINGS.filter(b=>b.status==="active"||b.status==="pending").map(b=><div key={b.id} style={{display:"flex",padding:"8px 10px",background:C.g100,borderRadius:12,marginBottom:6,fontSize:12}}><div style={{flex:1}}><div style={{fontWeight:700,color:C.black}}>{b.cust}</div><div style={{color:C.g400,fontSize:11}}>{b.moto} · {b.from}→{b.to}</div></div><div style={{textAlign:"right"}}><div style={{fontWeight:800,color:C.gd}}>{b.total.toLocaleString()} Kč</div><Badge {...STATUS[b.status]}/></div></div>)}</Card>
      <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:10}}>💬 Zprávy</div>{MSGS.slice(0,4).map(m=><div key={m.id} style={{display:"flex",alignItems:"flex-start",padding:"8px 10px",background:m.unread?C.gp:C.g100,borderRadius:12,marginBottom:6,borderLeft:m.unread?`3px solid ${C.green}`:"3px solid transparent"}}><div style={{width:26,height:26,borderRadius:"50%",background:C.dark,display:"flex",alignItems:"center",justifyContent:"center",fontSize:12,marginRight:8,flexShrink:0,color:C.white}}>{({web:"🌐",whatsapp:"📱",email:"📧",instagram:"📸"})[m.ch]}</div><div style={{flex:1}}><div style={{fontSize:12,fontWeight:m.unread?800:500,color:C.black}}>{m.from} <span style={{color:C.g400,fontWeight:400,fontSize:10}}>· {m.time}</span></div><div style={{color:C.g600,fontSize:11,marginTop:1}}>{m.subj}</div></div></div>)}</Card>
    </div>
    <div style={{display:"flex",gap:10,marginTop:16,flexWrap:"wrap"}}>
      {low>0&&<div style={{background:"#fef3c7",borderRadius:50,padding:"8px 18px",fontSize:12,fontWeight:700,color:"#92400e"}}>⚠️ {low} položek pod minimem</div>}
      <div style={{background:"#fee2e2",borderRadius:50,padding:"8px 18px",fontSize:12,fontWeight:700,color:"#991b1b"}}>🔧 Benelli TRK — servis do 10. 3.</div>
      <div style={{background:"#dbeafe",borderRadius:50,padding:"8px 18px",fontSize:12,fontWeight:700,color:C.blue}}>📊 Sezóna startuje — +42% poptávka</div>
    </div>
  </div>);
};

// ── FLEET ──
const Fleet = ()=>{const[f,sF]=useState("all");const d=f==="all"?MOTOS:MOTOS.filter(m=>m.status===f);return(<div>
  <div style={{display:"flex",gap:8,marginBottom:16,flexWrap:"wrap"}}>{[["all","Vše"],["active","Aktivní"],["maintenance","Servis"],["out_of_service","Vyřazené"]].map(([v,l])=><button key={v} onClick={()=>sF(v)} style={{padding:"7px 16px",borderRadius:50,fontSize:11,fontWeight:800,border:`2px solid ${f===v?C.green:C.g200}`,background:f===v?C.green:C.white,color:f===v?C.white:C.g600,cursor:"pointer",textTransform:"uppercase",letterSpacing:.3}}>{l}</button>)}<div style={{flex:1}}/><Btn green>+ Přidat motorku</Btn></div>
  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:14}}>{d.map(m=><Card key={m.id} style={{position:"relative"}}><div style={{position:"absolute",top:16,right:16}}><Badge {...STATUS[m.status]}/></div><div style={{fontSize:15,fontWeight:900,color:C.black,marginBottom:2}}>{m.name}</div><div style={{fontSize:11,color:C.g400,fontWeight:600,marginBottom:14}}>{m.branch} · {m.spz} · {m.cat}</div><div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr 1fr",gap:8}}>{[["Najeto",m.km.toLocaleString()+" km",C.black],["Cena/den",m.price.toLocaleString()+" Kč",C.gd],["Využití",m.util+"%",m.util>70?C.gdk:m.util>40?"#92400e":C.red],["Zisk/měs",(m.rev-m.cost>0?"+":"")+(Math.round((m.rev-m.cost)/1000))+"k",m.rev-m.cost>0?C.gdk:C.red]].map(([l,v,c],i)=><div key={i}><div style={{fontSize:9,color:C.g400,fontWeight:700,textTransform:"uppercase"}}>{l}</div><div style={{fontSize:14,fontWeight:800,color:c}}>{v}</div></div>)}</div>{m.nextSvc&&<div style={{marginTop:10,padding:"6px 10px",background:C.g100,borderRadius:10,fontSize:11,color:C.g600}}>🔧 Servis: <strong style={{color:C.black}}>{m.nextSvc}</strong></div>}</Card>)}</div>
</div>);};

// ── BOOKINGS ──
const Book = ()=>(<div><div style={{marginBottom:16}}><Btn green>+ Nová rezervace</Btn></div><Card style={{padding:0,overflow:"hidden"}}><table style={{width:"100%",borderCollapse:"collapse"}}><thead><TRow header><TH>ID</TH><TH>Zákazník</TH><TH>Motorka</TH><TH>Od</TH><TH>Do</TH><TH>Částka</TH><TH>Stav</TH><TH>Platba</TH></TRow></thead><tbody>{BOOKINGS.map(b=><TRow key={b.id}><TD mono color={C.gdk}>{b.id}</TD><TD bold>{b.cust}</TD><TD>{b.moto}</TD><TD>{b.from}</TD><TD>{b.to}</TD><TD bold color={C.gd} mono>{b.total.toLocaleString()} Kč</TD><TD><Badge {...STATUS[b.status]}/></TD><TD>{b.paid?<span style={{color:C.gdk,fontWeight:700}}>✓ Zaplaceno</span>:<span style={{color:"#92400e",fontWeight:700}}>Čeká</span>}</TD></TRow>)}</tbody></table></Card></div>);

// ── FINANCE ──
const Fin = ()=>{const tr=REV.reduce((s,v)=>s+v,0),tc=COST_DATA.reduce((s,v)=>s+v,0),pr=tr-tc;return(<div>
  <div style={{display:"flex",gap:14,marginBottom:20,flexWrap:"wrap"}}><Stat icon="💰" label="Tržby (rok)" value={`${tr}k Kč`} color={C.gd}/><Stat icon="📉" label="Náklady" value={`${tc}k Kč`} sub="servis, pojištění, odpisy" color={C.red}/><Stat icon="📈" label="Čistý zisk" value={`${pr}k Kč`} sub={`marže ${Math.round(pr/tr*100)}%`}/><Stat icon="💳" label="Neuhrazené" value="22 400 Kč" sub="2 faktury" color={C.red}/></div>
  <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:12}}>Měsíční přehled (tis. Kč)</div><Chart data={REV} h={80}/><div style={{display:"flex",justifyContent:"space-between",marginTop:6,marginBottom:16}}>{MO.map((m,i)=><span key={i} style={{fontSize:9,color:C.g400,fontWeight:700}}>{m}</span>)}</div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(4,1fr)",gap:10}}>{[["Ø tržba/moto/měs",`${Math.round(tr/12/8)}k Kč`],["Ø cena rezervace","14 329 Kč"],["Kauce držené","85 000 Kč"],["Pojistné události","1 (12 400 Kč)"]].map(([l,v],i)=><div key={i} style={{padding:12,background:C.g100,borderRadius:12,textAlign:"center"}}><div style={{fontSize:9,color:C.g400,fontWeight:700,textTransform:"uppercase",marginBottom:4}}>{l}</div><div style={{fontSize:15,fontWeight:800,color:C.black}}>{v}</div></div>)}</div>
    <ExportBar/>
  </Card>
</div>);};

// ── ACCOUNTING ──
const Acct = ()=>(<div>
  <div style={{display:"flex",gap:14,marginBottom:20,flexWrap:"wrap"}}><Stat icon="📒" label="Rozvaha" value="12.4M Kč" sub="aktiva celkem"/><Stat icon="📊" label="Výsledovka" value="+1.2M Kč" sub="HV za rok" color={C.gdk}/><Stat icon="🏛️" label="DPH k odvodu" value="187 400 Kč" sub="Q1 2026" color={C.gold}/><Stat icon="📋" label="Daň z příjmu" value="342 000 Kč" sub="odhad 2026" color={C.blue}/></div>
  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:16}}>
    <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:12}}>📊 Výsledovka (P&L)</div>{[["Tržby z pronájmu","2 406 000 Kč",C.gdk],["Tržby z příslušenství","184 000 Kč",C.gdk],["Náklady na servis","-487 000 Kč",C.red],["Pojištění flotily","-312 000 Kč",C.red],["Odpisy","-420 000 Kč",C.red],["Mzdy","-648 000 Kč",C.red],["Provozní náklady","-284 000 Kč",C.red]].map(([l,v,c],i)=><div key={i} style={{display:"flex",justifyContent:"space-between",padding:"8px 0",borderBottom:`1px solid ${C.g200}`}}><span style={{fontSize:13,fontWeight:600,color:C.g600}}>{l}</span><span style={{fontSize:13,fontWeight:800,color:c}}>{v}</span></div>)}<div style={{display:"flex",justifyContent:"space-between",padding:"12px 0 0",marginTop:4}}><span style={{fontSize:14,fontWeight:900,color:C.black}}>Hospodářský výsledek</span><span style={{fontSize:14,fontWeight:900,color:C.gdk}}>+439 000 Kč</span></div><ExportBar/></Card>
    <Card><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:12}}>📋 Rozvaha (zjednodušená)</div><div style={{fontSize:11,fontWeight:800,color:C.gdk,marginBottom:6,textTransform:"uppercase"}}>Aktiva</div>{[["Dlouhodobý majetek (flotila)","8 200 000 Kč"],["Zásoby (sklad)","420 000 Kč"],["Pohledávky","185 000 Kč"],["Finanční majetek","3 615 000 Kč"]].map(([l,v],i)=><div key={i} style={{display:"flex",justifyContent:"space-between",padding:"6px 0",fontSize:12,color:C.g600}}><span style={{fontWeight:600}}>{l}</span><span style={{fontWeight:800,color:C.black}}>{v}</span></div>)}<div style={{borderTop:`2px solid ${C.green}`,padding:"8px 0",margin:"8px 0",display:"flex",justifyContent:"space-between"}}><span style={{fontSize:13,fontWeight:900}}>Aktiva celkem</span><span style={{fontSize:13,fontWeight:900,color:C.gdk}}>12 420 000 Kč</span></div><div style={{fontSize:11,fontWeight:800,color:C.blue,marginBottom:6,marginTop:8,textTransform:"uppercase"}}>Pasiva</div>{[["Vlastní kapitál","7 800 000 Kč"],["Výsledek hospodaření","439 000 Kč"],["Závazky","4 181 000 Kč"]].map(([l,v],i)=><div key={i} style={{display:"flex",justifyContent:"space-between",padding:"6px 0",fontSize:12,color:C.g600}}><span style={{fontWeight:600}}>{l}</span><span style={{fontWeight:800,color:C.black}}>{v}</span></div>)}<ExportBar/></Card>
  </div>
  <Card style={{marginTop:16}}><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:12}}>🏛️ Daňové přiznání — generátor</div><div style={{display:"grid",gridTemplateColumns:"repeat(3,1fr)",gap:12}}>{[["Přiznání k DPH","Kvartální / Měsíční","Generovat DPH"],["Přiznání k dani z příjmu PO","Roční za 2025","Generovat DPPO"],["Kontrolní hlášení","Měsíční dle §101c","Generovat KH"]].map(([t,s,b],i)=><div key={i} style={{padding:16,background:C.g100,borderRadius:14,textAlign:"center"}}><div style={{fontSize:22,marginBottom:6}}>📋</div><div style={{fontSize:13,fontWeight:800,color:C.black}}>{t}</div><div style={{fontSize:11,color:C.g400,fontWeight:500,marginBottom:10}}>{s}</div><Btn green style={{width:"100%",justifyContent:"center"}}>{b}</Btn></div>)}</div></Card>
</div>);

// ── DOCUMENTS ──
const Docs = ()=>(<div>
  <div style={{display:"flex",gap:8,marginBottom:16}}><Btn green>+ Nový dokument</Btn><Btn outline>📥 Import šablony</Btn></div>
  <Card style={{padding:0,overflow:"hidden"}}><table style={{width:"100%",borderCollapse:"collapse"}}><thead><TRow header><TH>Typ</TH><TH>Název</TH><TH>Poslední úprava</TH><TH>Stav</TH><TH>Akce</TH></TRow></thead><tbody>{DOCS.map(d=><TRow key={d.id}><TD><Badge l={d.type} c={C.gdk} bg="#dcfce7"/></TD><TD bold>{d.name}</TD><TD>{d.updated}</TD><TD><Badge {...STATUS[d.status]}/></TD><TD><div style={{display:"flex",gap:6}}><Btn style={{padding:"4px 12px",fontSize:10}}>✏️ Editovat</Btn><Btn style={{padding:"4px 12px",fontSize:10}}>📤 Export</Btn></div></TD></TRow>)}</tbody></table></Card>
  <Card style={{marginTop:16}}><div style={{fontSize:13,fontWeight:800,color:C.black,marginBottom:12}}>📝 Automatické generování dokumentů</div><div style={{display:"grid",gridTemplateColumns:"repeat(4,1fr)",gap:12}}>{[["Faktura","Auto-generace po platbě"],["Smlouva","Předvyplnění z rezervace"],["Předávací protokol","S fotodokumentací"],["Dobropis","Storno / refund"]].map(([t,s],i)=><div key={i} style={{padding:14,background:C.g100,borderRadius:14,textAlign:"center"}}><div style={{fontSize:20,marginBottom:4}}>📄</div><div style={{fontSize:12,fontWeight:800,color:C.black}}>{t}</div><div style={{fontSize:10,color:C.g400,fontWeight:500,marginTop:2}}>{s}</div></div>)}</div><ExportBar/></Card>
</div>);

// ── INVENTORY ──
const Inv = ()=>(<div>
  <div style={{display:"flex",gap:8,marginBottom:16}}><Btn green>+ Přidat položku</Btn><Btn outline>🛒 Objednat chybějící</Btn></div>
  <Card style={{padding:0,overflow:"hidden"}}><table style={{width:"100%",borderCollapse:"collapse"}}><thead><TRow header><TH>SKU</TH><TH>Název</TH><TH>Kategorie</TH><TH>Sklad</TH><TH>Min</TH><TH>Stav</TH><TH>Cena/ks</TH></TRow></thead><tbody>{INVENTORY.map(i=>{const lo=i.stock<=i.min;return<TRow key={i.id}><TD mono color={C.g400}>{i.sku}</TD><TD bold>{i.name}</TD><TD>{i.cat}</TD><TD bold color={lo?"#92400e":C.gdk} mono>{i.stock}</TD><TD mono>{i.min}</TD><TD>{lo?<Badge l="Doplnit!" c="#92400e" bg="#fef3c7"/>:<Badge l="OK" c={C.gdk} bg="#dcfce7"/>}</TD><TD mono color={C.gd}>{i.price.toLocaleString()} Kč</TD></TRow>})}</tbody></table></Card>
</div>);

// ── SERVICE ──
const Svc = ()=>{const items=MOTOS.filter(m=>m.nextSvc).sort((a,b)=>new Date(a.nextSvc)-new Date(b.nextSvc));return(<div>
  <div style={{display:"flex",gap:14,marginBottom:20,flexWrap:"wrap"}}><Stat icon="🔧" label="V servisu" value="1" sub="Benelli TRK" color={C.gold}/><Stat icon="📅" label="Naplánované" value="6" sub="příštích 90 dní" color={C.blue}/><Stat icon="💸" label="Servisní náklady rok" value="187k Kč" color={C.purple}/></div>
  <Card>{items.map(m=>{const d=Math.round((new Date(m.nextSvc)-new Date())/864e5),u=d<14;return<div key={m.id} style={{display:"flex",alignItems:"center",padding:"12px",background:u?"#fef3c7":C.g100,borderRadius:14,marginBottom:8,borderLeft:`4px solid ${u?C.gold:C.g200}`}}><div style={{flex:1}}><div style={{fontWeight:800,color:C.black,fontSize:14}}>{m.name}</div><div style={{color:C.g400,fontSize:11,fontWeight:600}}>{m.spz} · {m.km.toLocaleString()} km</div></div><div style={{textAlign:"right"}}><div style={{fontWeight:800,color:u?"#92400e":C.g600,fontSize:13}}>{m.nextSvc}</div><div style={{color:u?"#92400e":C.g400,fontSize:11}}>{d>0?`za ${d} dní`:"DNES!"}</div></div></div>})}</Card>
</div>);};

// ── AI COPILOT ──
const AI = ()=>{
  const[ms,sMs]=useState([{r:"ai",t:"Ahoj! Jsem tvůj AI asistent MotoGo24 Velín. Umím analyzovat výkonnost flotily, generovat reporty, psát odpovědi zákazníkům, optimalizovat ceny, predikovat poptávku, připravovat podklady pro účetnictví a státní správu. Na co se chceš zeptat?"}]);
  const[inp,sInp]=useState("");const ref=useRef(null);
  const qk=["Nejziskovější motorka?","Měsíční report únor","Predikce poptávky duben","Optimalizuj víkendové ceny","Připrav DPH přiznání","Napiš odpověď zákazníkovi","Porovnej pobočky Mezná vs Brno","Navrhni nákupní plán"];
  const send=(t)=>{const m=t||inp;if(!m.trim())return;sMs(p=>[...p,{r:"user",t:m}]);sInp("");
    setTimeout(()=>{let r;
      if(m.includes("zisk")||m.includes("vydělává"))r="📊 **Analýza ziskovosti (březen 2026):**\n\n🥇 KTM 1290 SA — čistý zisk 140k Kč (util. 88%)\n🥈 CF MOTO 800 MT — čistý zisk 114k Kč (util. 82%)\n🥉 BMW R 1200 GS — čistý zisk 116k Kč (util. 78%)\n\n⚠️ Triumph Tiger 1200 je vyřazena a generuje nulový příjem při odpisech 35k/měs. Doporučuji prodej nebo intenzivní opravu.\n\nROI flotily: 23.4% anualizovaně.";
      else if(m.includes("report"))r="📋 **Report únor 2026:**\n\n• Tržby: 487 200 Kč (+12% MoM)\n• Čistý zisk: 198 400 Kč (marže 40.7%)\n• Rezervací: 34 (31 dokončených, storno 8.8%)\n• Ø objednávka: 14 329 Kč\n• Top motorka: KTM 1290 SA (14/28 dnů)\n• Provozovna Mezná: 312k | Brno: 175k\n\nChceš export do PDF nebo XLSX?";
      else if(m.includes("predikce")||m.includes("poptáv"))r="📈 **Predikce duben 2026:**\n\n• Celková poptávka: +45% vs březen\n• Adventure segment: +62% (peak sezóny)\n• Víkendy: 95% kapacity — doporučuji surge pricing +15%\n• Optimální rozložení: 5 motorek Mezná, 3 Brno\n\nNa základě historických dat 2024-2025 a sezónních koeficientů. Přesnost modelu: 87%.";
      else if(m.includes("DPH")||m.includes("daň"))r="🏛️ **Podklady DPH Q1 2026:**\n\n• Základ daně (výstupy): 1 203 000 Kč\n• DPH 21%: 252 630 Kč\n• Odpočet (vstupy): 65 230 Kč\n• K odvodu: 187 400 Kč\n• Termín podání: 25. 4. 2026\n\nPřipravím XML export pro EPO?";
      else if(m.includes("cen")||m.includes("optim"))r="💰 **Cenová optimalizace:**\n\n• Pátek: +15% (peak demand)\n• Neděle: -8% (generování poptávky)\n• Sezónní příplatek IV-IX: +20%\n• Niken GT: -5% (nižší utiliz. 71%→cíl 80%)\n\nOdhad dopadu: +34 000 Kč/měsíc bez poklesu obsazenosti.";
      else if(m.includes("pobočk")||m.includes("srovn"))r="🏢 **Srovnání poboček:**\n\n| | Mezná | Brno |\n|---|---|---|\n| Motorek | 5 | 3 |\n| Tržby/měs | 481k | 215k |\n| Ø utiliz. | 59% | 49% |\n| Zisk/moto | 72k | 58k |\n\nMezná výrazně profitabilnější. Brno potřebuje marketingový push nebo přesun 1 stroje do Mezné.";
      else if(m.includes("odpověď")||m.includes("zákazník"))r="✉️ **Odpověď pro Jana Nováka:**\n\n\"Dobrý den, Jene!\n\nProdloužení BMW R 1200 GS o 2 dny je možné — motorka je volná. Nová celková cena pronájmu bude 25 248 Kč.\n\nPotvrďte prosím odpovědí na tuto zprávu.\n\nDěkujeme za důvěru!\nTým MotoGo24\"\n\nOdeslat přes web / WhatsApp / email?";
      else r="Rozumím. Na základě dat z velínu připravím analýzu. Potřebuješ něco konkrétního k flotile, financím, zákazníkům nebo dokumentům?";
      sMs(p=>[...p,{r:"ai",t:r}]);
    },800);
  };
  useEffect(()=>{ref.current?.scrollIntoView({behavior:"smooth"});},[ms]);
  return(<div style={{display:"flex",flexDirection:"column",height:"calc(100vh - 140px)"}}>
    <div style={{flex:1,overflowY:"auto",marginBottom:12}}>{ms.map((m,i)=><div key={i} style={{display:"flex",justifyContent:m.r==="user"?"flex-end":"flex-start",marginBottom:10}}><div style={{maxWidth:"78%",padding:"12px 16px",borderRadius:m.r==="user"?"18px 18px 4px 18px":"18px 18px 18px 4px",background:m.r==="user"?C.gp:C.white,color:C.black,fontSize:13,lineHeight:1.6,whiteSpace:"pre-wrap",boxShadow:C.shadow,border:m.r==="user"?`2px solid ${C.green}33`:"none"}}>{m.r==="ai"&&<div style={{fontSize:10,color:C.gdk,fontWeight:800,marginBottom:6}}>🤖 AI Copilot</div>}{m.t}</div></div>)}<div ref={ref}/></div>
    <div style={{display:"flex",gap:6,flexWrap:"wrap",marginBottom:10}}>{qk.map((a,i)=><button key={i} onClick={()=>send(a)} style={{padding:"5px 12px",borderRadius:50,fontSize:11,border:`2px solid ${C.g200}`,background:C.white,color:C.g600,cursor:"pointer",fontWeight:700,fontFamily:"inherit"}}>{a}</button>)}</div>
    <div style={{display:"flex",gap:8}}><input value={inp} onChange={e=>sInp(e.target.value)} onKeyDown={e=>e.key==="Enter"&&send()} placeholder="Zeptej se AI copilota…" style={{flex:1,padding:"12px 18px",borderRadius:50,border:`2px solid ${C.g200}`,background:C.white,color:C.black,fontSize:14,outline:"none",fontFamily:"inherit"}}/><Btn green onClick={()=>send()}>Odeslat</Btn></div>
  </div>);
};

// ── PLACEHOLDER ──
const PH = ({title,icon,features})=>(<Card style={{textAlign:"center",padding:40}}><div style={{fontSize:56,marginBottom:12}}>{icon}</div><h2 style={{color:C.black,margin:"0 0 8px",fontSize:20,fontWeight:900}}>{title}</h2><p style={{color:C.g400,margin:"0 0 20px",fontSize:13,fontWeight:500}}>Modul připravený pro backend</p><div style={{display:"flex",flexWrap:"wrap",gap:8,justifyContent:"center"}}>{features.map((f,i)=><div key={i} style={{padding:"7px 16px",background:C.g100,borderRadius:50,fontSize:12,color:C.g600,fontWeight:700,border:`1px solid ${C.g200}`}}>{f}</div>)}</div></Card>);

const VIEWS = {
  dash:Dash, fleet:Fleet, book:Book, fin:Fin, acct:Acct, docs:Docs, inv:Inv, svc:Svc, ai:AI,
  crm:()=><PH title="CRM — Zákazníci" icon="👥" features={["Databáze","Historie pronájmů","Reliability skóre","Blacklist / VIP","Gear velikosti","Doklady a ŘP","Segmentace","Automatické follow-up"]}/>,
  msg:()=><PH title="Omnichannel Inbox" icon="💬" features={["Web chat","WhatsApp","Email","Instagram DM","FB Messenger","SMS","AI auto-reply","Šablony","Prioritizace"]}/>,
  cms:()=><PH title="Web CMS" icon="🌐" features={["Editace textů","Editace cen","SEO","Promo bannery","Slevové kódy","Feature toggles","A/B testing","Maintenance mode","Proměnné webu"]}/>,
  stats:()=><PH title="Statistiky & Predikce" icon="📊" features={["KPI dashboard","Heatmapy poptávky","Srovnání provozoven","Sezónní trendy","Prediktivní modely","Export PDF/XLSX/CSV","Výkonnost strojů","Custom reporty"]}/>,
  buy:()=><PH title="Nákupy & Plánování" icon="🛒" features={["Auto-objednávky","Schvalování","Dodavatelé","Historie","Cenové srovnání","Budget tracking","Predikce spotřeby","Nákupní plány"]}/>,
  gov:()=><PH title="Státní správa" icon="🏛️" features={["DPH přiznání","Kontrolní hlášení","Daň z příjmu PO","EET / eKasa","ČSSZ hlášení","Datové schránky","ARES napojení","EPO export","XML / PDF generátor"]}/>,
};

// ═══════════════════════════════════════════════════════════
// MAIN APP
// ═══════════════════════════════════════════════════════════
export default function Velin(){
  const[v,sV]=useState("dash");
  const[col,sCol]=useState(false);
  const[time,sT]=useState(new Date());
  useEffect(()=>{const t=setInterval(()=>sT(new Date()),1000);return()=>clearInterval(t);},[]);
  const View=VIEWS[v]||Dash;
  const label=NAV.find(n=>n.id===v)?.l||"Velín";
  const unr=MSGS.filter(m=>m.unread).length;

  return(
    <div style={{display:"flex",height:"100vh",background:C.bg,fontFamily:"'Montserrat','Segoe UI',sans-serif",color:C.black,overflow:"hidden"}}>
      <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800;900&display=swap" rel="stylesheet"/>

      {/* SIDEBAR */}
      <div style={{width:col?62:230,background:C.dark,display:"flex",flexDirection:"column",transition:"width .3s",flexShrink:0,overflow:"hidden"}}>
        <div style={{padding:col?"16px 8px":"20px",borderBottom:"1px solid rgba(255,255,255,.08)",display:"flex",alignItems:"center",gap:12,cursor:"pointer"}} onClick={()=>sCol(!col)}>
          <div style={{flexShrink:0}}><Logo size={col?38:44}/></div>
          {!col&&<div><div style={{fontSize:16,fontWeight:900,color:C.white,letterSpacing:-.5}}>MOTO GO 24</div><div style={{fontSize:9,fontWeight:700,color:"rgba(255,255,255,.4)",letterSpacing:3,textTransform:"uppercase",marginTop:2}}>Velín</div></div>}
        </div>
        <nav style={{flex:1,padding:"10px 6px",overflowY:"auto"}}>
          {NAV.map(n=>{const a=v===n.id,u=n.id==="msg"?unr:0;return(
            <button key={n.id} onClick={()=>sV(n.id)} style={{width:"100%",display:"flex",alignItems:"center",gap:10,padding:col?"9px 0":"9px 14px",justifyContent:col?"center":"flex-start",borderRadius:14,border:"none",cursor:"pointer",marginBottom:1,fontSize:13,fontWeight:a?800:600,background:a?"rgba(116,251,113,.12)":"transparent",color:a?C.green:"rgba(255,255,255,.5)",borderLeft:a?`3px solid ${C.green}`:"3px solid transparent",transition:"all .2s",fontFamily:"inherit"}}>
              <span style={{fontSize:16,flexShrink:0}}>{n.i}</span>
              {!col&&<span style={{flex:1,textAlign:"left"}}>{n.l}</span>}
              {!col&&u>0&&<span style={{background:C.red,color:C.white,fontSize:9,fontWeight:900,padding:"2px 7px",borderRadius:50}}>{u}</span>}
            </button>
          );})}
        </nav>
        {!col&&<div style={{padding:"14px 16px",borderTop:"1px solid rgba(255,255,255,.08)",display:"flex",alignItems:"center",gap:10}}>
          <div style={{width:32,height:32,borderRadius:"50%",background:C.green,display:"flex",alignItems:"center",justifyContent:"center",fontSize:14,fontWeight:900,color:C.dark}}>A</div>
          <div><div style={{fontSize:12,fontWeight:700,color:C.white}}>Admin</div><div style={{fontSize:10,color:"rgba(255,255,255,.35)",fontWeight:500}}>Správce systému</div></div>
        </div>}
      </div>

      {/* MAIN */}
      <div style={{flex:1,display:"flex",flexDirection:"column",overflow:"hidden"}}>
        <div style={{padding:"12px 28px",borderBottom:`1px solid ${C.g200}`,display:"flex",alignItems:"center",justifyContent:"space-between",background:C.white,flexShrink:0}}>
          <div style={{display:"flex",alignItems:"center",gap:12}}>
            <h1 style={{margin:0,fontSize:20,fontWeight:900,color:C.black}}>{label}</h1>
          </div>
          <div style={{display:"flex",alignItems:"center",gap:20}}>
            <div style={{fontSize:12,color:C.g400,fontWeight:600}}>{time.toLocaleDateString("cs-CZ",{weekday:"long",day:"numeric",month:"long",year:"numeric"})}</div>
            <div style={{fontSize:14,color:C.gdk,fontWeight:800,letterSpacing:1}}>{time.toLocaleTimeString("cs-CZ")}</div>
            <div style={{width:8,height:8,borderRadius:"50%",background:C.green,boxShadow:`0 0 8px ${C.green}`}} title="Online"/>
          </div>
        </div>
        <div style={{flex:1,overflowY:"auto",padding:24}}><View/></div>
      </div>
    </div>
  );
}
