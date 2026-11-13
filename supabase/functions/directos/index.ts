// TORNEAZO · Edge Function "directos": dice qué streamers oficiales de un torneo público están en directo en Twitch.
// La llama la página pública con {code}. Lee el torneo con la clave del servidor, saca los canales de Twitch de
// data.streams y pregunta a la API de Twitch (Helix) con un token de aplicación. Solo datos públicos de Twitch.
// Necesita los secretos TWITCH_CLIENT_ID y TWITCH_CLIENT_SECRET (app gratuita en dev.twitch.tv).
// Desplegar con "Verify JWT" DESACTIVADO (la llaman visitantes sin cuenta).
const DB = Deno.env.get("SUPABASE_URL") ?? "";
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CID = Deno.env.get("TWITCH_CLIENT_ID") ?? "";
const CSEC = Deno.env.get("TWITCH_CLIENT_SECRET") ?? "";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// Canal de Twitch a partir del enlace que pone el organizador.
export function twitchLogin(u: string): string | null {
  const m = /^https?:\/\/(?:www\.|m\.)?twitch\.tv\/([A-Za-z0-9_]{3,25})(?:[/?#].*)?$/i.exec(String(u || "").trim());
  if (!m) return null;
  const l = m[1].toLowerCase();
  return ["directory", "videos", "search", "settings", "p", "downloads", "jobs", "turbo"].includes(l) ? null : l;
}

let tok = "", tokExp = 0;
async function appToken() {
  if (tok && Date.now() < tokExp - 60000) return tok;
  const r = await fetch("https://id.twitch.tv/oauth2/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CID, client_secret: CSEC, grant_type: "client_credentials" }),
  });
  if (!r.ok) throw new Error("token " + r.status);
  const j = await r.json();
  tok = j.access_token; tokExp = Date.now() + (j.expires_in || 3600) * 1000;
  return tok;
}

const cache = new Map<string, { t: number; d: unknown }>();
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);
  let body: any = {};
  try { body = await req.json() } catch { /* vacío */ }
  const code = String(body.code || "");
  if (!/^[a-z0-9]{10,16}$/.test(code)) return json({ error: "codigo" }, 400);
  const hit = cache.get(code);
  if (hit && Date.now() - hit.t < 60000) return json(hit.d);
  if (!CID || !CSEC) return json({ error: "sin_claves", live: {} });
  try {
    const tr = await fetch(`${DB}/rest/v1/tournaments?public_code=eq.${code}&hidden=eq.false&select=data`, { headers: { apikey: SR, Authorization: `Bearer ${SR}` } });
    const t = tr.ok ? (await tr.json())[0] : null;
    if (!t) return json({ error: "codigo" }, 404);
    const logins = [...new Set(((t.data && t.data.streams) || []).map((s: any) => twitchLogin(s && s.u)).filter(Boolean))].slice(0, 12) as string[];
    const live: Record<string, unknown> = {};
    if (logins.length) {
      const q = logins.map((l) => "user_login=" + encodeURIComponent(l)).join("&");
      let r = await fetch(`https://api.twitch.tv/helix/streams?${q}`, { headers: { "Client-ID": CID, Authorization: `Bearer ${await appToken()}` } });
      if (r.status === 401) { tok = ""; r = await fetch(`https://api.twitch.tv/helix/streams?${q}`, { headers: { "Client-ID": CID, Authorization: `Bearer ${await appToken()}` } }); }
      if (!r.ok) throw new Error("helix " + r.status);
      const j = await r.json();
      for (const s of j.data || []) {
        if (s.type !== "live") continue;
        live[String(s.user_login).toLowerCase()] = { v: s.viewer_count | 0, t: String(s.title || "").slice(0, 120), g: String(s.game_name || "").slice(0, 60), s: s.started_at };
      }
    }
    const d = { ok: true, live, at: new Date().toISOString() };
    cache.set(code, { t: Date.now(), d });
    if (cache.size > 500) cache.delete(cache.keys().next().value as string);
    return json(d);
  } catch (e) {
    console.error(e);
    return json({ error: "fallo", live: {} }, 502);
  }
});
