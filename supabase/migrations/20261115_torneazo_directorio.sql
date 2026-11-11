-- TORNEAZO · directorio de torneos públicos, denuncias y moderación.
-- Un torneo aparece en el directorio SOLO si su dueño lo pide (listed = true) y tiene página pública.
-- Si 3 personas distintas lo denuncian se oculta solo (hidden) hasta que lo revise un administrador.

alter table public.tournaments add column if not exists listed boolean not null default false;
alter table public.tournaments add column if not exists hidden boolean not null default false;
alter table public.tournaments add column if not exists report_count int not null default 0;
create index if not exists tournaments_directorio_idx on public.tournaments (listed) where listed and not hidden and public_code is not null;

alter table public.profiles add column if not exists is_admin boolean not null default false;

-- El dueño ya no puede tocar hidden ni report_count (solo el servidor y los administradores).
revoke update on public.tournaments from authenticated;
grant update (name, data, public_code, listed) on public.tournaments to authenticated;

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  motivo text not null check (motivo in ('inapropiado','spam','suplantacion','otro')),
  detalle text check (detalle is null or char_length(detalle) <= 200),
  ip_hash text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists reports_unique_ip on public.reports (tournament_id, ip_hash);
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

-- Un torneo oculto deja de verse también en su página pública y no admite inscripciones.
create or replace function public.ver_torneo(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', t.name, 'data', t.data, 'updated_at', t.updated_at)
  from public.tournaments t
  where t.public_code = p_code and not t.hidden and char_length(p_code) between 10 and 16
  limit 1
$$;
create or replace function public.inscripcion_info(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('count', (select count(*) from public.registrations r where r.tournament_id = t.id and r.status <> 'rejected'))
  from public.tournaments t where t.public_code = p_code and not t.hidden and char_length(p_code) between 10 and 16 limit 1
$$;

-- Los torneos ocultos tampoco admiten inscripciones.
create or replace function public.inscribirse(p_code text, p_name text, p_contact text default null, p_level int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t record; reg jsonb; cap int := 0; n int; ipv text; ih text; st text; nm text; ct text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
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


-- Directorio público: solo torneos listados y no ocultos. Filtros por texto, estado y juego.
create or replace function public.directorio(p_q text default '', p_estado text default 'all', p_game text default '', p_limit int default 20, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare pat text; res jsonb;
begin
  pat := '%' || replace(replace(replace(left(coalesce(p_q,''), 60), E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into res from (
    select code, name, game, preset, estado, n, start, org, descr, reg_open, reg_max, reg_count from (
      select t.public_code as code, left(t.name, 80) as name,
        left(coalesce(t.data ->> 'game',''), 60) as game, left(coalesce(t.data ->> 'preset',''), 20) as preset,
        case when t.data -> 'dir' ->> 'estado' in ('next','live','done') then t.data -> 'dir' ->> 'estado' else 'next' end as estado,
        case when jsonb_typeof(t.data -> 'dir' -> 'n') = 'number' then least((t.data -> 'dir' ->> 'n')::numeric::int, 100000) else 0 end as n,
        case when (t.data -> 'info' ->> 'start') ~ '^\d{4}-\d{2}-\d{2}$' then t.data -> 'info' ->> 'start' end as start,
        left(coalesce(t.data -> 'info' ->> 'org',''), 60) as org, left(coalesce(t.data -> 'info' ->> 'desc',''), 160) as descr,
        ((t.data -> 'reg' -> 'open') = 'true'::jsonb
          and not coalesce(((t.data -> 'reg' ->> 'deadline') ~ '^\d{4}-\d{2}-\d{2}$') and current_date > (t.data -> 'reg' ->> 'deadline')::date, false)) as reg_open,
        case when jsonb_typeof(t.data -> 'reg' -> 'max') = 'number' then least((t.data -> 'reg' ->> 'max')::numeric::int, 100000) else 0 end as reg_max,
        (select count(*) from public.registrations r where r.tournament_id = t.id and r.status <> 'rejected') as reg_count,
        t.updated_at
      from public.tournaments t
      where t.listed and not t.hidden and t.public_code is not null
    ) b
    where (coalesce(p_q,'') = '' or b.name ilike pat or b.game ilike pat or b.org ilike pat)
      and (coalesce(p_estado,'') in ('','all')
           or (p_estado = 'open' and b.reg_open and b.estado <> 'done')
           or b.estado = p_estado)
      and (coalesce(p_game,'') = '' or (p_game = 'otros' and b.preset = '') or b.preset = p_game)
    order by case when b.reg_open and b.estado <> 'done' then 0 when b.estado = 'live' then 1 when b.estado = 'next' then 2 else 3 end,
             coalesce(b.start, '9999-12-31'), b.updated_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
  ) x;
  return res;
end $$;

-- Denunciar un torneo (sin cuenta). 5 denuncias por hora y dispositivo; con 3 personas distintas se oculta solo.
create or replace function public.reportar_torneo(p_code text, p_motivo text, p_detalle text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t record; ipv text := ''; ih text; n int;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  if p_motivo not in ('inapropiado','spam','suplantacion','otro') then return jsonb_build_object('error','motivo'); end if;
  select id into t from public.tournaments where public_code = p_code;
  if not found then return jsonb_build_object('error','codigo'); end if;
  begin
    ipv := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
  exception when others then ipv := '';
  end;
  if ipv = '' then return jsonb_build_object('error','limite'); end if;
  ih := md5(ipv || 'torneazo-report');
  if (select count(*) from public.reports where ip_hash = ih and created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error','limite');
  end if;
  insert into public.reports (tournament_id, motivo, detalle, ip_hash)
  values (t.id, p_motivo, nullif(left(btrim(coalesce(p_detalle,'')), 200), ''), ih)
  on conflict (tournament_id, ip_hash) do nothing;
  select count(*) into n from public.reports where tournament_id = t.id;
  update public.tournaments set report_count = n, hidden = (hidden or n >= 3) where id = t.id;
  return jsonb_build_object('ok', true);
end $$;

-- Moderación: solo para administradores (profiles.is_admin, que solo se cambia desde el servidor).
create or replace function public.moderacion_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin) then
    raise exception 'No autorizado';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select t.public_code as code, left(t.name, 80) as name, left(coalesce(t.data ->> 'game',''), 60) as game,
           t.listed, t.hidden, t.report_count,
           (select string_agg(distinct r.motivo, ', ') from public.reports r where r.tournament_id = t.id) as motivos,
           (select left(string_agg(r.detalle, ' | '), 300) from public.reports r where r.tournament_id = t.id and r.detalle is not null) as detalles
    from public.tournaments t
    where t.report_count > 0 or t.hidden
    order by t.hidden desc, t.report_count desc, t.updated_at desc
    limit 100) x), '[]'::jsonb);
end $$;

create or replace function public.moderar(p_code text, p_hidden boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin) then
    raise exception 'No autorizado';
  end if;
  update public.tournaments set hidden = coalesce(p_hidden, false),
    report_count = case when coalesce(p_hidden, false) then report_count else 0 end
  where public_code = p_code;
  if not coalesce(p_hidden, false) then
    delete from public.reports where tournament_id = (select id from public.tournaments where public_code = p_code);
  end if;
end $$;

revoke all on function public.directorio(text, text, text, int, int) from public;
revoke all on function public.reportar_torneo(text, text, text) from public;
revoke all on function public.moderacion_lista() from public;
revoke all on function public.moderar(text, boolean) from public;
grant execute on function public.directorio(text, text, text, int, int) to anon, authenticated;
grant execute on function public.reportar_torneo(text, text, text) to anon, authenticated;
grant execute on function public.moderacion_lista() to authenticated;
grant execute on function public.moderar(text, boolean) to authenticated;
