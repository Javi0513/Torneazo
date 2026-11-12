// TORNEAZO · Edge Function "avisos": envía notificaciones al móvil de los jugadores.
//  - mode "turno" (lo llama la app del organizador al apuntar un resultado): avisa al turno actual ("Te toca jugar")
//    y al siguiente ("Prepárate"). Solo si quien llama puede ver el torneo (dueño o co-organizador).
//  - mode "cron" (lo llama pg_cron cada 5 minutos): recordatorio ~15 minutos antes de los partidos con hora.
// Cada aviso se envía una sola vez (tabla push_sent). Necesita los secretos VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY y VAPID_SUBJECT.
// Desplegar con "Verify JWT" DESACTIVADO (pg_cron no manda token de usuario).
import { send } from "./webpush.js";

const DB = Deno.env.get("SUPABASE_URL") ?? "";
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SITE = "https://torneazo.monetizaplus.com/";
const VAPID = {
  pub: Deno.env.get("VAPID_PUBLIC_KEY") ?? "",
  priv: Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
  subject: Deno.env.get("VAPID_SUBJECT") ?? "mailto:javiadsense@gmail.com",
};
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const rest = (path: string, opt: RequestInit = {}) =>
  fetch(`${DB}/rest/v1/${path}`, {
    ...opt,
    headers: { apikey: SR, Authorization: `Bearer ${SR}`, "Content-Type": "application/json", ...(opt.headers || {}) },
  });

type M = { a?: number | null; b?: number | null; sa?: number | null; sb?: number | null; t?: string; c?: string; o?: number; bye?: boolean };
// Misma lista de partidos que la app (clave → partido)
function partidos(d: any): { key: string; m: M }[] {
  const L: { key: string; m: M }[] = [];
  (d.matches || []).forEach((m: M, i: number) => L.push({ key: "m:" + i, m }));
  if (d.liga) (d.liga.matches || []).forEach((m: M, i: number) => L.push({ key: "l:" + i, m }));
  if (d.ko) d.ko.forEach((r: M[], ri: number) => r.forEach((m, i) => { if (!m.bye) L.push({ key: `k:${ri}:${i}`, m }) }));
  if (d.ko && d.third && d.k3) L.push({ key: "k3", m: d.k3 });
  if (d.de) (d.de.m || []).forEach((m: M, i: number) => L.push({ key: "d:" + i, m }));
  return L.filter((x) => x.m && x.m.a != null && x.m.b != null && x.m.a !== -1 && x.m.b !== -1 && !(x.m.sa != null && x.m.sb != null));
}
const nombre = (d: any, id: number) => String((d.teams || [])[id]?.name ?? "tu rival").slice(0, 40);

// Hora local del torneo (zona IANA) → instante UTC
function aUtc(local: string, tz: string): number {
  const [f, h] = local.split("T"), [y, mo, da] = f.split("-").map(Number), [hh, mi] = h.split(":").map(Number);
  let guess = Date.UTC(y, mo - 1, da, hh, mi);
  for (let k = 0; k < 2; k++) {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
      .formatToParts(new Date(guess)).filter((x) => x.type !== "literal").map((x) => [x.type, +x.value]));
    const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
    guess += Date.UTC(y, mo - 1, da, hh, mi) - shown;
  }
  return guess;
}

