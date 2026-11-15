// TORNEAZO · Edge Function "discord": publica en el canal de Discord del torneo (resultados, sorteo, campeón).
// La llama la app del organizador o de un co-organizador con su sesión. Comprueba que puede ver el torneo,
// lee el enlace secreto del canal (tabla tournament_hooks, solo servidor) y envía los mensajes.
// Desplegar con "Verify JWT" ACTIVADO (solo usuarios con cuenta).
const DB = Deno.env.get("SUPABASE_URL") ?? "";
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HOOK = /^https:\/\/(discord|discordapp)\.com\/api\/webhooks\/[0-9]{5,30}\/[A-Za-z0-9_-]{20,100}$/;
const txt = (v: unknown, n: number) => String(v ?? "").replace(/@(everyone|here)/g, "@​$1").slice(0, n);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);
  let body: any = {};
  try { body = await req.json() } catch { /* vacío */ }
  const tid = String(body.tid || "");
  if (!UUID.test(tid)) return json({ error: "torneo" }, 400);
  const auth = req.headers.get("authorization") || "";
  const v = await fetch(`${DB}/rest/v1/tournaments?id=eq.${tid}&select=id`, { headers: { apikey: ANON, Authorization: auth } });
  if (!(v.ok && (await v.json()).length === 1)) return json({ error: "permiso" }, 403);
  const h = await fetch(`${DB}/rest/v1/tournament_hooks?tournament_id=eq.${tid}&select=discord`, { headers: { apikey: SR, Authorization: `Bearer ${SR}` } });
  const url = h.ok ? ((await h.json())[0] || {}).discord : null;
  if (!url || !HOOK.test(url)) return json({ error: "sin_canal" }, 404);
  const embeds = (Array.isArray(body.embeds) ? body.embeds : []).slice(0, 10).map((e: any) => ({
    title: txt(e.title, 240),
    description: txt(e.desc, 3500),
    color: Number.isInteger(e.color) ? e.color : 0x9bea1c,
    url: typeof e.url === "string" && /^https:\/\/torneazo\.monetizaplus\.com\//.test(e.url) ? e.url : undefined,
    fields: (Array.isArray(e.fields) ? e.fields : []).slice(0, 10).map((f: any) => ({ name: txt(f.name, 240) || "·", value: txt(f.value, 1000) || "·", inline: !!f.inline })),
    footer: { text: "TORNEAZO by JAVI AI" },
  }));
  if (!embeds.length) return json({ error: "vacio" }, 400);
  const r = await fetch(url + "?wait=false", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: "TORNEAZO", allowed_mentions: { parse: [] }, embeds }),
  });
  if (r.status === 404) return json({ error: "canal_borrado" }, 410);
  if (!r.ok) return json({ error: "discord", status: r.status }, 502);
  return json({ ok: true });
});
