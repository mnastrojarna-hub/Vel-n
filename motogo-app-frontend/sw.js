// ===== SERVICE WORKER – MotoGo24 PWA offline cache =====
var CACHE = 'motogo24-v50';
var ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './css/main.css',
  './css/elements.css',
  './css/screens.css',
  './css/screens-extra.css',
  './data/assets.js',
  './data/assets-img1.js',
  './data/assets-data.js',
  './data/motos.js',
  './data/motos-extra.js',
  './data/legal-texts.js',
  './src/services/supabase-sdk.js',
  './src/services/supabaseClient.js',
  './src/services/auth.js',
  './js/offline-guard.js',
  './templates.js',
  './templates-screens.js',
  './templates-screens-booking.js',
  './templates-booking-form2.js',
  './templates-booking-form.js',
  './templates-res.js',
  './templates-res-edit.js',
  './templates-res-sos.js',
  './templates-res-sos2.js',
  './templates-res-sos3.js',
  './templates-shop.js',
  './templates-shop-detail.js',
  './templates-done.js',
  './js/router.js',
  './js/storage.js',
  './js/booking-utils.js',
  './js/cart-engine.js',
  './js/cart-checkout.js',
  './js/cart-shop-discount.js',
  './js/cart-booking-price.js',
  './js/cart-booking-discount.js',
  './js/cart-address-data.js',
  './js/cart-address.js',
  './js/cart-address-geo.js',
  './ui-controller.js',
  './booking-logic.js',
  './booking-detail.js',
  './booking-detail-cal.js',
  './booking-calendar.js',
  './booking-edit.js',
  './js/auth-ui.js',
  './js/profile-ui.js',
  './js/reservations-ui.js',
  './js/payment-ui.js',
  './js/i18n.js',
  './js/documents.js',
  './native-bridge.js',
  './app.js'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE).then(function(cache) {
      return cache.addAll(ASSETS);
    }).then(function() {
      return self.skipWaiting();
    })
  );
});

self.addEventListener('activate', function(e) {
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
  // Only handle same-origin GET requests
  if (e.request.method !== 'GET') return;

  e.respondWith(
    caches.match(e.request).then(function(cached) {
      if (cached) return cached;
      return fetch(e.request).then(function(response) {
        // Cache successful same-origin responses
        if (response.ok && e.request.url.startsWith(self.location.origin)) {
          var copy = response.clone();
          caches.open(CACHE).then(function(cache) {
            cache.put(e.request, copy);
          });
        }
        return response;
      });
    }).catch(function() {
      // Offline fallback – return cached index for navigation
      if (e.request.mode === 'navigate') {
        return caches.match('./index.html');
      }
    })
  );
});
