-- TORNEAZO · varios organizadores por torneo.
-- El dueño crea un enlace de invitación (edit_code). Quien lo abre con su cuenta pasa a ser co-organizador:
-- puede ver y editar el torneo (resultados, horarios…), pero no borrarlo ni cambiar su enlace público,
-- el directorio ni la invitación. Máximo 5 co-organizadores por torneo.

alter table public.tournaments add column if not exists edit_code text;
create unique index if not exists tournaments_edit_code_idx on public.tournaments (edit_code) where edit_code is not null;

create table if not exists public.tournament_editors (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text check (name is null or char_length(name) <= 40),
  created_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);
alter table public.tournament_editors enable row level security;
revoke all on public.tournament_editors from anon, authenticated;
grant select, delete on public.tournament_editors to authenticated;

-- ¿Es el usuario actual co-organizador de este torneo? (SECURITY DEFINER para no entrar en bucle con las políticas)
create or replace function public.es_coorganizador(p_tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tournament_editors e where e.tournament_id = p_tid and e.user_id = (select auth.uid()))
$$;
revoke all on function public.es_coorganizador(uuid) from public, anon;
grant execute on function public.es_coorganizador(uuid) to authenticated;

create or replace function public.es_dueno(p_tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tournaments t where t.id = p_tid and t.owner_id = (select auth.uid()))
$$;
revoke all on function public.es_dueno(uuid) from public, anon;
grant execute on function public.es_dueno(uuid) to authenticated;

drop policy if exists "coorganizadores: ver" on public.tournament_editors;
create policy "coorganizadores: ver" on public.tournament_editors for select to authenticated
  using (user_id = (select auth.uid()) or public.es_dueno(tournament_id));
drop policy if exists "coorganizadores: quitar" on public.tournament_editors;
create policy "coorganizadores: quitar" on public.tournament_editors for delete to authenticated
  using (user_id = (select auth.uid()) or public.es_dueno(tournament_id));

-- Los co-organizadores también pueden leer y editar el torneo.
drop policy if exists "torneos: leer los propios" on public.tournaments;
create policy "torneos: leer los propios" on public.tournaments for select to authenticated
  using (owner_id = (select auth.uid()) or public.es_coorganizador(id));
drop policy if exists "torneos: editar los propios" on public.tournaments;
create policy "torneos: editar los propios" on public.tournaments for update to authenticated
  using (owner_id = (select auth.uid()) or public.es_coorganizador(id))
  with check (owner_id = (select auth.uid()) or public.es_coorganizador(id));

grant update (name, data, public_code, listed, edit_code) on public.tournaments to authenticated;

-- Quien no es el dueño no puede cambiar el enlace público, el directorio ni la invitación.
create or replace function public.proteger_campos_dueno() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.owner_id is distinct from (select auth.uid()) then
    new.public_code := old.public_code;
    new.listed := old.listed;
    new.edit_code := old.edit_code;
  end if;
  return new;
end $$;
revoke execute on function public.proteger_campos_dueno() from public, anon, authenticated;
drop trigger if exists tournaments_proteger on public.tournaments;
create trigger tournaments_proteger before update on public.tournaments
  for each row execute function public.proteger_campos_dueno();

-- Aceptar una invitación.
create or replace function public.unirse_coorganizador(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; uid uuid := (select auth.uid()); n int; nm text;
begin
  if uid is null then return jsonb_build_object('error','sesion'); end if;
  if p_code is null or p_code !~ '^[a-z0-9]{16,24}$' then return jsonb_build_object('error','codigo'); end if;
  select id, name, owner_id into t from public.tournaments where edit_code = p_code;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if t.owner_id = uid then return jsonb_build_object('ok', true, 'id', t.id, 'name', t.name, 'dueno', true); end if;
  if exists (select 1 from public.tournament_editors where tournament_id = t.id and user_id = uid) then
    return jsonb_build_object('ok', true, 'id', t.id, 'name', t.name);
  end if;
  select count(*) into n from public.tournament_editors where tournament_id = t.id;
  if n >= 5 then return jsonb_build_object('error','lleno'); end if;
  select left(coalesce(display_name, ''), 40) into nm from public.profiles where id = uid;
  insert into public.tournament_editors (tournament_id, user_id, name) values (t.id, uid, nullif(nm, ''));
  return jsonb_build_object('ok', true, 'id', t.id, 'name', t.name);
end $$;
revoke all on function public.unirse_coorganizador(text) from public, anon;
grant execute on function public.unirse_coorganizador(text) to authenticated;

-- Los co-organizadores también gestionan inscripciones y resultados enviados por jugadores.
drop policy if exists "inscripciones: ver las de mis torneos" on public.registrations;
create policy "inscripciones: ver las de mis torneos" on public.registrations for select to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));
drop policy if exists "inscripciones: editar las de mis torneos" on public.registrations;
create policy "inscripciones: editar las de mis torneos" on public.registrations for update to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id))
  with check (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));
drop policy if exists "resultados: ver los de mis torneos" on public.result_reports;
create policy "resultados: ver los de mis torneos" on public.result_reports for select to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));
drop policy if exists "resultados: editar los de mis torneos" on public.result_reports;
create policy "resultados: editar los de mis torneos" on public.result_reports for update to authenticated
  using (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id))
  with check (public.es_dueno(tournament_id) or public.es_coorganizador(tournament_id));
