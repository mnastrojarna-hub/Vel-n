// ===== MotoGo24 Web — Reusable Components =====

var MG = window.MG || {};
window.MG = MG;

// ===== MOTO CARD =====
MG.renderMotoCard = function(m){
  var img = m.image_url || (m.images && m.images.length ? m.images[0] : '') || '';
  var desc = m.ideal_usage || '';
  var cat = m.category || '';
  var kw = m.power_kw ? (m.power_kw + ' kW') : '';
  var price = MG.getMinPrice(m);
  var license = m.license_required || '';

  var features = [];
  if(cat) features.push(cat);
  if(license && license !== 'N') features.push(license);
  if(kw) features.push(kw);
  if(desc){
    desc.split(',').forEach(function(f){
      var t = f.trim();
      if(t && features.length < 6) features.push(t);
    });
  }

  var featHtml = '<ul>';
  features.forEach(function(f){ featHtml += '<li>' + f + '</li>'; });
  featHtml += '</ul>';

  var priceText = price > 0 ? ('Cena: od ' + MG.formatPrice(price) + '/den') : '';

  return '<a class="moto-wrapper" href="#/katalog/' + m.id + '" aria-label="' + m.model + '">' +
    '<div class="moto-title"><h2>' + m.model + '</h2></div>' +
    '<div class="moto-img">' + (img ? '<img src="' + img + '" alt="' + m.model + '" class="imgres" loading="lazy">' : '') + '</div>' +
    '<div class="moto-desc">' + featHtml + (priceText ? '<p class="moto-price">' + priceText + '</p>' : '') + '</div>' +
    '<div class="moto-btn"><span class="btn btngreen-small">DETAIL MOTORKY</span></div>' +
  '</a>';
};

// ===== BLOG CARD =====
MG.renderBlogCard = function(post){
  var img = (post.images && post.images[0]) || post.image_url || '';
  var tag = (post.tags && post.tags[0]) || '';
  var excerpt = post.excerpt || post.description || '';
  return '<div><a class="blog-wrapper" href="#/blog/' + post.slug + '" aria-label="' + post.title + '">' +
    '<div class="blog-title"><h2>' + post.title + '</h2></div>' +
    '<div class="blog-img">' + (img ? '<img src="' + img + '" alt="' + post.title + '" class="imgres" loading="lazy">' : '') + '</div>' +
    '<div class="blog-desc">' + (tag ? '<p><span class="tag-label">' + tag + '</span></p>' : '') + '<p>' + excerpt + '</p></div>' +
    '<div class="blog-btn"><span class="btn btngreen-small">PŘEČÍST ČLÁNEK</span></div>' +
  '</a></div>';
};

// ===== WBOX (icon box) =====
MG.renderWbox = function(icon, title, text){
  return '<div class="wbox">' +
    (icon ? '<div class="wbox-img"><img src="' + icon + '" class="icon" alt="' + title + '" loading="lazy"></div>' : '') +
    '<h3><p>' + title + '</p></h3>' +
    '<p>' + text + '</p></div>';
};

// ===== FAQ ITEM =====
MG.renderFaqItem = function(question, answer){
  return '<details class="faq-item"><summary>' + question + '</summary><p>' + answer + '</p></details>';
};

// ===== FAQ SECTION =====
MG.renderFaqSection = function(title, items, moreLink){
  var html = '<section aria-labelledby="faq"><h2>' + title + '</h2><div class="tab-content"><div class="tab-pane active" id="all"><div class="gr2">';
  items.forEach(function(faq){
    html += MG.renderFaqItem(faq.q, faq.a);
  });
  html += '</div></div></div>';
  if(moreLink){
    html += '<p>&nbsp;</p><p><a class="btn btngreen" href="#' + moreLink + '">Další často kladené otázky</a></p>';
  }
  html += '</section>';
  return html;
};

// ===== CTA SECTION =====
MG.renderCta = function(title, text, buttons){
  var html = '<section aria-labelledby="cta"><h2>' + title + '</h2><p>' + text + '</p><p>&nbsp;</p><p>';
  buttons.forEach(function(btn){
    html += '<a class="btn ' + (btn.cls || 'btndark') + '" href="#' + btn.href + '">' + btn.label + '</a>&nbsp;';
  });
  html += '</p></section>';
  return html;
};

