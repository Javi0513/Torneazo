-- TORNEAZO · avisos al móvil (notificaciones push).
-- Un jugador, desde la página pública del torneo, elige su nombre y activa los avisos: se guarda la suscripción
-- de su navegador (push_subs). La función "avisos" envía "Te toca jugar" por turnos y recordatorios ~15 min
-- antes de los partidos con hora. push_sent evita mandar el mismo aviso dos veces.

create table if not exists public.push_subs (
  id bigint generated always as identity primary key,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  team_id int not null check (team_id between 0 and 9999),
  endpoint text not null check (endpoint ~ '^https://' and char_length(endpoint) <= 800),
  p256dh text not null check (p256dh ~ '^[A-Za-z0-9_-]{80,100}$'),
  auth text not null check (auth ~ '^[A-Za-z0-9_-]{16,30}$'),
  created_at timestamptz not null default now(),
  unique (tournament_id, endpoint)
);
create index if not exists push_subs_team_idx on public.push_subs (tournament_id, team_id);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;

create table if not exists public.push_sent (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  key text not null check (char_length(key) <= 120),
  sent_at timestamptz not null default now(),
  primary key (tournament_id, key)
);
alter table public.push_sent enable row level security;
revoke all on public.push_sent from anon, authenticated;

-- Activar avisos (un dispositivo sigue a un jugador por torneo; si cambia de jugador se sustituye).
create or replace function public.avisos_alta(p_code text, p_team int, p_endpoint text, p_p256dh text, p_auth text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t record; n int;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if p_team is null or p_team < 0 or p_team >= coalesce(jsonb_array_length(t.data -> 'teams'), 0) then return jsonb_build_object('error','jugador'); end if;
  if p_endpoint is null or p_endpoint !~ '^https://' or char_length(p_endpoint) > 800
     or p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_-]{80,100}$' or p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{16,30}$' then
    return jsonb_build_object('error','suscripcion');
  end if;
  select count(*) into n from public.push_subs where tournament_id = t.id;
  if n >= 2000 then return jsonb_build_object('error','limite'); end if;
  insert into public.push_subs (tournament_id, team_id, endpoint, p256dh, auth) values (t.id, p_team, p_endpoint, p_p256dh, p_auth)
  on conflict (tournament_id, endpoint) do update set team_id = excluded.team_id, p256dh = excluded.p256dh, auth = excluded.auth;
  return jsonb_build_object('ok', true);
end $$;

-- Desactivar avisos de este dispositivo en un torneo.
create or replace function public.avisos_baja(p_code text, p_endpoint text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.push_subs s using public.tournaments t
  where s.tournament_id = t.id and t.public_code = p_code and s.endpoint = p_endpoint;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.avisos_alta(text, int, text, text, text) from public;
revoke all on function public.avisos_baja(text, text) from public;
grant execute on function public.avisos_alta(text, int, text, text, text) to anon, authenticated;
grant execute on function public.avisos_baja(text, text) to anon, authenticated;

-- Recordatorios: cada 5 minutos se llama a la función "avisos" (pg_cron + pg_net).
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.unschedule('torneazo-avisos') where exists (select 1 from cron.job where jobname = 'torneazo-avisos');
select cron.schedule('torneazo-avisos', '*/5 * * * *', $cron$
  select net.http_post(
    url := 'https://qflfsqomewjxebvdhgfo.supabase.co/functions/v1/avisos',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('mode', 'cron')
  );
$cron$);
