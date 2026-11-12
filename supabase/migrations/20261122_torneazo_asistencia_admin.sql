-- TORNEAZO · 1) confirmar asistencia desde el QR  2) resumen para el panel de administración.

-- 1) Asistencia: el día del torneo cada jugador abre el enlace o el QR, elige su nombre y pulsa «Estoy aquí».
--    Solo si el organizador lo ha activado (data.selfCk) y el nombre está en la lista de participantes.
create table if not exists public.checkins (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  ip_hash text,
  created_at timestamptz not null default now(),
  primary key (tournament_id, name)
);
alter table public.checkins enable row level security;
revoke all on public.checkins from anon, authenticated;
grant select, delete on public.checkins to authenticated;

drop policy if exists "asistencia: ver la de mis torneos" on public.checkins;
create policy "asistencia: ver la de mis torneos" on public.checkins for select to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));
drop policy if exists "asistencia: borrar la de mis torneos" on public.checkins;
create policy "asistencia: borrar la de mis torneos" on public.checkins for delete to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));

create or replace function public.confirmar_asistencia(p_code text, p_name text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; nm text; ipv text; ih text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if (t.data -> 'selfCk') is distinct from 'true'::jsonb then return jsonb_build_object('error','cerrado'); end if;
  nm := lower(btrim(coalesce(p_name,'')));
  if char_length(nm) not between 1 and 40 then return jsonb_build_object('error','nombre'); end if;
  -- El nombre tiene que estar en la lista (se ignora el nivel escrito detrás, por ejemplo "Ana: 3").
  if not exists (
    select 1 from regexp_split_to_table(coalesce(t.data ->> 'players',''), E'\n') l
    where left(lower(btrim(l)), char_length(nm)) = nm
      and btrim(substr(lower(btrim(l)), char_length(nm) + 1)) ~ '^([:=*].*)?$'
  ) then return jsonb_build_object('error','nombre'); end if;
  begin
    ipv := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
  exception when others then ipv := '';
  end;
  ih := case when ipv <> '' then md5(ipv || p_code || 'ck') else null end;
  if ih is not null and (select count(*) from public.checkins where tournament_id = t.id and ip_hash = ih and created_at > now() - interval '1 hour') >= 8 then
    return jsonb_build_object('error','limite');
  end if;
  if (select count(*) from public.checkins where tournament_id = t.id) >= 600 then return jsonb_build_object('error','limite'); end if;
  insert into public.checkins (tournament_id, name, ip_hash) values (t.id, nm, ih) on conflict (tournament_id, name) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.confirmar_asistencia(text, text) from public;
grant execute on function public.confirmar_asistencia(text, text) to anon, authenticated;

-- 2) Panel de administración: solo cifras generales, nunca datos personales. Solo para administradores.
create or replace function public.admin_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin) then
    return jsonb_build_object('error','permiso');
  end if;
  return jsonb_build_object(
    'usuarios', (select count(*) from auth.users),
    'usuarios_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'usuarios_30d', (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'premium', (select count(*) from public.profiles where coalesce(is_premium,false)),
    'torneos', (select count(*) from public.tournaments),
    'torneos_7d', (select count(*) from public.tournaments where created_at > now() - interval '7 days'),
    'activos_7d', (select count(*) from public.tournaments where updated_at > now() - interval '7 days'),
    'publicos', (select count(*) from public.tournaments where public_code is not null),
    'directorio', (select count(*) from public.tournaments where public_code is not null and coalesce(listed,false)),
    'ocultos', (select count(*) from public.tournaments where hidden),
    'inscripciones', (select count(*) from public.registrations),
    'resultados_jugadores', (select count(*) from public.result_reports),
    'avisos', (select count(*) from public.push_subs),
    'coorganizadores', (select count(*) from public.tournament_editors),
    'asistencias', (select count(*) from public.checkins),
    'juegos', coalesce((select jsonb_agg(x) from (
      select coalesce(nullif(data ->> 'game',''),'Otro') as juego, count(*) as n
      from public.tournaments group by 1 order by 2 desc limit 10) x), '[]'::jsonb),
    'dias', coalesce((select jsonb_agg(x order by x.dia) from (
      select to_char(d, 'YYYY-MM-DD') as dia,
        (select count(*) from public.tournaments t where t.created_at >= d and t.created_at < d + interval '1 day') as torneos,
        (select count(*) from auth.users u where u.created_at >= d and u.created_at < d + interval '1 day') as usuarios
      from generate_series(date_trunc('day', now()) - interval '13 days', date_trunc('day', now()), interval '1 day') d) x), '[]'::jsonb)
  );
end $$;
revoke all on function public.admin_resumen() from public, anon;
grant execute on function public.admin_resumen() to authenticated;
