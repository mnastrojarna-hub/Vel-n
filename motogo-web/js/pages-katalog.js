// ===== MotoGo24 Web — Katalog + Detail motorky =====

var MG = window.MG || {};
window.MG = MG;

// Cached motos
MG._motosCache = null;
MG._getMotos = async function(){
  if(MG._motosCache && MG._motosCache.length) return MG._motosCache;
  MG._motosCache = await MG.fetchMotos();
  console.log('[KATALOG] Loaded', (MG._motosCache||[]).length, 'motos');
  return MG._motosCache || [];
};

// ===== KATALOG LISTING =====
MG.route('/katalog', function(app){ MG._renderKatalog(app, null, 'Katalog motorek'); });
MG.route('/katalog/cestovni', function(app){ MG._renderKatalog(app, 'cestovni', 'Cestovní motorky'); });
MG.route('/katalog/detske', function(app){ MG._renderKatalog(app, 'detske', 'Dětské motorky'); });

MG._renderKatalog = async function(app, category, title){
  var bc = [{label:'Domů', href:'/'}, {label:'Katalog motorek', href:'/katalog'}];
  if(category) bc.push(title);
  else bc[1] = title;

  app.innerHTML = '<main id="content"><section class="container">' +
    MG.renderBreadcrumb(bc) +
    '<div class="ccontent"><h1>' + title + '</h1>' +
    '<div id="katalog-grid" class="gr4"><div class="loading-overlay"><span class="spinner"></span> Načítám motorky...</div></div>' +
    '</div></section></main>';

  var motos = await MG._getMotos();
  var filtered = motos;
  if(category){
    filtered = motos.filter(function(m){
      var cat = (m.category || '').toLowerCase();
      var model = (m.model || '').toLowerCase();
      if(category === 'cestovni') return cat.indexOf('cestov') !== -1 || cat.indexOf('adventure') !== -1 || cat.indexOf('enduro') !== -1 || cat.indexOf('touring') !== -1;
      if(category === 'detske') return cat.indexOf('dets') !== -1 || cat.indexOf('dět') !== -1 || cat.indexOf('mini') !== -1 || cat.indexOf('child') !== -1 || (m.license_required && m.license_required.toUpperCase() === 'N');
      return true;
    });
  }

  var el = document.getElementById('katalog-grid');
  if(!el) return;
  if(!filtered.length){ el.innerHTML = '<p>V této kategorii nemáme momentálně žádné motorky.</p>'; return; }
  var html = '';
  filtered.forEach(function(m){
    html += '<section aria-label="katalog motorek">' + MG.renderMotoCard(m) + '</section>';
  });
  el.innerHTML = html;
};

