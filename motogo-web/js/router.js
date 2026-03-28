// ===== MotoGo24 Web — SPA Router =====
// Hash-based routing pro statický hosting. Stránky se renderují do #app.

var MG = window.MG || {};
window.MG = MG;

MG.routes = {};
MG._currentPage = null;

MG.route = function(path, handler){
  MG.routes[path] = handler;
};

MG.navigate = function(path){
  window.location.hash = '#' + path;
};

MG.getHash = function(){
  var h = window.location.hash.replace(/^#\/?/, '') || '';
  return '/' + h;
};

MG.initRouter = function(){
  window.addEventListener('hashchange', function(){ MG._resolve(); });
  MG._resolve();
};

MG._resolve = function(){
  var fullPath = MG.getHash();
  // Strip query string for route matching (query params stay in hash for pages to read)
  var path = fullPath.split('?')[0];
  var app = document.getElementById('app');
  if(!app) return;

  // Exact match
  if(MG.routes[path]){
    MG._currentPage = path;
    MG.routes[path](app, {});
    window.scrollTo(0, 0);
    MG._updateActiveMenu(path);
    return;
  }

  // Parametric match: /katalog/:slug, /blog/:slug
  for(var pattern in MG.routes){
    if(pattern.indexOf(':') === -1) continue;
    var regex = new RegExp('^' + pattern.replace(/:[^/]+/g, '([^/]+)') + '$');
    var match = path.match(regex);
    if(match){
      var paramNames = (pattern.match(/:[^/]+/g) || []).map(function(p){ return p.slice(1); });
      var params = {};
      paramNames.forEach(function(name, i){ params[name] = decodeURIComponent(match[i+1]); });
      MG._currentPage = path;
      MG.routes[pattern](app, params);
      window.scrollTo(0, 0);
      MG._updateActiveMenu(path);
      return;
    }
  }

  // 404
  app.innerHTML = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Stránka nenalezena']) +
    '<div class="ccontent"><h1>Stránka nenalezena</h1><p>Hledaná stránka neexistuje.</p>' +
    '<p><a class="btn btngreen" href="#/">Zpět na úvodní stránku</a></p></div>';
};

MG._updateActiveMenu = function(path){
  document.querySelectorAll('.main-menu a').forEach(function(a){
    a.classList.remove('active');
    var href = a.getAttribute('data-route') || '';
    if(href && path.indexOf(href) === 0) a.classList.add('active');
  });
};

// ===== BREADCRUMB HELPER =====
MG.renderBreadcrumb = function(items){
  var html = '<nav class="breadcrumb" aria-label="breadcrumb"><ol>';
  items.forEach(function(item, i){
    if(typeof item === 'string'){
      html += '<li>' + item + '</li>';
    } else {
      html += '<li><a href="#' + item.href + '">' + item.label + '</a></li>';
    }
  });
  html += '</ol></nav>';
  return html;
};

// ===== LINK INTERCEPT =====
// Convert internal links to hash navigation
document.addEventListener('click', function(e){
  var a = e.target.closest('a[data-route]');
  if(!a) return;
  e.preventDefault();
  MG.navigate(a.getAttribute('data-route'));
});
