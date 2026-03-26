// ===== MotoGo24 Web — Blog listing + detail =====

var MG = window.MG || {};
window.MG = MG;

// ===== BLOG LISTING =====
MG.route('/blog', async function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Blog']);

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<section class="ccontent"><h1>Blog a tipy</h1>' +
    '<div id="blog-tags"></div>' +
    '<div class="tab-content"><div class="tab-pane active">' +
    '<div id="blog-grid" class="gr3"><div class="loading-overlay"><span class="spinner"></span> Načítám články...</div></div>' +
    '</div></div></section></div></main>';

  var posts = await MG.fetchCmsPages();
  var gridEl = document.getElementById('blog-grid');
  var tagsEl = document.getElementById('blog-tags');
  if(!gridEl) return;

  if(!posts.length){
    gridEl.innerHTML = '<p>Zatím nemáme žádné články.</p>';
    return;
  }

  // Extract unique tags
  var tagCounts = {};
  posts.forEach(function(p){
    if(p.tags && p.tags.length){
      p.tags.forEach(function(t){ tagCounts[t] = (tagCounts[t]||0) + 1; });
    }
  });

  // Render tag filter
  if(tagsEl && Object.keys(tagCounts).length){
    var tagHtml = '<ul class="nav nav-pills df"><li>Štítky</li>' +
      '<li class="active"><a href="#" data-blog-tag="">Všechny (' + posts.length + ')</a></li>';
    for(var tag in tagCounts){
      tagHtml += '<li><a href="#" data-blog-tag="' + tag + '">' + tag + ' (' + tagCounts[tag] + ')</a></li>';
    }
    tagHtml += '</ul>';
    tagsEl.innerHTML = tagHtml;

    // Tag click handler
    tagsEl.querySelectorAll('[data-blog-tag]').forEach(function(a){
      a.addEventListener('click', function(e){
        e.preventDefault();
        var selectedTag = a.getAttribute('data-blog-tag');
        tagsEl.querySelectorAll('li').forEach(function(li){ li.classList.remove('active'); });
        a.parentElement.classList.add('active');
        MG._filterBlogPosts(posts, selectedTag);
      });
    });
  }

  // Render all posts
  MG._renderBlogPosts(gridEl, posts);
});

MG._filterBlogPosts = function(posts, tag){
  var el = document.getElementById('blog-grid');
  if(!el) return;
  var filtered = tag ? posts.filter(function(p){
    return p.tags && p.tags.indexOf(tag) !== -1;
  }) : posts;
  MG._renderBlogPosts(el, filtered);
};

MG._renderBlogPosts = function(el, posts){
  if(!posts.length){ el.innerHTML = '<p>Žádné články v této kategorii.</p>'; return; }
  var html = '';
  posts.forEach(function(p){ html += MG.renderBlogCard(p); });
  el.innerHTML = html;
};

// ===== BLOG DETAIL =====
MG.route('/blog/:slug', async function(app, params){
  app.innerHTML = '<main id="content"><div class="container"><div class="loading-overlay"><span class="spinner"></span> Načítám článek...</div></div></main>';

  var post = await MG.fetchCmsPage(params.slug);
  if(!post){
    app.innerHTML = '<main id="content"><div class="container">' +
      MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Blog',href:'/blog'},'Článek nenalezen']) +
      '<div class="ccontent"><h1>Článek nenalezen</h1><p><a class="btn btngreen" href="#/blog">Zpět na blog</a></p></div></div></main>';
    return;
  }

  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},{label:'Blog',href:'/blog'}, post.title]);

  // Gallery
  var galleryHtml = '';
  if(post.images && post.images.length){
    galleryHtml = '<section><div class="gallery-blog">';
    post.images.forEach(function(img){
      galleryHtml += '<div class="col-lg-3 col-md-4 col-sm-6">' +
        '<a href="' + img + '" target="_blank"><div class="gallery-background"><div class="gallery-box">' +
        '<img src="' + img + '" alt="' + post.title + '" loading="lazy"></div></div></a></div>';
    });
    galleryHtml += '</div></section>';
  } else if(post.image_url){
    galleryHtml = '<section><div class="gallery-blog">' +
      '<div class="col-lg-3 col-md-4 col-sm-6"><a href="' + post.image_url + '" target="_blank"><div class="gallery-background"><div class="gallery-box">' +
      '<img src="' + post.image_url + '" alt="' + post.title + '" loading="lazy"></div></div></a></div></div></section>';
  }

  // Content
  var content = post.content || post.description || '';

  app.innerHTML = '<main id="content"><div class="container">' + bc +
    '<div class="ccontent blog-detail">' +
    '<section><h1>' + post.title + '</h1>' +
    '<p>' + (post.excerpt || post.description || '') + '</p></section>' +
    (content ? '<section><div class="blog-content">' + content + '</div></section>' : '') +
    galleryHtml +
    '</div></div></main>';
});