// ===== DETAIL MOTORKY =====
MG.route('/katalog/:id', async function(app, params){
  app.innerHTML = '<main id="content"><div class="container"><div class="loading-overlay"><span class="spinner"></span> Načítám detail motorky...</div></div></main>';

  var motos = await MG._getMotos();
  var moto = motos.find(function(m){ return m.id === params.id; });
  if(!moto){
    app.innerHTML = '<main id="content"><div class="container">' +
      MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Katalog',href:'/katalog'},'Motorka nenalezena']) +
      '<div class="ccontent"><h1>Motorka nenalezena</h1><p><a class="btn btngreen" href="#/katalog">Zpět na katalog</a></p></div></div></main>';
    return;
  }

  // Find prev/next
  var idx = motos.indexOf(moto);
  var prev = idx > 0 ? motos[idx-1] : null;
  var next = idx < motos.length-1 ? motos[idx+1] : null;

  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Katalog motorek',href:'/katalog'}, moto.model]);

  // Navigation
  var navHtml = '<nav class="moto-nav">';
  navHtml += prev ? '<a class="moto-nav-prev" href="#/katalog/' + prev.id + '">&larr; ' + prev.model + '</a>' : '<span class="moto-nav-prev moto-nav-disabled"></span>';
  navHtml += '<a class="moto-nav-back" href="#/katalog">&#8801; Katalog motorek</a>';
  navHtml += next ? '<a class="moto-nav-next" href="#/katalog/' + next.id + '">' + next.model + ' &rarr;</a>' : '<span class="moto-nav-next moto-nav-disabled"></span>';
  navHtml += '</nav>';

  // Header
  var headerHtml = '<div class="moto-detail-header"><div><h1>' + moto.model + '</h1></div><div>' +
    '<a class="btn btngreen" href="#/rezervace?moto=' + moto.id + '">REZERVOVAT ONLINE</a></div></div>';

  // Short desc + gallery
  var descHtml = '<div class="moto-shortdesc">';
  if(moto.description){
    descHtml += '<div class="wbox"><p>' + moto.description + '</p></div><p>&nbsp;</p>';
  }
  // Features list
  var features = [];
  if(moto.power_kw) features.push('<strong>Výkon:</strong> ' + moto.power_kw + ' kW');
  if(moto.category) features.push('<strong>Typ:</strong> ' + moto.category);
  if(moto.engine_cc) features.push('<strong>Motor:</strong> ' + moto.engine_cc + ' ccm');
  if(moto.engine_type) features.push('<strong>Motor typ:</strong> ' + moto.engine_type);
  if(moto.ideal_usage) features.push('<strong>Vhodná pro:</strong> ' + moto.ideal_usage);
  if(features.length){
    descHtml += '<h2>Krátký popis</h2><ul>';
    features.forEach(function(f){ descHtml += '<li>' + f + '</li>'; });
    descHtml += '</ul><p>&nbsp;</p>';
  }
  if(moto.features){
    descHtml += '<h3>Výbava a výhody</h3><ul>';
    var featArr = typeof moto.features === 'string' ? moto.features.split(',') : (moto.features || []);
    featArr.forEach(function(f){ if(f.trim()) descHtml += '<li>' + f.trim() + '</li>'; });
    descHtml += '</ul>';
  }
  descHtml += '</div>';

  // Gallery
  var mainImg = moto.image_url || (moto.images && moto.images[0]) || '';
  var galleryHtml = '<div class="moto-gallery">';
  if(mainImg){
    galleryHtml += '<div class="moto-photo"><a href="' + mainImg + '" target="_blank"><div class="gallery-img"><img src="' + mainImg + '" alt="' + moto.model + '" loading="lazy"></div></a></div>';
  }
  if(moto.images && moto.images.length > 1){
    galleryHtml += '<div class="gr3">';
    moto.images.slice(1, 4).forEach(function(img){
      galleryHtml += '<div><a href="' + img + '" target="_blank"><div class="gallery-img"><img src="' + img + '" alt="' + moto.model + '" loading="lazy"></div></a></div>';
    });
    galleryHtml += '</div>';
  }
  galleryHtml += '</div>';

  var infoHtml = '<section class="moto-info gr2">' + descHtml + galleryHtml + '</section>';

  // Description + Specs table
  var specsRows = [];
  if(moto.engine_cc) specsRows.push(['Objem motoru', moto.engine_cc + ' ccm']);
  if(moto.power_kw) specsRows.push(['Výkon', moto.power_kw + ' kW']);
  if(moto.engine_type) specsRows.push(['Typ motoru', moto.engine_type]);
  if(moto.weight_kg) specsRows.push(['Hmotnost', moto.weight_kg + ' kg']);
  if(moto.seat_height_mm) specsRows.push(['Výška sedla', moto.seat_height_mm + ' mm']);
  if(moto.fuel_tank_l) specsRows.push(['Nádrž', moto.fuel_tank_l + ' l']);
  if(moto.has_abs) specsRows.push(['ABS', 'Ano']);
  if(moto.license_required) specsRows.push(['Řidičák', 'Skupina ' + moto.license_required]);
  if(moto.ideal_usage) specsRows.push(['Ideální pro', moto.ideal_usage]);

  var descSpecsHtml = '<section class="gr2"><div>';
  descSpecsHtml += '<h2>Popis motorky</h2><p>' + (moto.description || moto.model) + '</p>';
  if(moto.manual_url){
    descSpecsHtml += '<p>&nbsp;</p><p><a class="btn btngreen" href="' + moto.manual_url + '" target="_blank" rel="noopener">Uživatelský manuál</a></p>';
  }
  descSpecsHtml += '</div><div><h2>Technická specifikace</h2>';
  if(specsRows.length){
    descSpecsHtml += MG.renderTable(['Parametr', 'Hodnota'], specsRows);
  }
  descSpecsHtml += '</div></section>';

  // Pricing table + Calendar
  var days = ['Pondělí','Úterý','Středa','Čtvrtek','Pátek','Sobota','Neděle'];
  var priceKeys = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun'];
  var priceRows = [];
  days.forEach(function(day, i){
    var p = moto[priceKeys[i]];
    if(p) priceRows.push([day, MG.formatPrice(p)]);
  });

  var pricesHtml = '<section class="moto-prices gr2"><div><h2>Ceník půjčovného</h2>' +
    '<p>Cena půjčení se liší podle dne v týdnu:</p>';
  if(priceRows.length) pricesHtml += MG.renderTable(['Den','Cena za den'], priceRows);
  pricesHtml += '<p><strong>V ceně je zahrnuta výbava:</strong> helma, bunda, kalhoty a rukavice.</p></div>';
  pricesHtml += '<div class="moto-reservation"><h2>Dostupnost</h2>' +
    '<p>Zkontroluj volné termíny a zarezervuj si motorku snadno online.</p>' +
    MG.renderCalendar('detail-cal-' + moto.id, moto.id) +
    '<p class="calendar-info">* Vyberte si prosím minimálně 3 souvislé dny.</p>' +
    '<div class="reservation-btn"><a class="btn btngreen" href="#/rezervace?moto=' + moto.id + '">PŘEJÍT NA REZERVACE</a></div>' +
  '</div></section>';

  // Related motos
  var sameCat = motos.filter(function(m){ return m.id !== moto.id && m.category === moto.category; }).slice(0, 4);
  var relatedHtml = '';
  if(sameCat.length){
    relatedHtml = '<section class="moto-related"><h2>Podobné motorky k zapůjčení</h2><div class="gr4">';
    sameCat.forEach(function(m){
      relatedHtml += '<section aria-label="katalog motorek">' + MG.renderMotoCard(m) + '</section>';
    });
    relatedHtml += '</div></section>';
  }

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<article class="moto-detail ccontent" itemscope itemtype="https://schema.org/Product">' +
      '<header>' + navHtml + headerHtml + '</header>' +
      infoHtml + descSpecsHtml + pricesHtml + relatedHtml +
    '</article></div></main>';
});
