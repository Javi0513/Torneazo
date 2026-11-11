-- TORNEAZO · resultados enviados por los jugadores.
-- Desde la página pública (sin cuenta) un jugador propone el resultado de un partido con enviar_resultado().
-- No se aplica solo: el organizador lo acepta o lo rechaza. No hay acceso directo a la tabla para anónimos.

create table if not exists public.result_reports (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  match_key text not null check (match_key ~ '^(m:\d{1,4}|l:\d{1,4}|k:\d{1,2}:\d{1,4})$'),
  team_a int not null check (team_a between 0 and 9999),
  team_b int not null check (team_b between 0 and 9999),
  score_a int not null check (score_a between 0 and 999),
  score_b int not null check (score_b between 0 and 999),
  name text not null check (char_length(name) between 1 and 40),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  ip_hash text,
  created_at timestamptz not null default now()
);
create index if not exists result_reports_tournament_idx on public.result_reports (tournament_id, status, created_at);

alter table public.result_reports enable row level security;
revoke all on public.result_reports from anon, authenticated;
grant select, delete on public.result_reports to authenticated;
grant update (status) on public.result_reports to authenticated;

drop policy if exists "resultados: ver los de mis torneos" on public.result_reports;
create policy "resultados: ver los de mis torneos" on public.result_reports for select to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));
drop policy if exists "resultados: editar los de mis torneos" on public.result_reports;
create policy "resultados: editar los de mis torneos" on public.result_reports for update to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));
drop policy if exists "resultados: borrar los de mis torneos" on public.result_reports;
create policy "resultados: borrar los de mis torneos" on public.result_reports for delete to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id and t.owner_id = (select auth.uid())));

-- Enviar un resultado. Solo si el torneo es público, no está oculto y el organizador lo permite (data.selfRep).
-- Límites: 10 por hora y dispositivo, 30 por minuto en el torneo y 300 pendientes por torneo.
create or replace function public.enviar_resultado(p_code text, p_key text, p_a int, p_b int, p_sa int, p_sb int, p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t record; ipv text; ih text; nm text;
begin
  if p_code is null or char_length(p_code) not between 10 and 16 then return jsonb_build_object('error','codigo'); end if;
  select id, data into t from public.tournaments where public_code = p_code and not hidden;
  if not found then return jsonb_build_object('error','codigo'); end if;
  if (t.data -> 'selfRep') is distinct from 'true'::jsonb then return jsonb_build_object('error','cerrado'); end if;
  if p_key is null or p_key !~ '^(m:\d{1,4}|l:\d{1,4}|k:\d{1,2}:\d{1,4})$' then return jsonb_build_object('error','partido'); end if;
  if p_a is null or p_b is null or p_a not between 0 and 9999 or p_b not between 0 and 9999 or p_a = p_b then
    return jsonb_build_object('error','partido');
  end if;
  if p_sa is null or p_sb is null or p_sa not between 0 and 999 or p_sb not between 0 and 999 then
    return jsonb_build_object('error','marcador');
  end if;
  nm := btrim(coalesce(p_name,''));
  if char_length(nm) not between 1 and 40 then return jsonb_build_object('error','nombre'); end if;
  begin
    ipv := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for',''), ',', 1);
  exception when others then ipv := '';
  end;
  ih := case when ipv <> '' then md5(ipv || p_code || 'res') else null end;
  if ih is not null and (select count(*) from public.result_reports where tournament_id = t.id and ip_hash = ih and created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('error','limite');
  end if;
  if (select count(*) from public.result_reports where tournament_id = t.id and created_at > now() - interval '1 minute') >= 30 then
    return jsonb_build_object('error','limite');
  end if;
  if (select count(*) from public.result_reports where tournament_id = t.id and status = 'pending') >= 300 then
    return jsonb_build_object('error','limite');
  end if;
  insert into public.result_reports (tournament_id, match_key, team_a, team_b, score_a, score_b, name, ip_hash)
  values (t.id, p_key, p_a, p_b, p_sa, p_sb, nm, ih);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.enviar_resultado(text, text, int, int, int, int, text) from public;
grant execute on function public.enviar_resultado(text, text, int, int, int, int, text) to anon, authenticated;
