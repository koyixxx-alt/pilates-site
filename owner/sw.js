/* Pilates Studio — Service Worker
   方針：常にネットワーク優先（オンライン時は必ず最新版を表示＝更新の取りこぼしなし）。
   オフラインのときだけキャッシュを使い、アプリが開けるようにする。 */
const CACHE = 'pilates-shell-v1';

self.addEventListener('install', (e) => { self.skipWaiting(); });

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;   // Supabase等の通信はそのまま通す

  e.respondWith((async () => {
    try {
      const fresh = await fetch(req);                  // オンライン：常に最新
      const cache = await caches.open(CACHE);
      cache.put(req, fresh.clone());
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);          // オフライン：キャッシュ
      if (cached) return cached;
      const shell = await caches.match('./');
      if (shell) return shell;
      throw err;
    }
  })());
});