// Marca el aviso como enviado; devuelve false si ya se había enviado.
async function marcar(tid: string, key: string) {
  const r = await rest("push_sent", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=representation" }, body: JSON.stringify({ tournament_id: tid, key }) });
  if (!r.ok) return false;
  const j = await r.json().catch(() => []);
  return Array.isArray(j) && j.length > 0;
}
async function avisar(t: any, team: number, key: string, title: string, body: string) {
  if (!(await marcar(t.id, key))) return 0;
  const r = await rest(`push_subs?tournament_id=eq.${t.id}&team_id=eq.${team}&select=id,endpoint,p256dh,auth`);
  const subs = r.ok ? await r.json() : [];
  let n = 0;
  for (const s of subs) {
    try {
      const st = await send(s, { title, body, url: t.public_code ? `${SITE}?t=${t.public_code}` : SITE, tag: key }, VAPID);
      if (st === 404 || st === 410) await rest(`push_subs?id=eq.${s.id}`, { method: "DELETE" });
      else if (st < 300) n++;
    } catch (e) { console.error(e) }
  }
  return n;
}

async function turno(t: any) {
  const d = t.data || {}, L = partidos(d).filter((x) => x.m.o).sort((x, y) => (x.m.o as number) - (y.m.o as number));
  if (!L.length) return 0;
  const t0 = L[0].m.o as number, nx = L.find((x) => (x.m.o as number) > t0), t1 = nx ? (nx.m.o as number) : null;
  let n = 0;
  for (const x of L.filter((x) => x.m.o === t0)) for (const [me, rv] of [[x.m.a, x.m.b], [x.m.b, x.m.a]] as number[][])
    n += await avisar(t, me, `o${t0}:${x.key}:${me}:ya`, `Te toca jugar · Turno ${t0}`, `Contra ${nombre(d, rv)}${x.m.c ? " · " + x.m.c : ""}. ¡Suerte!`);
  if (t1 != null) for (const x of L.filter((x) => x.m.o === t1)) for (const [me, rv] of [[x.m.a, x.m.b], [x.m.b, x.m.a]] as number[][])
    n += await avisar(t, me, `o${t1}:${x.key}:${me}:pre`, `Prepárate: juegas en el turno ${t1}`, `Después del turno actual, contra ${nombre(d, rv)}.`);
  return n;
}

async function recordatorios() {
  const r = await rest("push_subs?select=tournament_id");
  const ids = [...new Set(((r.ok ? await r.json() : []) as any[]).map((x) => x.tournament_id))].slice(0, 200);
  let n = 0;
  const now = Date.now();
  for (const id of ids) {
    const tr = await rest(`tournaments?id=eq.${id}&select=id,name,data,public_code`);
    const t = tr.ok ? (await tr.json())[0] : null;
    if (!t) continue;
    const d = t.data || {}, tz = typeof d.tz === "string" && d.tz ? d.tz : "Europe/Madrid";
    for (const x of partidos(d)) {
      if (!x.m.t || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(x.m.t)) continue;
      let at: number; try { at = aUtc(x.m.t, tz) } catch { at = aUtc(x.m.t, "Europe/Madrid") }
      const falta = at - now;
      if (falta < 0 || falta > 16 * 60000) continue;
      const hora = x.m.t.slice(11);
      for (const [me, rv] of [[x.m.a, x.m.b], [x.m.b, x.m.a]] as number[][])
        n += await avisar(t, me, `t:${x.key}:${x.m.t}:${me}`, `Tu partido empieza a las ${hora}`, `Contra ${nombre(d, rv)}${x.m.c ? " · " + x.m.c : ""}. ${String(d.name || "").slice(0, 40)}`);
    }
  }
  return n;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("ok", { headers: CORS });
  if (!VAPID.pub || !VAPID.priv) return new Response(JSON.stringify({ error: "sin claves" }), { status: 500, headers: CORS });
  let body: any = {};
  try { body = await req.json() } catch { /* vacío */ }
  try {
    if (body.mode === "turno") {
      const tid = String(body.tid || "");
      if (!UUID.test(tid)) return new Response(JSON.stringify({ error: "torneo" }), { status: 400, headers: CORS });
      // ¿Puede quien llama ver el torneo? (dueño o co-organizador, según las reglas de acceso)
      const auth = req.headers.get("authorization") || "";
      const v = await fetch(`${DB}/rest/v1/tournaments?id=eq.${tid}&select=id`, { headers: { apikey: ANON, Authorization: auth } });
      const ok = v.ok ? (await v.json()).length === 1 : false;
      if (!ok) return new Response(JSON.stringify({ error: "permiso" }), { status: 403, headers: CORS });
      const tr = await rest(`tournaments?id=eq.${tid}&select=id,name,data,public_code`);
      const t = tr.ok ? (await tr.json())[0] : null;
      const n = t ? await turno(t) : 0;
      return new Response(JSON.stringify({ ok: true, enviados: n }), { headers: { ...CORS, "Content-Type": "application/json" } });
    }
    const n = await recordatorios();
    return new Response(JSON.stringify({ ok: true, enviados: n }), { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: "fallo" }), { status: 500, headers: CORS });
  }
});
