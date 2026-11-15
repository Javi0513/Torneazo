-- TORNEAZO · 1) avisos al móvil del organizador  2) resultados automáticos en Discord.

-- 1) Avisos para el organizador (y co-organizadores): nueva inscripción, resultado enviado por un jugador
--    o asistencia confirmada por QR. Cada móvil se guarda con el usuario que lo activa.
create table if not exists public.org_push (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null check (endpoint ~ '^https://' and char_length(endpoint) <= 800),
  p256dh text not null check (p256dh ~ '^[A-Za-z0-9_-]{80,100}$'),
  auth text not null check (auth ~ '^[A-Za-z0-9_-]{16,30}$'),
  created_at timestamptz not null default now(),
  unique (endpoint)
);
create index if not exists org_push_user_idx on public.org_push (user_id);
alter table public.org_push enable row level security;
revoke all on public.org_push from anon, authenticated;

create or replace function public.org_avisos_alta(p_endpoint text, p_p256dh text, p_auth text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then return jsonb_build_object('error','cuenta'); end if;
  if p_endpoint is null or p_endpoint !~ '^https://' or char_length(p_endpoint) > 800
     or p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_-]{80,100}$' or p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{16,30}$' then
    return jsonb_build_object('error','suscripcion');
  end if;
  if (select count(*) from public.org_push where user_id = uid) >= 10 then
    delete from public.org_push where id = (select id from public.org_push where user_id = uid order by created_at limit 1);
  end if;
  insert into public.org_push (user_id, endpoint, p256dh, auth) values (uid, p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.org_avisos_baja(p_endpoint text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.org_push where endpoint = p_endpoint and user_id = (select auth.uid());
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.org_avisos_estado(p_endpoint text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('on', exists (select 1 from public.org_push where endpoint = p_endpoint and user_id = (select auth.uid())))
$$;

revoke all on function public.org_avisos_alta(text, text, text) from public, anon;
revoke all on function public.org_avisos_baja(text) from public, anon;
revoke all on function public.org_avisos_estado(text) from public, anon;
grant execute on function public.org_avisos_alta(text, text, text) to authenticated;
grant execute on function public.org_avisos_baja(text) to authenticated;
grant execute on function public.org_avisos_estado(text) to authenticated;

-- Al llegar una inscripción, un resultado de jugador o una asistencia, se avisa a la función "avisos".
-- La función no se fía del aviso: mira ella misma lo nuevo de ese torneo y lo envía una sola vez.
create extension if not exists pg_net;
create or replace function public.avisar_organizador() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://qflfsqomewjxebvdhgfo.supabase.co/functions/v1/avisos',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('mode', 'org', 'tid', new.tournament_id)
  );
  return null;
exception when others then return null;
end $$;
revoke all on function public.avisar_organizador() from public, anon, authenticated;

drop trigger if exists avisar_org_inscripcion on public.registrations;
create trigger avisar_org_inscripcion after insert on public.registrations for each row execute function public.avisar_organizador();
drop trigger if exists avisar_org_resultado on public.result_reports;
create trigger avisar_org_resultado after insert on public.result_reports for each row execute function public.avisar_organizador();
drop trigger if exists avisar_org_asistencia on public.checkins;
create trigger avisar_org_asistencia after insert on public.checkins for each row execute function public.avisar_organizador();

-- 2) Discord: el enlace (webhook) del canal es secreto. Se guarda aparte, nunca en los datos públicos del torneo,
--    y nadie lo puede leer desde la app: solo la función "discord" del servidor.
create table if not exists public.tournament_hooks (
  tournament_id uuid primary key references public.tournaments(id) on delete cascade,
  discord text check (discord ~ '^https://(discord|discordapp)\.com/api/webhooks/[0-9]{5,30}/[A-Za-z0-9_-]{20,100}$'),
  updated_at timestamptz not null default now()
);
alter table public.tournament_hooks enable row level security;
revoke all on public.tournament_hooks from anon, authenticated;

create or replace function public.discord_guardar(p_tid uuid, p_url text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (public.es_dueno(p_tid) or public.es_coorganizador(p_tid)) then return jsonb_build_object('error','permiso'); end if;
  if p_url is null or btrim(p_url) = '' then
    delete from public.tournament_hooks where tournament_id = p_tid;
    return jsonb_build_object('ok', true, 'on', false);
  end if;
  if btrim(p_url) !~ '^https://(discord|discordapp)\.com/api/webhooks/[0-9]{5,30}/[A-Za-z0-9_-]{20,100}$' then
    return jsonb_build_object('error','enlace');
  end if;
  insert into public.tournament_hooks (tournament_id, discord, updated_at) values (p_tid, btrim(p_url), now())
  on conflict (tournament_id) do update set discord = excluded.discord, updated_at = now();
  return jsonb_build_object('ok', true, 'on', true);
end $$;

create or replace function public.discord_estado(p_tid uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.es_dueno(p_tid) or public.es_coorganizador(p_tid)) then return jsonb_build_object('error','permiso'); end if;
  return jsonb_build_object('on', exists (select 1 from public.tournament_hooks where tournament_id = p_tid and discord is not null));
end $$;

revoke all on function public.discord_guardar(uuid, text) from public, anon;
revoke all on function public.discord_estado(uuid) from public, anon;
grant execute on function public.discord_guardar(uuid, text) to authenticated;
grant execute on function public.discord_estado(uuid) to authenticated;
