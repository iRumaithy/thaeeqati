const CACHE_NAME = 'thawaq-shell-v2.3';
const APP_SHELL = [
  './',
  './index.html',
  './config.js',
  './manifest.webmanifest',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png',
  './icon-512-maskable.png'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)));
});


self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Never cache Supabase API/auth/storage responses.
  if (url.hostname.endsWith('.supabase.co')) return;

  // Network-first for pages/config so published updates are picked up quickly.
  if (req.mode === 'navigate' || (url.origin === self.location.origin && /\/(index\.html|config\.js)$/.test(url.pathname))) {
    event.respondWith(
      fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
        return res;
      }).catch(() => caches.match(req).then(r => r || caches.match('./index.html')))
    );
    return;
  }

  // Cache local static assets and the Supabase JS CDN library after first use.
  if (url.origin === self.location.origin || url.hostname === 'cdn.jsdelivr.net') {
    event.respondWith(
      caches.match(req).then(cached => cached || fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
        return res;
      }))
    );
  }
});


self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = { body: event.data?.text?.() || '' }; }
  const title = data.title || 'ذواق';
  const options = {
    body: data.body || 'لديك إشعار جديد من ذواق.',
    icon: './icon-192.png',
    badge: './icon-192.png',
    tag: data.tag || `thawaq-${data.version || 'notice'}`,
    renotify: true,
    data: { url: data.url || './', version: data.version || '', kind: data.kind || '' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || './', self.location.origin).href;
  event.waitUntil((async () => {
    const list = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of list) {
      if ('focus' in client) {
        try { await client.navigate(target); } catch {}
        return client.focus();
      }
    }
    return clients.openWindow ? clients.openWindow(target) : undefined;
  })());
});
