-- TORNEAZO · árbitros: un enlace secreto con el que alguien sin cuenta apunta resultados.
-- El código del enlace se guarda en tournament_hooks (privada, nunca en los datos públicos del torneo).
-- Los resultados del árbitro llegan como result_reports con trusted = true y la app del organizador
-- los aplica sola (sin tener que aceptarlos uno a uno).

alter table public.result_reports add column if not exists trusted boolean not null default false;
alter table public.tournament_hooks alter column discord drop not null;
alter table public.tournament_hooks add column if not exists arb_token text check (arb_token ~ '^[a-z0-9]{16}$');

-- Crear (o cambiar) y quitar el enlace de árbitro. Devuelve el código para montar el enlace.
create or replace function public.arbitro_enlace(p_tid uuid, p_on boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tok text;
begin
  if not (public.es_dueno(p_tid) or public.es_coorganizador(p_tid)) then return jsonb_build_object('error','permiso'); end if;
  if not coalesce(p_on, false) then
    update public.tournament_hooks set arb_token = null, updated_at = now() where tournament_id = p_tid;
    return jsonb_build_object('ok', true, 'token', null);
  end if;
  tok := substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 16);
  insert into public.tournament_hooks (tournament_id, arb_token, updated_at) values (p_tid, tok, now())
  on conflict (tournament_id) do update set arb_token = excluded.arb_token, updated_at = now();
  return jsonb_build_object('ok', true, 'token', tok);
end $$;

create or replace function public.arbitro_estado(p_tid uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.es_dueno(p_tid) or public.es_coorganizador(p_tid)) then return jsonb_build_object('error','permiso'); end if;
  return jsonb_build_object('token', (select arb_token from public.tournament_hooks where tournament_id = p_tid));
end $$;

-- Resultado enviado por un árbitro desde la página pública con ?arb=<código>.
create or replace function public.arbitro_resultado(p_code text, p_token text, p_key text, p_a int, p_b int, p_sa int, p_sb int, p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t record; nm text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if p_token is null or p_token !~ '^[a-z0-9]{16}$'
     or not exists (select 1 from public.tournament_hooks h where h.tournament_id = t.id and h.arb_token = p_token) then
    return jsonb_build_object('error','enlace');
  end if;
  if p_key is null or p_key !~ '^(m:\d{1,4}|l:\d{1,4}|k:\d{1,2}:\d{1,4}|k3|d:\d{1,4})$' then return jsonb_build_object('error','partido'); end if;
  if p_a is null or p_b is null or p_a not between 0 and 9999 or p_b not between 0 and 9999 or p_a = p_b then return jsonb_build_object('error','partido'); end if;
  if p_sa is null or p_sb is null or p_sa not between 0 and 999 or p_sb not between 0 and 999 then return jsonb_build_object('error','marcador'); end if;
  nm := left(btrim(coalesce(nullif(btrim(p_name), ''), 'Árbitro')), 40);
  if (select count(*) from public.result_reports where tournament_id = t.id and trusted and created_at > now() - interval '1 hour') >= 300 then
    return jsonb_build_object('error','limite');
  end if;
  insert into public.result_reports (tournament_id, match_key, team_a, team_b, score_a, score_b, name, trusted)
  values (t.id, p_key, p_a, p_b, p_sa, p_sb, nm, true);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.arbitro_enlace(uuid, boolean) from public, anon;
revoke all on function public.arbitro_estado(uuid) from public, anon;
revoke all on function public.arbitro_resultado(text, text, text, int, int, int, int, text) from public;
grant execute on function public.arbitro_enlace(uuid, boolean) to authenticated;
grant execute on function public.arbitro_estado(uuid) to authenticated;
grant execute on function public.arbitro_resultado(text, text, text, int, int, int, int, text) to anon, authenticated;
