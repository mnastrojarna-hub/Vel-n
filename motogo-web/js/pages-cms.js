// ===== MotoGo24 Web — CMS pages (VOP, GDPR, Smlouva) =====

var MG = window.MG || {};
window.MG = MG;

// Generic CMS page renderer
MG._renderCmsPage = async function(app, slug, title, bcItems){
  var bc = MG.renderBreadcrumb(bcItems);
  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><div class="loading-overlay"><span class="spinner"></span> Načítám obsah...</div></div></div></main>';

  var page = await MG.fetchCmsPage(slug);
  var content = '';
  if(page && page.content){
    content = page.content;
  } else {
    content = '<p>Obsah se připravuje. Kontaktujte nás pro více informací.</p>' +
      '<p>&nbsp;</p><p><a class="btn btngreen" href="#/kontakt">KONTAKTOVAT NÁS</a></p>';
  }

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><h1>' + title + '</h1>' + content + '</div></div></main>';
};

// ===== OBCHODNÍ PODMÍNKY =====
MG.route('/obchodni-podminky', function(app){
  MG._renderCmsPage(app, 'obchodni-podminky', 'Obchodní podmínky',
    [{label:'Domů',href:'/'},'Obchodní podmínky']);
});

// ===== GDPR =====
MG.route('/gdpr', function(app){
  MG._renderCmsPage(app, 'gdpr', 'Zásady ochrany osobních údajů',
    [{label:'Domů',href:'/'},'GDPR']);
});

// ===== SMLOUVA O PRONÁJMU =====
MG.route('/smlouva', function(app){
  MG._renderCmsPage(app, 'smlouva-o-pronajmu', 'Smlouva o pronájmu',
    [{label:'Domů',href:'/'},'Smlouva o pronájmu']);
});

// ===== MAPA STRÁNEK =====
MG.route('/mapa-stranek', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Mapa stránek']);
  var links = [
    {href:'/', label:'Úvodní stránka'},
    {href:'/pujcovna-motorek', label:'Půjčovna motorek'},
    {href:'/katalog', label:'Katalog motorek'},
    {href:'/katalog/cestovni', label:'  Cestovní motorky'},
    {href:'/katalog/detske', label:'  Dětské motorky'},
    {href:'/jak-pujcit', label:'Jak si půjčit motorku'},
    {href:'/jak-pujcit/postup', label:'  Postup půjčení'},
    {href:'/jak-pujcit/pristaveni', label:'  Přistavení motocyklu'},
    {href:'/jak-pujcit/vyzvednuti', label:'  Vyzvednutí motocyklu'},
    {href:'/jak-pujcit/co-v-cene', label:'  Co je v ceně'},
    {href:'/jak-pujcit/dokumenty', label:'  Dokumenty a návody'},
    {href:'/jak-pujcit/faq', label:'  Často kladené dotazy'},
    {href:'/poukazy', label:'Poukazy'},
    {href:'/blog', label:'Blog'},
    {href:'/kontakt', label:'Kontakt'},
    {href:'/rezervace', label:'Rezervace'},
    {href:'/obchodni-podminky', label:'Obchodní podmínky'},
    {href:'/gdpr', label:'GDPR'},
    {href:'/smlouva', label:'Smlouva o pronájmu'}
  ];
  var html = '<ul>';
  links.forEach(function(l){
    html += '<li><a href="#' + l.href + '">' + l.label + '</a></li>';
  });
  html += '</ul>';

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent"><h1>Mapa stránek</h1>' + html + '</div></div></main>';
});
