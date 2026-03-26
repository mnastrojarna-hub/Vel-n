// ===== MotoGo24 Web — Shared Layout (Header + Footer) =====

var MG = window.MG || {};
window.MG = MG;

MG.PHONE = '+420 774 256 271';
MG.PHONE_LINK = 'tel:+420774256271';
MG.EMAIL_USER = 'info';
MG.EMAIL_DOMAIN = 'motogo24.cz';
MG.ADDRESS = 'Mezná 9, 393 01 Pelhřimov';
MG.FB_URL = 'https://www.facebook.com/profile.php?id=61581614672839';
MG.IG_URL = 'https://www.instagram.com/moto.go24/';
MG.LOGO_SVG = 'gfx/logo.svg';

MG.menuItems = [
  {label:'Půjčovna motorek', route:'/pujcovna-motorek'},
  {label:'Katalog motorek', route:'/katalog', children:[
    {label:'Cestovní motorky', route:'/katalog/cestovni'},
    {label:'Dětské motorky', route:'/katalog/detske'}
  ]},
  {label:'Jak si půjčit motorku', route:'/jak-pujcit', children:[
    {label:'Postup půjčení', route:'/jak-pujcit/postup'},
    {label:'Přistavení motocyklu', route:'/jak-pujcit/pristaveni'},
    {label:'Vyzvednutí motocyklu', route:'/jak-pujcit/vyzvednuti'},
    {label:'Co je v ceně', route:'/jak-pujcit/co-v-cene'},
    {label:'Dokumenty a návody', route:'/jak-pujcit/dokumenty'},
    {label:'Často kladené dotazy', route:'/jak-pujcit/faq'}
  ]},
  {label:'Poukazy', route:'/poukazy'},
  {label:'Blog', route:'/blog'},
  {label:'Kontakt', route:'/kontakt'}
];

MG.renderHeader = function(){
  var nav = '';
  MG.menuItems.forEach(function(item){
    var hasSub = item.children && item.children.length;
    var arrow = hasSub ? ' <img src="gfx/arrow-down.svg" alt="" loading="lazy" class="menu-arrow">' : '';
    nav += '<li' + (hasSub ? ' class="has-sub"' : '') + '>';
    nav += '<a data-route="' + item.route + '" href="#' + item.route + '">' + item.label + arrow + '</a>';
    if(hasSub){
      nav += '<ul class="submenu bs">';
      item.children.forEach(function(ch){
        nav += '<li><a data-route="' + ch.route + '" href="#' + ch.route + '">' + ch.label + '</a></li>';
      });
      nav += '</ul>';
    }
    nav += '</li>';
  });

  return '<header>' +
    '<ul class="focus"><li><a href="#main-menu">PŘEJDI NA HLAVNÍ MENU</a></li><li><a href="#content">PŘEJDI NA OBSAH</a></li><li><a href="#footer">PŘEJDI NA KONTAKT</a></li></ul>' +
    '<div class="header"><div class="container dfcs">' +
      '<div class="header-logo"><a href="#/" aria-label="Motogo24"><img src="' + MG.LOGO_SVG + '" alt="Půjčovna motorek Vysočina Motogo24" loading="lazy"></a></div>' +
      '<div class="header-phone"><p><a href="' + MG.PHONE_LINK + '" aria-label="Zavolejte nám"><img alt="Zavolejte" src="gfx/telefon-header.svg" loading="lazy"></a>&nbsp;<a href="' + MG.PHONE_LINK + '">' + MG.PHONE + '</a></p></div>' +
      '<div class="header-menu dfje">' +
        '<button class="nav-toggle" aria-label="Menu" onclick="MG.toggleMobile()">MENU ☰</button>' +
        '<nav id="mobile-menu" class="mobile-menu-overlay">' +
          '<button class="mobile-menu-close" aria-label="Zavřít" onclick="MG.toggleMobile()">✕</button>' +
          '<ul id="main-menu" class="main-menu df">' + nav +
            '<li><a class="btn btngreen-small pulse" data-route="/rezervace" href="#/rezervace">REZERVACE</a></li>' +
          '</ul>' +
        '</nav>' +
      '</div>' +
    '</div></div>' +
  '</header>';
};

