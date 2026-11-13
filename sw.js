/* Service worker de TORNEAZO.
   - Código (html/js/css/config/version): primero red, para que las actualizaciones lleguen enseguida;
     si no hay conexión, usa la copia guardada (la app abre sin internet).
   - Letras, iconos y librería: primero la copia guardada (no cambian).
   - Las llamadas a Supabase NO se tocan nunca. */
const VERSION = "1.38.0";
const CACHE = "torneazo-" + VERSION;
const SHELL = [
  "./",
  "index.html",
  "config.js",
  "app.js",
  "version.json",
  "supabase.js",
  "manifest.webmanifest",
  "manifest-torneo.webmanifest",
  "favicon.png",
  "apple-touch-icon.png",
  "icon-192.png",
  "icon-512.png",
  "icon-maskable-512.png",
  "fondo.webp",
  "fondo-movil.webp",
  "qrcode.js",
];
const NETWORK_FIRST = /\.(html|js|css|json)$|\/$/;

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) =>
        Promise.all(
          SHELL.map((u) =>
            fetch(u, { cache: "no-store" })
              .then((r) => r.ok && c.put(u, r))
              .catch(() => {}),
          ),
        ),
      )
      .then(() => self.skipWaiting()),
  );
});
// La app pide activar la versión nueva cuando el usuario pulsa «Actualizar».
self.addEventListener("message", (e) => {
  if (e.data === "skip") self.skipWaiting();
});
self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((ks) =>
        Promise.all(
          ks
            .filter((k) => k.startsWith("torneazo-") && k !== CACHE)
            .map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // Supabase, Cloudflare, etc.: no se tocan
  if (url.pathname.endsWith("/sw.js")) return;
  const networkFirst =
    req.mode === "navigate" || NETWORK_FIRST.test(url.pathname);
  if (networkFirst) {
    /* Con poca cobertura (en el campo) no se espera más de 5 s a la red:
       si hay copia guardada se abre con ella y la versión nueva llega la próxima vez. */
    const red = fetch(req, { cache: "no-store" }).then((r) => {
      if (r.ok) {
        const copy = r.clone();
        caches.open(CACHE).then((c) => c.put(req, copy));
      }
      return r;
    });
    const copia = () =>
      caches
        .match(req, { ignoreSearch: true })
        .then((m) => m || (req.mode === "navigate" ? caches.match("index.html") : undefined));
    e.respondWith(
      new Promise((ok, ko) => {
        let hecho = false;
        const t = setTimeout(() => {
          copia().then((m) => {
            if (m && !hecho) {
              hecho = true;
              ok(m);
            }
          });
        }, 5000);
        red
          .then((r) => {
            clearTimeout(t);
            if (!hecho) {
              hecho = true;
              ok(r);
            }
          })
          .catch(() => {
            clearTimeout(t);
            copia().then((m) => {
              if (hecho) return;
              hecho = true;
              m ? ok(m) : ko(new Error("sin red"));
            });
          });
      }),
    );
  } else {
    e.respondWith(
      caches.match(req, { ignoreSearch: true }).then(
        (m) =>
          m ||
          fetch(req).then((r) => {
            if (r.ok) {
              const copy = r.clone();
              caches.open(CACHE).then((c) => c.put(req, copy));
            }
            return r;
          }),
      ),
    );
  }
});

// Avisos al móvil (push): muestra la notificación y abre el torneo al tocarla.
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "TORNEAZO", body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(String(d.title || "TORNEAZO").slice(0, 80), {
    body: String(d.body || "").slice(0, 200),
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { url: d.url || "./" },
  }));
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "./";
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) if (c.url.split("#")[0] === url && "focus" in c) return c.focus();
    return self.clients.openWindow(url);
  }));
});
