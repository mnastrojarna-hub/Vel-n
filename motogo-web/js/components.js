// ===== MotoGo24 Web — Reusable Components =====

var MG = window.MG || {};
window.MG = MG;

// ===== IMAGE URL HELPER =====
// Handles relative paths from DB (e.g. "photos/yamaha.jpg") by prepending Supabase storage URL
MG.imgUrl = function(src){
  if(!src) return '';
  if(src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) return src;
  var base = (window.MOTOGO_CONFIG || {}).SUPABASE_URL || '';
  return base + '/storage/v1/object/public/media/' + src;
};

// ===== MOTO CARD =====
MG.renderMotoCard = function(m){
  var img = MG.imgUrl(m.image_url || (m.images && m.images.length ? m.images[0] : ''));
  var desc = m.ideal_usage || '';
  var cat = m.category || '';
  var kw = m.power_kw ? (m.power_kw + ' kW') : '';
  var price = MG.getMinPrice(m);
  var license = m.license_required || '';

  var features = [];
  if(cat) features.push(cat);
  if(license && license !== 'N') features.push(license);
  if(kw) features.push(kw);
  if(desc && typeof desc === 'string'){
    desc.split(',').forEach(function(f){
      var t = f.trim();
      if(t && features.length < 6) features.push(t);
    });
  } else if(Array.isArray(desc)){
    desc.forEach(function(f){
      var t = (typeof f === 'string') ? f.trim() : String(f);
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

// ===== CALENDAR COMPONENT (interactive with date selection) =====
MG.renderCalendar = function(containerId, motoId){
  setTimeout(function(){ MG._buildCalendar(containerId, motoId); }, 100);
  return '<div id="' + containerId + '" class="calendar-placeholder"><div class="loading-overlay"><span class="spinner"></span> Načítám dostupnost...</div></div>' +
    '<div class="calendar-icons gr3"><div><span class="cicon loosely">&nbsp;</span> Volné</div><div><span class="cicon occupied">&nbsp;</span> Obsazené</div><div><span class="cicon unconfirmed">&nbsp;</span> Nepotvrzené</div></div>' +
    '<div id="' + containerId + '-banner" style="display:none"></div>';
};

MG._calState = {};

MG._buildCalendar = async function(containerId, motoId){
  var el = document.getElementById(containerId);
  if(!el) return;

  var bookings = await MG.fetchMotoBookings(motoId);
  var bookedDays = {};
  var now = new Date();
  bookings.forEach(function(b){
    var s = new Date(b.start_date);
    var e = new Date(b.end_date);
    var d = new Date(s);
    var isPending = b.status === 'pending';
    var createdAt = b.created_at ? new Date(b.created_at) : null;
    var isRecent = createdAt && (now - createdAt) < 4 * 60 * 60 * 1000;
    var status = (isPending && isRecent) ? 'unconfirmed' : 'occupied';
    while(d <= e){
      var key = d.toISOString().split('T')[0];
      bookedDays[key] = status;
      d.setDate(d.getDate() + 1);
    }
  });

  var state = {year: now.getFullYear(), month: now.getMonth(), bookedDays: bookedDays, motoId: motoId, startDate: null, endDate: null};
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
  var dayFull = ['Ne','Po','Út','St','Čt','Pá','So'];
  var firstDay = new Date(y, m, 1);
  var lastDay = new Date(y, m + 1, 0);
  var startDow = (firstDay.getDay() + 6) % 7;
  var todayStr = new Date().toISOString().split('T')[0];
  var sd = state.startDate, ed = state.endDate;

  var html = '<div class="cal-nav">' +
    '<button onclick="MG._calPrev(\'' + containerId + '\')">&larr;</button>' +
    '<span>' + months[m] + ' ' + y + '</span>' +
    '<button onclick="MG._calNext(\'' + containerId + '\')">&rarr;</button></div>';
  html += '<div class="cal-grid">';
  dayNames.forEach(function(d){ html += '<div class="cal-header">' + d + '</div>'; });

  for(var i = 0; i < startDow; i++) html += '<div class="cal-day empty"></div>';

  for(var d = 1; d <= lastDay.getDate(); d++){
    var ds = y + '-' + String(m+1).padStart(2,'0') + '-' + String(d).padStart(2,'0');
    var booked = state.bookedDays[ds];
    var isPast = ds < todayStr;
    var inRange = sd && ed && ds >= sd && ds <= ed;
    var isStart = sd && ds === sd;
    var isEnd = ed && ds === ed;
    var dayOfWeek = dayFull[new Date(y,m,d).getDay()];

    var bg, color, cursor = 'default', border = 'none';
    if(isPast || booked === 'occupied'){ bg='#444'; color='#fff'; cursor='not-allowed'; }
    else if(booked === 'unconfirmed'){ bg='#fff'; color='#333'; cursor='not-allowed'; border='2px solid #ccc'; }
    else if(isStart || isEnd){ bg='#1a8c1a'; color='#fff'; cursor='pointer'; border='2px solid #fff'; }
    else if(inRange){ bg='#1a8c1a'; color='#fff'; cursor='pointer'; }
    else { bg='#74FB71'; color='#0b0b0b'; cursor='pointer'; }

    var canClick = !isPast && !booked;
    var style = 'background:'+bg+';color:'+color+';cursor:'+cursor+';border:'+border+';border-radius:12px;';
    var click = canClick ? ' onclick="MG._calPickDate(\''+containerId+'\',\''+ds+'\')"' : '';
    html += '<div class="cal-day" style="'+style+'"'+click+'>' +
      '<span style="font-size:.65rem;opacity:.7;display:block;line-height:1">'+dayOfWeek+'</span>' +
      '<span style="font-weight:700">'+d+'</span></div>';
  }
  html += '</div>';
  el.innerHTML = html;
};

// ===== CALENDAR DATE PICK LOGIC =====
MG._calPickDate = function(containerId, ds){
  var state = MG._calState[containerId];
  if(!state) return;
  if(!state.startDate || state.endDate){ state.startDate = ds; state.endDate = null; }
  else if(ds < state.startDate){ state.startDate = ds; state.endDate = null; }
  else if(ds === state.startDate){ state.startDate = null; state.endDate = null; }
  else { state.endDate = ds; }
  MG._renderCalMonth(containerId);
  MG._calUpdateBanner(containerId);
  MG._calUpdateReserveBtn(containerId);
};

// ===== CALENDAR BANNER (shows selected dates) =====
MG._calUpdateBanner = function(containerId){
  var ban = document.getElementById(containerId + '-banner');
  if(!ban) return;
  var state = MG._calState[containerId];
  if(!state.startDate){ ban.style.display='none'; return; }
  if(!state.endDate){
    ban.style.display='block';
    ban.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:12px 16px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
      '<span>Vybrán začátek: <strong>'+MG.formatDate(state.startDate)+'</strong> — klikněte na koncové datum</span>' +
      '<span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="MG._calResetDates(\''+containerId+'\')">&#x2715; ZRUŠIT VÝBĚR</span></div>';
    return;
  }
  ban.style.display='block';
  ban.innerHTML = '<div style="background:#74FB71;color:#0b0b0b;padding:14px 18px;border-radius:25px;margin:12px 0;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">' +
    '<span style="font-size:1.05rem"><strong>VYBRANÝ TERMÍN: '+MG.formatDate(state.startDate)+' – '+MG.formatDate(state.endDate)+'</strong></span>' +
    '<span class="btn" style="background:#0b0b0b;color:#74FB71;padding:6px 14px;font-size:.85rem;cursor:pointer;border-radius:20px" onclick="MG._calResetDates(\''+containerId+'\')">&#x2715; ZRUŠIT VÝBĚR</span></div>';
};

// ===== CALENDAR RESET DATES =====
MG._calResetDates = function(containerId){
  var state = MG._calState[containerId];
  if(state){ state.startDate = null; state.endDate = null; }
  MG._renderCalMonth(containerId);
  MG._calUpdateBanner(containerId);
  MG._calUpdateReserveBtn(containerId);
};

// ===== UPDATE RESERVE BUTTON with selected dates =====
MG._calUpdateReserveBtn = function(containerId){
  var state = MG._calState[containerId];
  if(!state) return;
  var btn = document.getElementById(containerId + '-reserve-btn');
  if(!btn) return;
  var href = '#/rezervace?moto=' + state.motoId;
  if(state.startDate) href += '&start=' + state.startDate;
  if(state.endDate) href += '&end=' + state.endDate;
  btn.href = href;
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
