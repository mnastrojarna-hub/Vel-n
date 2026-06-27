<?php
// ===== MotoGo24 Web PHP — /testovani =====
// Onboarding beta testerů mobilní aplikace (uzavřené testování Google Play).
// Dva kroky, které Google vyžaduje a které NELZE obejít ani automatizovat:
//   1) self-join do Google Group testerů (skupina = „kdokoli se může připojit")
//   2) opt-in do testu („Become a tester") → instalace z Google Play
// Stránka je noindex, česky, bez buildu. QR jsou statické SVG v gfx/.
// UI/UX bubliny pro stažení appky v hlavičce zůstává beze změny — tohle je
// samostatná landing stránka, na kterou se odkazuje přímo (motogo24.cz/testovani).

$groupUrl = TESTER_GROUP_URL;                 // krok 1
$testUrl  = PLAY_STORE_URL;                   // krok 2 (closed testing opt-in)
$liveUrl  = PLAY_STORE_LIVE_URL;              // veřejný Store (po ostrém spuštění)
$gUrl = htmlspecialchars($groupUrl, ENT_QUOTES, 'UTF-8');
$tUrl = htmlspecialchars($testUrl, ENT_QUOTES, 'UTF-8');
$lUrl = htmlspecialchars($liveUrl, ENT_QUOTES, 'UTF-8');
$qrG  = BASE_URL . '/gfx/qr-testeri-skupina.svg';
$qrT  = BASE_URL . '/gfx/qr-google-play.svg';
$gSub = 'motogo24-testeri+subscribe@googlegroups.com'; // e-mail self-join fallback

