-- TORNEAZO · pagos (Stripe), aceptación de términos y borrado de cuenta.
-- Basado en lo ya probado en Mi Fútbol JV32 (supabase-stripe.sql, supabase-multiusuario.sql).
-- Ejecutar después de 20261110_torneazo_inicial.sql. Se puede repetir sin riesgo.

alter table public.profiles add column if not exists terms_version text;
alter table public.profiles add column if not exists accepted_terms_at timestamptz;
alter table public.profiles add column if not exists stripe_customer text;
alter table public.profiles add column if not exists stripe_subscription text;
alter table public.profiles add column if not exists stripe_estado text;
alter table public.profiles add column if not exists stripe_evento_at bigint;
alter table public.profiles add column if not exists plan_actualizado_at timestamptz;
alter table public.profiles add column if not exists premium_hasta timestamptz;
create unique index if not exists profiles_stripe_customer_key
  on public.profiles (stripe_customer) where stripe_customer is not null;

-- Los usuarios solo leen su perfil; las columnas de pago las cambia únicamente la Edge Function (service_role).
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (display_name) on public.profiles to authenticated;

-- El perfil guarda qué versión de los términos aceptó cada usuario al registrarse.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, terms_version, accepted_terms_at)
  values (new.id,
          left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Jugador'), 24),
          nullif(left(coalesce(new.raw_user_meta_data->>'terms_version', ''), 20), ''),
          now())
  on conflict (id) do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Derecho de supresión: el botón «Borrar mi cuenta» llama a esta función.
create or replace function public.borrar_mi_cuenta() returns void
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'No autenticado'; end if;
  delete from public.tournaments where owner_id = uid;
  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end $$;
revoke all on function public.borrar_mi_cuenta() from public, anon;
grant execute on function public.borrar_mi_cuenta() to authenticated;
