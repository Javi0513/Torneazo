-- TORNEAZO · esquema inicial con seguridad a nivel de fila (RLS).
-- Aplicar SOLO en el proyecto Supabase propio de TORNEAZO (no en proyectos de otros clientes).

-- 1) Perfiles: uno por usuario registrado.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Jugador' check (char_length(display_name) between 1 and 24),
  is_premium boolean not null default false,
  created_at timestamptz not null default now()
);

-- 2) Torneos: cada uno pertenece a su dueño.
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  data jsonb not null check (pg_column_size(data) < 200000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tournaments_owner_idx on public.tournaments(owner_id, updated_at desc);

alter table public.profiles enable row level security;
alter table public.tournaments enable row level security;

-- 3) Políticas: cada usuario solo ve y toca lo suyo.
create policy "perfil: leer el propio" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "perfil: editar el propio" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "torneos: leer los propios" on public.tournaments
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "torneos: crear los propios" on public.tournaments
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "torneos: editar los propios" on public.tournaments
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "torneos: borrar los propios" on public.tournaments
  for delete to authenticated using (owner_id = (select auth.uid()));

-- 4) Nadie puede darse Premium a sí mismo: solo se puede editar el apodo desde la app.
--    is_premium solo lo cambia el servidor (webhook de pagos con service_role).
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
revoke all on public.tournaments from anon;
grant select, insert, update, delete on public.tournaments to authenticated;

-- 5) Perfil automático al registrarse.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Jugador'), 24));
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 6) Límites de la versión gratuita aplicados en el servidor (no se pueden saltar desde el navegador).
create function public.enforce_free_limits() returns trigger
language plpgsql security definer set search_path = '' as $$
declare premium boolean; n int;
begin
  select is_premium into premium from public.profiles where id = new.owner_id;
  if not coalesce(premium, false) then
    if tg_op = 'INSERT' then
      select count(*) into n from public.tournaments where owner_id = new.owner_id;
      if n >= 3 then raise exception 'Límite de la versión gratuita: 3 torneos guardados'; end if;
    end if;
    if array_length(regexp_split_to_array(coalesce(new.data->>'players',''), E'[\\n,]+'), 1) > 32 then
      raise exception 'Límite de la versión gratuita: 32 participantes';
    end if;
  end if;
  new.updated_at = now();
  return new;
end $$;
revoke execute on function public.enforce_free_limits() from public, anon, authenticated;
create trigger tournaments_limits before insert or update on public.tournaments
  for each row execute function public.enforce_free_limits();
