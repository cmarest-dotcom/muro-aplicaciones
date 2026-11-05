// Only cache the application shell. Data and auth are always requested live.
const CACHE='muro-shell-v7';
const SHELL=['./','./index.html','./manifest.webmanifest','./config.js','./icons/icon-192.png','./icons/icon-512.png'];
self.addEventListener('install', event=>event.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{const req=event.request;if(req.method!=='GET'||new URL(req.url).origin!==location.origin)return;event.respondWith(fetch(req).then(response=>{if(response.ok&&SHELL.some(f=>new URL(f,self.registration.scope).href===req.url)){const copy=response.clone();caches.open(CACHE).then(c=>c.put(req,copy));}return response}).catch(()=>caches.match(req).then(cached=>cached||Response.error())))});
