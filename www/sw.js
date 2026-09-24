// Offline cache + auto-update for הלכות הבן איש חי.
//
// Update strategy (important): the NEW worker takes control IMMEDIATELY on every deploy —
// it does NOT wait for the full offline precache to finish first (that older behavior made
// updates slow and, on mobile, sometimes stuck mid-download so users kept seeing stale text).
// Instead:
//   • install  -> skipWaiting at once (no blocking work) so activation is instant
//   • activate -> claim the page, drop old caches, then precache everything in the BACKGROUND
//   • fetch    -> the small files that change on a content deploy (index.html + the derived
//                 JSON indexes) are NETWORK-FIRST when online, so an online user always sees
//                 the latest immediately; the cache is a fallback for offline. Everything else
//                 (per-parasha text, icons) is cache-first for instant, fully-offline loads.
const CACHE_VERSION = "v267";
const CACHE_PREFIX = "hy-cache-";
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;

async function postAll(msg) {
  const clients = await self.clients.matchAll({ includeUncontrolled: true });
  for (const c of clients) c.postMessage(msg);
}

// Fill the offline cache in the background. Runs AFTER the worker already controls the page,
// so it never delays the user seeing fresh content — it only backfills for offline use.
async function precacheAll() {
  const cache = await caches.open(CACHE_NAME);
  let urls = [];
  try {
    const res = await fetch("content/offline_manifest.json", { cache: "no-store" });
    urls = await res.json();
  } catch (e) { return; }
  let done = 0;
  await postAll({ type: "offline-progress", done: 0, total: urls.length });
  for (const url of urls) {
    try {
      if (!(await cache.match(url))) {
        const r = await fetch(url, { cache: "no-store" });
        if (r.ok) await cache.put(url, r.clone());
      }
    } catch (e) { /* ignore single-file failure, keep going */ }
    done++;
    if (done % 5 === 0 || done === urls.length) {
      await postAll({ type: "offline-progress", done, total: urls.length });
    }
  }
  await postAll({ type: "offline-ready", total: urls.length });
}

self.addEventListener("install", () => {
  // Become the active worker as fast as possible — no precache blocking the swap.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    await self.clients.claim();
    const names = await caches.keys();
    // Only ever drop OUR OWN old caches. `caches` is shared across the whole origin, so a
    // blanket delete would wipe the host site's caches when this app is embedded in it.
    await Promise.all(
      names.filter((n) => n.startsWith(CACHE_PREFIX) && n !== CACHE_NAME).map((n) => caches.delete(n))
    );
    // Fire-and-forget: control is already taken and the page is already showing fresh content;
    // this just backfills the offline cache without holding anything up.
    precacheAll();
  })());
});

// The derived indexes that change on a content deploy + the weekly pointer file (and any
// page navigation) are served NETWORK-FIRST when online, so a user who is online always
// sees the latest immediately; the offline cache is only a fallback. Everything else
// (rarely-changing per-parasha text, icons, fonts) stays cache-first for instant loads.
const NETWORK_FIRST =
  /\/content\/(topics|search_index|parashot|parasha_resolve)\.json(\?|$)|\/content\/week\/current\.json(\?|$)/;

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  // Only manage same-origin requests. The Ask engine loads transformers.js + a ~120MB model
  // from CDNs (jsdelivr / huggingface); those must NOT go into our versioned cache (a version
  // bump would evict and force a full re-download). Let the browser + transformers.js's own
  // cache handle them.
  if (new URL(event.request.url).origin !== self.location.origin) return;
  const navReq = event.request.mode === "navigate";
  const netFirst = navReq || NETWORK_FIRST.test(event.request.url);
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    if (netFirst) {
      try {
        const fresh = await fetch(event.request, { cache: "no-store" });
        if (fresh.ok) cache.put(event.request, fresh.clone());
        return fresh;
      } catch (e) {
        const cached = (await cache.match(event.request)) ||
                       (navReq ? await cache.match("index.html") : null);
        return cached || Response.error();
      }
    }
    // cache-first for the rarely-changing bulk (per-parasha text, icons, fonts)
    const cached = await cache.match(event.request);
    if (cached) return cached;
    try {
      const fresh = await fetch(event.request);
      if (fresh.ok) cache.put(event.request, fresh.clone());
      return fresh;
    } catch (e) {
      return cached || Response.error();
    }
  })());
});
