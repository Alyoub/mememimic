// Offline support: pages come from the network first, everything else from the cache (refreshed in the background).
// Bump VERSION whenever files change so returning players get the new build.
const VERSION = 'meme-mimic-v3';

const CORE = [
  './',
  'index.html',
  'css/app.css?v=2',
  'js/main.js', 'js/ui.js', 'js/game.js', 'js/audio.js', 'js/analyzer.js', 'js/stage.js',
  'js/library.js', 'js/icons.js', 'js/haptics.js', 'js/recorder-worklet.js',
  'vendor/three/three.module.min.js',
  'vendor/three/addons/loaders/GLTFLoader.js',
  'vendor/three/addons/utils/BufferGeometryUtils.js',
  'vendor/three/addons/utils/SkeletonUtils.js',
  'vendor/three/addons/libs/meshopt_decoder.module.js',
  'vendor/three/addons/geometries/RoundedBoxGeometry.js',
  'vendor/preact/preact.module.js', 'vendor/preact/hooks.module.js', 'vendor/preact/htm.module.js',
  'img/icons/splash.jpg', 'img/icons/favicon-48.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;

  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then((res) => {
      const copy = res.clone();
      caches.open(VERSION).then((c) => c.put(req, copy));
      return res;
    }).catch(() => caches.match(req).then((r) => r || caches.match('./'))));
    return;
  }

  // Stale-while-revalidate: instant from cache, refreshed in the background for next time.
  const fresh = fetch(req).then((res) => {
    if (res.ok && res.type === 'basic' && res.status === 200) {
      const copy = res.clone();
      caches.open(VERSION).then((c) => c.put(req, copy));
    }
    return res;
  });
  e.respondWith(caches.match(req).then((hit) => {
    if (hit) { e.waitUntil(fresh.catch(() => {})); return hit; }
    return fresh;
  }));
});
