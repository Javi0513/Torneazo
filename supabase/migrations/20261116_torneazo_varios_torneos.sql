-- Torneos por cuenta: gratis 1, Premium hasta 50 (límite de seguridad).
create or replace function public.enforce_free_limits() returns trigger
language plpgsql security definer set search_path = '' as $$
declare premium boolean; n int;
begin
  select is_premium into premium from public.profiles where id = new.owner_id;
  if tg_op = 'INSERT' then
    select count(*) into n from public.tournaments where owner_id = new.owner_id;
    if not coalesce(premium, false) and n >= 1 then
      raise exception 'Límite de la versión gratuita: 1 torneo guardado';
    end if;
    if n >= 50 then raise exception 'Máximo 50 torneos por cuenta'; end if;
  end if;
  if not coalesce(premium, false) then
    if array_length(regexp_split_to_array(coalesce(new.data->>'players',''), E'[\\n,]+'), 1) > 32 then
      raise exception 'Límite de la versión gratuita: 32 participantes';
    end if;
  end if;
  new.updated_at = now();
  return new;
end $$;
revoke execute on function public.enforce_free_limits() from public, anon, authenticated;
