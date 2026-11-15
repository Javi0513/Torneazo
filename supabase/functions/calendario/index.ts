// TORNEAZO · Edge Function "calendario": calendario (.ics) de un torneo público al que se suscribe el móvil.
// GET ?t=<código público>[&j=<número de jugador>] → los partidos con fecha (de todos o de ese jugador).
// El calendario del móvil lo vuelve a pedir cada cierto tiempo, así que los cambios de hora llegan solos.
// Desplegar con "Verify JWT" DESACTIVADO (lo piden los calendarios, sin sesión). Solo lee torneos públicos.
const DB = Deno.env.get("SUPABASE_URL") ?? "";
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SITE = "https://torneazo.monetizaplus.com/";

type M = { a?: number | null; b?: number | null; sa?: number | null; sb?: number | null; t?: string; c?: string; bye?: boolean; sec?: string; r?: number };
function partidos(d: any): { key: string; m: M; lab: string }[] {
  const L: { key: string; m: M; lab: string }[] = [];
  const G = (d.groupsList || []).length;
  (d.matches || []).forEach((m: any, i: number) => L.push({ key: "m" + i, m, lab: d.format == "suizo" ? "Ronda " + ((+m.r || 0) + 1) : m.j != null ? "Jornada " + (m.j + 1) : G > 1 ? "Fase de grupos" : "" }));
  if (d.liga) (d.liga.matches || []).forEach((m: M, i: number) => L.push({ key: "l" + i, m, lab: "Nuevo grupo" }));
  if (d.ko) d.ko.forEach((r: M[], ri: number) => r.forEach((m, i) => { if (!m.bye) L.push({ key: `k${ri}-${i}`, m, lab: ri == d.ko.length - 1 ? "Final" : ri == d.ko.length - 2 ? "Semifinales" : "Eliminatoria" }) }));
  if (d.ko && d.third && d.k3) L.push({ key: "k3", m: d.k3, lab: "Tercer puesto" });
  if (d.de) (d.de.m || []).forEach((m: M, i: number) => L.push({ key: "d" + i, m, lab: m.sec == "g" ? "Gran final" : m.sec == "l" ? "Cuadro de perdedores" : "Cuadro de ganadores" }));
  return L;
}
function aUtc(local: string, tz: string): number {
  const [f, h] = local.split("T"), [y, mo, da] = f.split("-").map(Number), [hh, mi] = h.split(":").map(Number);
  let guess = Date.UTC(y, mo - 1, da, hh, mi);
  for (let k = 0; k < 2; k++) {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
      .formatToParts(new Date(guess)).filter((x) => x.type !== "literal").map((x) => [x.type, +x.value]));
    guess += Date.UTC(y, mo - 1, da, hh, mi) - Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
  }
  return guess;
}
const esc = (t: unknown) => String(t ?? "").replace(/\\/g, "\\\\").replace(/;/g, "\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const stamp = (ms: number) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
// Las líneas de un .ics no deben pasar de 75 octetos: se parten con un espacio al principio.
const fold = (l: string) => { const b = new TextEncoder().encode(l); if (b.length <= 74) return l; const out: string[] = []; let cur = ""; for (const ch of l) { if (new TextEncoder().encode(cur + ch).length > 73) { out.push(cur); cur = " " + ch } else cur += ch } out.push(cur); return out.join("\r\n") };

Deno.serve(async (req) => {
  const u = new URL(req.url), code = u.searchParams.get("t") || "", j = u.searchParams.get("j");
  if (!/^[a-z0-9]{10,16}$/.test(code)) return new Response("Calendario no encontrado", { status: 404 });
  const r = await fetch(`${DB}/rest/v1/tournaments?public_code=eq.${code}&hidden=eq.false&select=name,data`, { headers: { apikey: SR, Authorization: `Bearer ${SR}` } });
  const t = r.ok ? (await r.json())[0] : null;
  if (!t) return new Response("Calendario no encontrado", { status: 404 });
  const d = t.data || {}, T = d.teams || [], tz = typeof d.tz === "string" && d.tz ? d.tz : "Europe/Madrid";
  const team = j != null && /^\d{1,4}$/.test(j) && T[+j] ? +j : null;
  const nm = (id: any) => id == null || id === -1 ? "Por decidir" : String((T.find((x: any) => x.id === id) || T[id] || {}).name || "?");
  const dur = Math.min(600, Math.max(5, +((d.cal || {}).dur) || 30));
  const name = String(t.name || d.name || "Torneo").slice(0, 80), now = stamp(Date.now());
  const out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//TORNEAZO//JAVI AI//ES", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "X-WR-CALNAME:" + esc(team != null ? `${nm(team)} · ${name}` : name), "X-WR-TIMEZONE:" + tz, "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H"];
  for (const x of partidos(d).slice(0, 600)) {
    const m = x.m;
    if (!m || !m.t || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(m.t)) continue;
    if (team != null && m.a !== team && m.b !== team) continue;
    let st: number; try { st = aUtc(m.t, tz) } catch { continue }
    const res = m.sa != null && m.sb != null ? ` (${m.sa}-${m.sb})` : "";
    out.push("BEGIN:VEVENT", `UID:${x.key}-${code}@torneazo`, "DTSTAMP:" + now, "DTSTART:" + stamp(st), "DTEND:" + stamp(st + dur * 60000),
      fold("SUMMARY:" + esc(`${nm(m.a)} vs ${nm(m.b)}${res} · ${name}`)));
    if (m.c) out.push(fold("LOCATION:" + esc(m.c)));
    out.push(fold("DESCRIPTION:" + esc(`${x.lab ? x.lab + ". " : ""}Sigue el torneo en directo: ${SITE}?t=${code}`)), fold("URL:" + `${SITE}?t=${code}`), "END:VEVENT");
  }
  out.push("END:VCALENDAR");
  return new Response(out.join("\r\n") + "\r\n", { headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "public, max-age=600", "Content-Disposition": `inline; filename="torneo.ics"` } });
});
