// ===== MotoGo24 Web — Homepage =====

var MG = window.MG || {};
window.MG = MG;

MG.route('/', function(app){
  // Start with static shell, fill dynamic parts after
  app.innerHTML = MG._homeShell();
  MG._loadHomeMotos();
  MG._loadHomeBlog();
});

MG._homeShell = function(){
  // Hero banner
  var banner = '<div class="banner">' +
    '<img fetchpriority="high" alt="Půjčovna motorek Vysočina Motogo24" src="gfx/hero-banner.jpg">' +
    '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' +
      '<p><strong>Půjčovna motorek</strong> na Vysočině</p><p>&nbsp;</p>' +
      '<p>Půjč si motorku na Vysočině snadno online.<br>Vyber si z <strong>cestovních, sportovních i enduro</strong> modelů.<br>Rezervace s <strong>platbou kartou</strong> a <strong>rychlým převzetím</strong>.</p><p>&nbsp;</p>' +
      '<p><a class="btn btngreen" href="#/katalog">VYBER SI MOTORKU</a> <a class="btn btndark" href="#/jak-pujcit">JAK TO FUNGUJE</a></p>' +
    '</div></div></div></div>';

  // Signpost (6 cards)
  var signposts = [
    {icon:'gfx/ico-katalog.svg', title:'<strong>Katalog</strong> motorek', text:'Prohlédněte si naši nabídku <strong>motorek na pronájem</strong> – od sportovních po cestovní modely.', btn:'KATALOG MOTOREK', href:'/katalog'},
    {icon:'gfx/ico-jak.svg', title:'<strong>Jak si půjčit</strong> motorku', text:'Jednoduchý proces: vyberte <strong>motorku k zapůjčení</strong>, rezervujte, vyjeďte.', btn:'JAK SI PŮJČIT MOTORKU', href:'/jak-pujcit'},
    {icon:'gfx/ico-rezervace.svg', title:'<strong>Online rezervace</strong> motorky', text:'Zarezervujte si <strong>motorku na pronájem</strong> přes snadný systém.', btn:'REZERVOVAT MOTORKU', href:'/rezervace'},
    {icon:'gfx/ico-kontakt.svg', title:'<strong>Kontakty</strong> a mapa', text:'Navštivte naši <strong>půjčovnu motorek v Pelhřimově</strong> nebo nás kontaktujte.', btn:'KONTAKT', href:'/kontakt'},
    {icon:'gfx/ico-faq.svg', title:'Často kladené <strong>dotazy</strong>', text:'Nejčastější dotazy k <strong>půjčení motorky</strong> přehledně.', btn:'ČASTÉ DOTAZY', href:'/jak-pujcit/faq'},
    {icon:'gfx/ico-trasy.svg', title:'Motocyklové <strong>výlety</strong>', text:'Objevte nejlepší <strong>motocyklové trasy v Česku</strong> pro turisty.', btn:'MOTOCYKLOVÉ TRASY', href:'/blog'}
  ];
  var signHtml = '<section aria-labelledby="signpost"><div class="gr3">';
  signposts.forEach(function(s){
    signHtml += '<a class="gbox" href="#' + s.href + '">' +
      '<div class="gr2"><div class="gbox-img"><img src="' + s.icon + '" class="icon" alt="' + s.btn + '" loading="lazy"></div><div>' +
      '<h3><p>' + s.title + '</p></h3><p>' + s.text + '</p>' +
      '<div class="btn btngreen-small">' + s.btn + '</div></div></div></a>';
  });
  signHtml += '</div></section>';

  // Motorky placeholder
  var motosSection = '<section aria-labelledby="catalogue"><h2>Naše motorky k pronájmu na Vysočině</h2>' +
    '<p>Prohlédněte si nabídku cestovních, sportovních a enduro z naší <strong>půjčovny motorek na Vysočině</strong>.</p><p>&nbsp;</p>' +
    '<div id="home-motos" class="gr4"><div class="loading-overlay"><span class="spinner"></span> Načítám motorky...</div></div>' +
    '<p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="#/katalog">KATALOG MOTOREK</a></p></section>';

  // Process steps
  var steps = [
    {icon:'gfx/ico-step1.svg', title:'1. Vyber', text:'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.'},
    {icon:'gfx/ico-step2.svg', title:'2. Rezervuj', text:'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.'},
    {icon:'gfx/ico-step3.svg', title:'3. Převzetí', text:'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.'},
    {icon:'gfx/ico-step4.svg', title:'4. Užij jízdu', text:'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.'}
  ];
  var processHtml = '<section aria-labelledby="process"><h2>Jak probíhá půjčení motorky na Vysočině</h2><div class="gr4">';
  steps.forEach(function(s){
    processHtml += MG.renderWbox(s.icon, s.title, s.text);
  });
  processHtml += '</div></section>';

  // FAQ
  var faqItems = [
    {q:'Jak si mohu rezervovat motorku?', a:'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.'},
    {q:'Můžu si motorku půjčit i bez předchozí rezervace?', a:'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit – online, telefonicky, e-mailem nebo přes sociální sítě.'},
    {q:'Musím složit kauci?', a:'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.'},
    {q:'Můžu odcestovat s motorkou do zahraničí?', a:'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).'}
  ];
  var faqHtml = MG.renderFaqSection('Často kladené otázky', faqItems, '/jak-pujcit/faq');

  // CTA
  var ctaHtml = MG.renderCta('Rezervuj svou motorku online',
    'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
    [
      {label:'REZERVOVAT MOTORKU', href:'/rezervace', cls:'btndark pulse'},
      {label:'Dárkový poukaz', href:'/poukazy', cls:'btndark'},
      {label:'Tipy na trasy', href:'/blog', cls:'btndark'}
    ]);

  // Blog placeholder
  var blogHtml = '<section aria-labelledby="blog"><h2>Blog a tipy</h2>' +
    '<div id="home-blog" class="gr3"><div class="loading-overlay"><span class="spinner"></span> Načítám články...</div></div>' +
    '<p>&nbsp;</p><p class="text-center"><a class="btn btngreen" href="#/blog">ČÍST VÍCE V BLOGU</a></p></section>';

  return '<main id="content"><h1 class="sr-only">Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop</h1><div class="container">' +
    signHtml + motosSection + processHtml + faqHtml + ctaHtml + blogHtml +
    '</div></main>';
};