$content = <<<HTML
<main id="content"><div class="container">
<div class="mg-testeri" data-mg-testeri>
<style>
.mg-testeri{max-width:760px;margin:1.5rem auto 2.5rem;color:#1a2e22}
.mg-testeri h1{font-size:1.7rem;line-height:1.2;margin:0 0 .5rem}
.mg-t-lead{font-size:1rem;color:#3a4d42;margin:0 0 1.4rem}
.mg-t-hint{display:none;background:#fff7e6;border:1px solid #f0d28a;color:#7a5b12;border-radius:10px;padding:.7rem .9rem;font-size:.85rem;margin:0 0 1.2rem}
.mg-testeri.not-android .mg-t-hint{display:block}
.mg-t-steps{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:1rem;counter-reset:step}
.mg-t-step{position:relative;background:#fff;border:1px solid #d4e6df;border-radius:14px;padding:1.1rem 1.2rem 1.2rem;box-shadow:0 6px 18px rgba(26,46,34,.06)}
.mg-t-step::before{counter-increment:step;content:counter(step);position:absolute;top:-12px;left:1.1rem;width:30px;height:30px;border-radius:50%;background:#1a2e22;color:#74fb71;font-weight:800;font-size:1rem;display:flex;align-items:center;justify-content:center}
.mg-t-step h2{font-size:1.1rem;margin:.4rem 0 .35rem}
.mg-t-step p{font-size:.9rem;color:#3a4d42;margin:0 0 .85rem}
.mg-t-cta{display:inline-flex;align-items:center;gap:.45rem;background:#1a2e22;color:#fff;font-weight:700;font-size:.95rem;text-decoration:none;padding:.7rem 1.1rem;border-radius:10px;transition:background .15s}
.mg-t-cta:hover{background:#0d6e0d;color:#fff}
.mg-t-cta.is-done{background:#5edc5a;color:#0b0b0b}
.mg-t-alt{font-size:.82rem;color:#4a6b5a;line-height:1.55;margin:.85rem 0 0;padding-top:.85rem;border-top:1px dashed #cfe3d8}
.mg-t-cta-alt{background:#eafaf0;color:#0d6e0d;border:1px solid #bfe6cd;font-size:.85rem;padding:.5rem .9rem;margin-top:.5rem}
.mg-t-cta-alt:hover{background:#d8f3e3;color:#0d6e0d}
.mg-t-warn{background:#fff7e6;border:1px solid #f0d28a;border-radius:10px;padding:.6rem .8rem;font-size:.85rem;line-height:1.55;color:#5a4a1a;margin:0 0 .85rem}
.mg-t-warn em{font-style:italic}
.mg-t-row{display:flex;gap:1.1rem;align-items:center;flex-wrap:wrap}
.mg-t-qr{width:128px;height:128px;flex:0 0 auto;border:1px solid #e3ece8;border-radius:10px;background:#fff;display:none}
.mg-testeri.not-android .mg-t-qr{display:block}
.mg-t-done-badge{display:none;margin-left:.5rem;font-size:.8rem;font-weight:700;color:#0d6e0d}
.mg-testeri.step1-done .mg-t-step[data-step="1"] .mg-t-done-badge{display:inline}
.mg-t-once{background:#eafaf0;border:1px solid #bfe6cd;color:#1a5e2e;border-radius:10px;padding:.6rem .85rem;font-size:.83rem;line-height:1.5;margin:0 0 1.4rem}
.mg-t-retry{display:none;margin:.85rem 0 0;padding:.6rem .8rem;background:#f4f9f6;border:1px dashed #bcd6c8;border-radius:9px;font-size:.82rem;line-height:1.5;color:#3a4d42}
.mg-testeri.step1-done .mg-t-step[data-step="2"] .mg-t-retry{display:block}
.mg-t-foot{margin-top:1.6rem;font-size:.82rem;color:#52655a;line-height:1.55}
.mg-t-foot a{color:#0d6e0d;font-weight:700}
@media (max-width:560px){.mg-testeri h1{font-size:1.4rem}.mg-t-qr{width:108px;height:108px}}
</style>

<h1>Staň se beta testerem aplikace MotoGo24</h1>
<p class="mg-t-lead">Aplikace je v uzavřeném testování Google Play. Stačí dva kroky — zabere to minutu. Postupuj na <strong>telefonu s Androidem</strong> a přihlas se stejným Google účtem, jaký máš v Obchodě Play.</p>

<div class="mg-t-hint">📱 Tyto kroky proveď na <strong>Android telefonu</strong>. Na počítači nebo iPhonu otevři stránku přes přiložený QR kód na Androidu.</div>

<p class="mg-t-once">✅ <strong>QR stačí naskenovat jednou.</strong> Oba kroky jsou tady na jedné stránce a zařazení mezi testery je jednorázové — jakmile appku jednou nainstaluješ, najdeš ji pak <strong>přímo v Google Play</strong> a QR ani odkaz už znovu nepotřebuješ.</p>

<ol class="mg-t-steps">
  <li class="mg-t-step" data-step="1">
    <h2>Přidej se do skupiny testerů<span class="mg-t-done-badge">✓ hotovo</span></h2>
    <p>Otevři skupinu. Google nahoře ukáže název <strong>„MotoGo24 Testeri"</strong> a hned pod ním <strong>šedě orámované tlačítko „Přidat se ke skupině"</strong> — na to klepni.</p>
    <p class="mg-t-warn">⚠️ Možná uvidíš zákazovou ikonu a hlášku <em>„Pro přístup k tomuto obsahu nemáte oprávnění"</em>. <strong>Toho se nelekej — je to normální pro nečleny.</strong> Stačí klepnout na <strong>„Přidat se ke skupině"</strong> úplně nahoře (nebo na modrý odkaz <em>„se připojit ke skupině"</em> uprostřed textu). Musíš být přihlášený <strong>stejným Google účtem jako v Obchodě Play</strong>.</p>
    <div class="mg-t-row">
      <a class="mg-t-cta" data-step1-btn href="{$gUrl}" target="_blank" rel="noopener">Přidat se ke skupině</a>
      <img class="mg-t-qr" src="{$qrG}" alt="QR kód pro připojení do skupiny testerů MotoGo24" width="128" height="128" loading="lazy">
    </div>
    <p class="mg-t-alt">Nevidíš tlačítko „Připojit se"? Přidej se <strong>e-mailem</strong> — otevře se rozepsaná zpráva, kterou jen <strong>odešleš</strong> (předmět ani text neměň):<br>
      <a class="mg-t-cta mg-t-cta-alt" data-step1-btn href="mailto:{$gSub}?subject=Subscribe">Přidat se e-mailem</a>
    </p>
  </li>
  <li class="mg-t-step" data-step="2">
    <h2>Nainstaluj appku z Google Play</h2>
    <p>Jsi tester — appku máš rovnou v Obchodě. Klepni na tlačítko níž (nebo naskenuj <strong>QR kód</strong>), případně v <strong>Obchodě Play</strong> nahoře vyhledej <strong>„MotoGo24"</strong> a dej <strong>Instalovat</strong>.</p>
    <div class="mg-t-row">
      <a class="mg-t-cta" href="{$lUrl}" target="_blank" rel="noopener">Otevřít MotoGo24 v Google Play</a>
      <img class="mg-t-qr" src="{$qrT}" alt="QR kód pro stažení aplikace MotoGo24 z Google Play" width="128" height="128" loading="lazy">
    </div>
    <p class="mg-t-retry">⏳ Appku v Obchodě hned nevidíš? Po přidání do skupiny chvíli trvá, než tě Google uvidí jako testera (obvykle <strong>pár minut</strong>, výjimečně až pár hodin). Dej si pauzu a zkus to znovu — objeví se sama, QR už skenovat nemusíš.</p>
  </li>
</ol>

<p class="mg-t-foot">Něco nefunguje? Napiš nám na <a href="mailto:info@motogo24.cz">info&#64;motogo24.cz</a> a pošli e-mail, kterým se přihlašuješ ke Google účtu — pomůžeme ti přístup dořešit ručně.<br>
Až bude appka veřejně spuštěná, najdeš ji v <a href="{$lUrl}" target="_blank" rel="noopener">Obchodě Google Play</a> bez testování.</p>

<script>
(function(){
  var root=document.querySelector('[data-mg-testeri]');
  if(!root)return;
  if(!/Android/i.test(navigator.userAgent||'')) root.classList.add('not-android');
  try{ if(localStorage.getItem('mg24_step1')==='1') root.classList.add('step1-done'); }catch(e){}
  var btns=root.querySelectorAll('[data-step1-btn]');
  Array.prototype.forEach.call(btns,function(b){
    b.addEventListener('click',function(){
      try{localStorage.setItem('mg24_step1','1');}catch(e){}
      root.classList.add('step1-done');
    });
  });
})();
</script>
</div>
</div></main>
HTML;

renderPage('Staň se testerem aplikace MotoGo24', $content, '/testovani', [
    'robots'      => 'noindex,follow',
    'description' => 'Přihlas se do beta testování mobilní aplikace MotoGo24 ve dvou krocích — připoj se do skupiny testerů a nainstaluj appku z Google Play.',
]);
