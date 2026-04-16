// ===== SERVICE WORKER – MotoGo24 (network-first) =====
// Network-first strategy: always serve fresh local files from Capacitor.
// Cache is ONLY used as offline fallback, never served first.
var CACHE = 'motogo24-v53';
var ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './css/main.css',
  './css/elements.css',
  './css/screens.css',
  './css/screens-extra.css'
];

self.addEventListener('install', function(e) {
  // Pre-cache minimal set for offline fallback only
  e.waitUntil(
    caches.open(CACHE).then(function(cache) {
      return cache.addAll(ASSETS);
    }).then(function() {
      return self.skipWaiting();
    })
  );
});

self.addEventListener('activate', function(e) {
  // Delete ALL old caches (including motogo24-v52 with 55 files)
  e.waitUntil(
    caches.keys().then(function(names) {
      return Promise.all(
        names.filter(function(n) { return n !== CACHE; })
             .map(function(n) { return caches.delete(n); })
      );
    }).then(function() {
      return self.clients.claim();
    })
  );
});

self.addEventListener('fetch', function(e) {
  if (e.request.method !== 'GET') return;

  // Skip Supabase API calls — never cache/intercept
  var url = e.request.url;
  if (url.indexOf('supabase.co') !== -1 || url.indexOf('stripe.com') !== -1) return;

  // NETWORK-FIRST: always try fresh file, cache only as fallback
  e.respondWith(
    fetch(e.request).catch(function() {
      return caches.match(e.request).then(function(cached) {
        if (cached) return cached;
        // Offline navigation fallback
        if (e.request.mode === 'navigate') {
          return caches.match('./index.html');
        }
      });
    })
  );
});
