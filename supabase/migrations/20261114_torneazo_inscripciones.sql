-- TORNEAZO · inscripciones con enlace.
-- Los jugadores se apuntan desde la página pública SIN cuenta, solo mediante la función inscribirse()
-- (no hay acceso directo a la tabla). El organizador ve y gestiona las inscripciones de SUS torneos.

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  contact text check (contact is null or char_length(contact) <= 80),
  level int check (level is null or level between 1 and 12),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  imported boolean not null default false,
  ip_hash text,
  created_at timestamptz not null default now()
);
create index if not exists registrations_tournament_idx on public.registrations (tournament_id, created_at);
create unique index if not exists registrations_unique_name on public.registrations (tournament_id, lower(name));

alter table public.registrations enable row level security;
revoke all on public.registrations from anon, authenticated;
grant select, delete on public.registrations to authenticated;
grant update (status, imported) on public.registrations to authenticated;

drop policy if exists "inscripciones: ver las de mis torneos" on public.registrations;
create policy "inscripciones: ver las de mis torneos" on public.registrations for select to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));
drop policy if exists "inscripciones: editar las de mis torneos" on public.registrations;
create policy "inscripciones: editar las de mis torneos" on public.registrations for update to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));
drop policy if exists "inscripciones: borrar las de mis torneos" on public.registrations;
create policy "inscripciones: borrar las de mis torneos" on public.registrations for delete to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));

-- Apuntarse. Comprueba que las inscripciones están abiertas, el plazo, el cupo, que no haya repetidos
-- y limita los intentos (5 por hora y dispositivo, 30 por minuto en el torneo).
create or replace function public.inscribirse(p_code text, p_name text, p_contact text default null, p_level int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t record; reg jsonb; cap int := 0; n int; ipv text; ih text; st text; nm text; ct text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code;
  if not found then return jsonb_build_object('error','codigo'); end if;
  reg := coalesce(t.data -> 'reg', '{}'::jsonb);
  if jsonb_typeof(reg) <> 'object' or (reg -> 'open') is distinct from 'true'::jsonb then
    return jsonb_build_object('error','cerrado');
  end if;
  if coalesce(reg ->> 'deadline','') ~ '^\d{4}-\d{2}-\d{2}$' and current_date > (reg ->> 'deadline')::date then
    return jsonb_build_object('error','plazo');
  end if;
  nm := btrim(coalesce(p_name,''));
  if char_length(nm) not between 1 and 40 then return jsonb_build_object('error','nombre'); end if;
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
    insert into public.registrations (tournament_id, name, contact, level, status, ip_hash)
    values (t.id, nm, ct, case when p_level between 1 and 12 then p_level else null end, st, ih);
  exception when unique_violation then
    return jsonb_build_object('error','duplicado');
  end;
  return jsonb_build_object('ok', true, 'status', st);
end $$;

-- Cuántas inscripciones lleva un torneo publicado (sin enseñar nombres).
create or replace function public.inscripcion_info(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('count', (select count(*) from public.registrations r where r.tournament_id = t.id and r.status <> 'rejected'))
  from public.tournaments t where t.public_code = p_code and char_length(p_code) between 10 and 16 limit 1
$$;

revoke all on function public.inscribirse(text, text, text, int) from public;
revoke all on function public.inscripcion_info(text) from public;
grant execute on function public.inscribirse(text, text, text, int) to anon, authenticated;
grant execute on function public.inscripcion_info(text) to anon, authenticated;
