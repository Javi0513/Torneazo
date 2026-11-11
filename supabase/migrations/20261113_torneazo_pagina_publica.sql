-- TORNEAZO · página pública de un torneo (solo lectura, con enlace secreto).
-- El dueño publica poniendo un código al azar en tournaments.public_code; cualquiera con el enlace
-- puede ver ese torneo (y solo ese) llamando a ver_torneo(). Sin código, nadie lo ve.
alter table public.tournaments add column if not exists public_code text;
alter table public.tournaments drop constraint if exists tournaments_public_code_fmt;
alter table public.tournaments add constraint tournaments_public_code_fmt
  check (public_code is null or public_code ~ '^[a-z0-9]{10,16}$');
create unique index if not exists tournaments_public_code_key
  on public.tournaments (public_code) where public_code is not null;

create or replace function public.ver_torneo(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', t.name, 'data', t.data, 'updated_at', t.updated_at)
  from public.tournaments t
  where t.public_code = p_code and char_length(p_code) between 10 and 16
  limit 1
$$;
revoke all on function public.ver_torneo(text) from public;
grant execute on function public.ver_torneo(text) to anon, authenticated;
