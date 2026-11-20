-- TORNEAZO · 1) inscripción por equipos  2) porra del público.

-- 1) Inscripción por equipos: el capitán apunta el nombre del equipo y a sus jugadores.
alter table public.registrations add column if not exists members jsonb
  check (members is null or (jsonb_typeof(members) = 'array' and jsonb_array_length(members) between 1 and 20));

create or replace function public.inscribir_equipo(p_code text, p_team text, p_members jsonb, p_contact text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t record; reg jsonb; cap int := 0; n int; ipv text; ih text; st text; nm text; ct text; mm jsonb := '[]'::jsonb; x text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  reg := coalesce(t.data -> 'reg', '{}'::jsonb);
  if jsonb_typeof(reg) <> 'object' or (reg -> 'open') is distinct from 'true'::jsonb then return jsonb_build_object('error','cerrado'); end if;
  if (reg -> 'team') is distinct from 'true'::jsonb then return jsonb_build_object('error','cerrado'); end if;
  if coalesce(reg ->> 'deadline','') ~ '^\d{4}-\d{2}-\d{2}$' and current_date > (reg ->> 'deadline')::date then
    return jsonb_build_object('error','plazo');
  end if;
  nm := btrim(coalesce(p_team,''));
  if char_length(nm) not between 1 and 40 then return jsonb_build_object('error','nombre'); end if;
  if p_members is null or jsonb_typeof(p_members) <> 'array' or jsonb_array_length(p_members) not between 1 and 20 then
    return jsonb_build_object('error','jugadores');
  end if;
  for x in select btrim(v) from jsonb_array_elements_text(p_members) v loop
    if char_length(x) not between 1 and 40 or x ~ '[:=*\n\r,]' then return jsonb_build_object('error','jugadores'); end if;
    if mm ? x then return jsonb_build_object('error','jugadores'); end if;
    mm := mm || to_jsonb(x);
  end loop;
  ct := nullif(left(btrim(coalesce(p_contact,'')), 80), '');
  if jsonb_typeof(reg -> 'max') = 'number' then cap := (reg ->> 'max')::numeric::int; end if;
  select count(*) into n from public.registrations where tournament_id = t.id and status <> 'rejected';
  if cap > 0 and n >= cap then return jsonb_build_object('error','lleno'); end if;
  begin
    ipv := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
  exception when others then ipv := '';
  end;
  ih := case when ipv <> '' then md5(ipv || p_code) else null end;
  if ih is not null and (select count(*) from public.registrations where tournament_id = t.id and ip_hash = ih and created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error','limite');
  end if;
  if (select count(*) from public.registrations where tournament_id = t.id and created_at > now() - interval '1 minute') >= 30 then
    return jsonb_build_object('error','limite');
  end if;
  st := case when (reg -> 'auto') is not distinct from 'true'::jsonb then 'approved' else 'pending' end;
  begin
    insert into public.registrations (tournament_id, name, contact, status, ip_hash, members)
    values (t.id, nm, ct, st, ih, mm);
  exception when unique_violation then
    return jsonb_build_object('error','duplicado');
  end;
  return jsonb_build_object('ok', true, 'status', st);
end $$;
revoke all on function public.inscribir_equipo(text, text, jsonb, text) from public;
grant execute on function public.inscribir_equipo(text, text, jsonb, text) to anon, authenticated;

-- 2) Porra: el público apuesta quién gana cada partido (sin dinero, solo puntos).
--    Cada móvil tiene un identificador al azar (voter) que nunca se devuelve tal cual.
create table if not exists public.predictions (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  voter text not null check (voter ~ '^[a-z0-9]{16,32}$'),
  name text not null check (char_length(name) between 1 and 30),
  match_key text not null check (match_key ~ '^(m:\d{1,4}|l:\d{1,4}|k:\d{1,2}:\d{1,4}|k3|d:\d{1,4})$'),
  pick smallint not null check (pick in (0, 1, 2)),
  ip_hash text,
  created_at timestamptz not null default now(),
  primary key (tournament_id, voter, match_key)
);
create index if not exists predictions_tid_idx on public.predictions (tournament_id);
alter table public.predictions enable row level security;
revoke all on public.predictions from anon, authenticated;

-- El partido de un torneo a partir de su clave (la misma que usa la app).
create or replace function public.partido_por_clave(d jsonb, k text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare p text[] := string_to_array(k, ':');
begin
  if k = 'k3' then return d -> 'k3'; end if;
  if p[1] = 'm' then return d -> 'matches' -> (p[2]::int); end if;
  if p[1] = 'l' then return d -> 'liga' -> 'matches' -> (p[2]::int); end if;
  if p[1] = 'k' then return d -> 'ko' -> (p[2]::int) -> (p[3]::int); end if;
  if p[1] = 'd' then return d -> 'de' -> 'm' -> (p[2]::int); end if;
  return null;
exception when others then return null;
end $$;

create or replace function public.porra_votar(p_code text, p_voter text, p_name text, p_key text, p_a int, p_b int, p_pick int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t record; m jsonb; nm text; ipv text; ih text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if (t.data -> 'porra') is distinct from 'true'::jsonb then return jsonb_build_object('error','cerrada'); end if;
  if p_voter is null or p_voter !~ '^[a-z0-9]{16,32}$' then return jsonb_build_object('error','voter'); end if;
  nm := btrim(coalesce(p_name,''));
  if char_length(nm) not between 1 and 30 then return jsonb_build_object('error','nombre'); end if;
  if p_key is null or p_key !~ '^(m:\d{1,4}|l:\d{1,4}|k:\d{1,2}:\d{1,4}|k3|d:\d{1,4})$' then return jsonb_build_object('error','partido'); end if;
  if p_pick is null or p_pick not in (0, 1, 2) then return jsonb_build_object('error','partido'); end if;
  m := public.partido_por_clave(t.data, p_key);
  -- El partido tiene que existir con esos dos rivales y no haberse jugado todavía.
  if m is null or jsonb_typeof(m) <> 'object' or (m ->> 'a') is distinct from p_a::text or (m ->> 'b') is distinct from p_b::text then
    return jsonb_build_object('error','partido');
  end if;
  if jsonb_typeof(m -> 'sa') = 'number' and jsonb_typeof(m -> 'sb') = 'number' then return jsonb_build_object('error','jugado'); end if;
  begin
    ipv := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
  exception when others then ipv := '';
  end;
  ih := case when ipv <> '' then md5(ipv || p_code || 'porra') else null end;
  if ih is not null and (select count(*) from public.predictions where tournament_id = t.id and ip_hash = ih and created_at > now() - interval '1 hour') >= 400 then
    return jsonb_build_object('error','limite');
  end if;
  if (select count(*) from public.predictions where tournament_id = t.id) >= 20000 then return jsonb_build_object('error','limite'); end if;
  insert into public.predictions (tournament_id, voter, name, match_key, pick, ip_hash)
  values (t.id, p_voter, nm, p_key, p_pick, ih)
  on conflict (tournament_id, voter, match_key) do update set pick = excluded.pick, name = excluded.name, created_at = now();
  -- El mismo móvil usa siempre el último nombre que ha escrito.
  update public.predictions set name = nm where tournament_id = t.id and voter = p_voter and name <> nm;
  return jsonb_build_object('ok', true);
end $$;

-- Votos de la porra de un torneo público. El identificador del móvil se devuelve cifrado.
create or replace function public.porra_datos(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('v', left(encode(sha256(convert_to(p.voter, 'UTF8')), 'hex'), 12), 'n', p.name, 'k', p.match_key, 'p', p.pick)), '[]'::jsonb)
  from public.tournaments t join public.predictions p on p.tournament_id = t.id
  where t.public_code = p_code and not t.hidden and char_length(p_code) between 10 and 16
$$;

revoke all on function public.partido_por_clave(jsonb, text) from public, anon, authenticated;
revoke all on function public.porra_votar(text, text, text, text, int, int, int) from public;
revoke all on function public.porra_datos(text) from public;
grant execute on function public.porra_votar(text, text, text, text, int, int, int) to anon, authenticated;
grant execute on function public.porra_datos(text) to anon, authenticated;