// ===== CALENDAR COMPONENT =====
MG.renderCalendar = function(containerId, motoId){
  setTimeout(function(){ MG._buildCalendar(containerId, motoId); }, 100);
  return '<div id="' + containerId + '" class="calendar-placeholder"><div class="loading-overlay"><span class="spinner"></span> Načítám dostupnost...</div></div>' +
    '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div><div><span class="cicon occupied">&nbsp;</span> Obsazené</div><div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>';
};

MG._calState = {};

MG._buildCalendar = async function(containerId, motoId){
  var el = document.getElementById(containerId);
  if(!el) return;

  var bookings = await MG.fetchMotoBookings(motoId);
  var bookedDays = {};
  bookings.forEach(function(b){
    var s = new Date(b.start_date);
    var e = new Date(b.end_date);
    var d = new Date(s);
    while(d <= e){
      var key = d.toISOString().split('T')[0];
      bookedDays[key] = b.status === 'pending' ? 'unconfirmed' : 'occupied';
      d.setDate(d.getDate() + 1);
    }
  });

  var now = new Date();
  var state = {year: now.getFullYear(), month: now.getMonth(), bookedDays: bookedDays};
  MG._calState[containerId] = state;
  MG._renderCalMonth(containerId);
};

MG._renderCalMonth = function(containerId){
  var el = document.getElementById(containerId);
  if(!el) return;
  var state = MG._calState[containerId];
  var y = state.year, m = state.month;
  var months = ['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'];
  var dayNames = ['Po','Út','St','Čt','Pá','So','Ne'];
  var firstDay = new Date(y, m, 1);
  var lastDay = new Date(y, m + 1, 0);
  var startDow = (firstDay.getDay() + 6) % 7;

  var html = '<div class="cal-nav">' +
    '<button onclick="MG._calPrev(\'' + containerId + '\')">&larr;</button>' +
    '<span>' + months[m] + ' ' + y + '</span>' +
    '<button onclick="MG._calNext(\'' + containerId + '\')">&rarr;</button></div>';
  html += '<div class="cal-grid">';
  dayNames.forEach(function(d){ html += '<div class="cal-header">' + d + '</div>'; });

  for(var i = 0; i < startDow; i++) html += '<div class="cal-day empty"></div>';

  var today = new Date().toISOString().split('T')[0];
  for(var d = 1; d <= lastDay.getDate(); d++){
    var dateStr = y + '-' + String(m+1).padStart(2,'0') + '-' + String(d).padStart(2,'0');
    var status = state.bookedDays[dateStr] || (dateStr < today ? 'past' : 'available');
    var cls = 'cal-day';
    if(status === 'occupied') cls += ' occupied';
    else if(status === 'unconfirmed') cls += ' unconfirmed';
    else if(status === 'past') cls += ' occupied';
    else cls += ' available';
    html += '<div class="' + cls + '">' + d + '</div>';
  }
  html += '</div>';
  el.innerHTML = html;
};

MG._calPrev = function(id){
  var s = MG._calState[id];
  s.month--;
  if(s.month < 0){ s.month = 11; s.year--; }
  MG._renderCalMonth(id);
};

MG._calNext = function(id){
  var s = MG._calState[id];
  s.month++;
  if(s.month > 11){ s.month = 0; s.year++; }
  MG._renderCalMonth(id);
};

// ===== TABLE HELPER =====
MG.renderTable = function(headers, rows){
  var html = '<div class="table-responsive"><table class="table table-striped table-hover"><thead><tr>';
  headers.forEach(function(h){ html += '<th>' + h + '</th>'; });
  html += '</tr></thead><tbody>';
  rows.forEach(function(row){
    html += '<tr>';
    row.forEach(function(cell){ html += '<td>' + cell + '</td>'; });
    html += '</tr>';
  });
  html += '</tbody></table></div>';
  return html;
};