MG.renderFooter = function(){
  var menuHtml = '';
  MG.menuItems.forEach(function(item){
    menuHtml += '<li><a data-route="' + item.route + '" href="#' + item.route + '">' + item.label + '</a></li>';
  });
  menuHtml += '<li><a data-route="/rezervace" href="#/rezervace">REZERVACE</a></li>';

  return '<footer id="footer"><div class="container"><div class="gr4">' +
    '<div>' +
      '<p><a href="#/" aria-label="Motogo24"><img src="' + MG.LOGO_SVG + '" alt="Motogo24" loading="lazy"></a></p><p>&nbsp;</p>' +
      '<p>Vítejte u Motogo24, vaší <strong>půjčovny motorek v Pelhřimově</strong>! Nabízíme <strong>pronájem motorek</strong> pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.</p>' +
    '</div>' +
    '<div><h3>Půjčovna motorek</h3><ul>' + menuHtml + '</ul></div>' +
    '<div><h3>Půjčovna motorek na sítích</h3>' +
      '<p class="dfc"><a href="' + MG.FB_URL + '" title="Facebook"><img alt="Facebook" src="gfx/facebook.svg" style="width:24px;height:24px;display:inline-block;filter:brightness(0) invert(1)"></a>&nbsp;<a href="' + MG.FB_URL + '">facebook</a></p><p>&nbsp;</p>' +
      '<p class="dfc"><a href="' + MG.IG_URL + '" title="Instagram"><img alt="Instagram" src="gfx/instagram.svg" style="width:24px;height:24px;display:inline-block;filter:brightness(0) invert(1)"></a>&nbsp;<a href="' + MG.IG_URL + '">instagram</a></p>' +
    '</div>' +
    '<div class="footer-contact"><h3>Potřebujete poradit?</h3>' +
      '<div class="footer-phone dfc"><div class="img-icon dfcc"><img src="gfx/telefon.svg" alt="Telefon" class="icon-small" loading="lazy"></div><div><p>ZAVOLEJTE NÁM<br><strong><a href="' + MG.PHONE_LINK + '">' + MG.PHONE + '</a></strong></p></div></div>' +
      '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/email.svg" alt="E-mail" class="icon-small" loading="lazy"></div><div><p>' + MG.EMAIL_USER + '@' + MG.EMAIL_DOMAIN + '</p></div></div>' +
      '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/adresa.svg" alt="Adresa" class="icon-small" loading="lazy"></div><div><p><strong>Půjčovna motorek Motogo24</strong><br>' + MG.ADDRESS + '</p></div></div>' +
      '<div class="dfc"><div class="img-icon dfcc"><img src="gfx/provozni-doba.svg" alt="Provozní doba" class="icon-small" loading="lazy"></div><div><p><strong>PO - NE</strong> 00:00 – 24:00&nbsp;(nonstop)</p></div></div>' +
    '</div>' +
  '</div></div>' +
  '<div class="copyright"><div class="container">' +
    '<p>© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena</p>' +
    '<p><a href="#/mapa-stranek">Mapa stránek</a><a href="#">Cookies</a><a href="#/gdpr">GDPR</a><a href="#/obchodni-podminky">Obchodní podmínky</a><a href="#/smlouva">Smlouva o pronájmu</a></p>' +
  '</div></div>' +
  '</footer>' +
  '<a id="Up" href="#" aria-label="NAHORU" onclick="window.scrollTo({top:0,behavior:\'smooth\'});return false"><img src="gfx/arrow-top.svg" alt="NAHORU"></a>';
};

// ===== MOBILE MENU TOGGLE =====
MG.toggleMobile = function(){
  var m = document.getElementById('mobile-menu');
  if(m) m.classList.toggle('open');
};

// ===== SCROLL TO TOP BUTTON =====
MG.initScrollTop = function(){
  var btn = document.getElementById('Up');
  if(!btn) return;
  window.addEventListener('scroll', function(){
    btn.classList.toggle('visible', window.scrollY > 400);
  });
};

// ===== SUBMENU TOGGLE (mobile) =====
MG.initSubmenus = function(){
  document.querySelectorAll('.has-sub > a').forEach(function(a){
    a.addEventListener('click', function(e){
      if(window.innerWidth <= 768){
        var li = a.parentElement;
        var wasOpen = li.classList.contains('show');
        document.querySelectorAll('.has-sub').forEach(function(el){ el.classList.remove('show'); });
        if(!wasOpen){
          e.preventDefault();
          li.classList.add('show');
        }
      }
    });
  });
};