// Wrap with banner (special for homepage)
var _origHomeRoute = MG.routes['/'];
MG.routes['/'] = function(app){
  _origHomeRoute(app);
  // Prepend banner before main
  var main = app.querySelector('main');
  if(main){
    var bannerDiv = document.createElement('div');
    bannerDiv.innerHTML = '<div class="banner">' +
      '<img fetchpriority="high" alt="Půjčovna motorek Vysočina" src="gfx/hero-banner.jpg">' +
      '<div class="banner-wrapper"><div class="container"><div class="banner-caption">' +
        '<p><strong>Půjčovna motorek</strong> na Vysočině</p><p>&nbsp;</p>' +
        '<p>Půjč si motorku na Vysočině snadno online.<br>Vyber si z <strong>cestovních, sportovních i enduro</strong> modelů.<br>Rezervace s <strong>platbou kartou</strong> a <strong>rychlým převzetím</strong>.</p><p>&nbsp;</p>' +
        '<p><a class="btn btngreen" href="#/katalog">VYBER SI MOTORKU</a> <a class="btn btndark" href="#/jak-pujcit">JAK TO FUNGUJE</a></p>' +
      '</div></div></div></div>';
    app.insertBefore(bannerDiv.firstChild, main);
  }
};

MG._loadHomeMotos = async function(){
  var el = document.getElementById('home-motos');
  if(!el) return;
  var motos = await MG.fetchMotos();
  if(!motos.length){ el.innerHTML = '<p>Momentálně nemáme žádné motorky v nabídce.</p>'; return; }
  var html = '';
  motos.slice(0, 4).forEach(function(m){
    html += '<section aria-labelledby="catalogue">' + MG.renderMotoCard(m) + '</section>';
  });
  el.innerHTML = html;
};

MG._loadHomeBlog = async function(){
  var el = document.getElementById('home-blog');
  if(!el) return;
  var posts = await MG.fetchCmsPages();
  if(!posts.length){ el.innerHTML = '<p>Zatím nemáme žádné články.</p>'; return; }
  var html = '';
  posts.slice(0, 3).forEach(function(p){ html += MG.renderBlogCard(p); });
  el.innerHTML = html;
};
