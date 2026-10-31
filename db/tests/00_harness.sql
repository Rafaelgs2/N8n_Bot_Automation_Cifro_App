-- Test harness. Every file in this folder is piped into one psql session, in order, so psql
-- variables and the results table are shared. Expected failures are asserted with t.raises,
-- which means any bare error aborts the run (ON_ERROR_STOP) instead of passing silently.
create schema t;

create table t.results (
  id serial primary key,
  scenario text not null,
  name text not null,
  ok boolean not null,
  detail text
);

grant usage on schema t to public;
grant select, insert on t.results to public;
grant usage on sequence t.results_id_seq to public;

create function t.eq(p_scenario text, p_name text, p_actual text, p_expected text) returns void
language plpgsql as $$
declare
  v_ok boolean := p_actual is not distinct from p_expected;
begin
  insert into t.results (scenario, name, ok, detail)
  values (p_scenario, p_name, v_ok, case when v_ok then null else format('esperado %L, veio %L', p_expected, p_actual) end);
end;
$$;

-- Passes when p_actual contains the fragment, ignoring case.
create function t.has(p_scenario text, p_name text, p_actual text, p_fragment text) returns void
language plpgsql as $$
declare
  v_ok boolean := coalesce(p_actual ilike '%' || p_fragment || '%', false);
begin
  insert into t.results (scenario, name, ok, detail)
  values (p_scenario, p_name, v_ok, case when v_ok then null else format('esperado conter %L, veio %L', p_fragment, p_actual) end);
end;
$$;

-- Runs p_sql as the current role and passes only if it fails with a message containing p_expected.
create function t.raises(p_scenario text, p_name text, p_sql text, p_expected text) returns void
language plpgsql as $$
begin
  execute p_sql;
  insert into t.results (scenario, name, ok, detail) values (p_scenario, p_name, false, 'nenhum erro foi lançado');
exception when others then
  insert into t.results (scenario, name, ok, detail)
  values (p_scenario, p_name, sqlerrm ilike '%' || p_expected || '%',
          case when sqlerrm ilike '%' || p_expected || '%' then null else format('erro inesperado: %s', sqlerrm) end);
end;
$$;

-- Plays the signed-in user: auth.uid() reads this setting.
create function t.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false) $$;

-- Plays the automation: PostgREST exposes request headers as a JSON setting.
create function t.bot(p_secret text) returns void language sql as $$
  select set_config('request.headers', json_build_object('x-cifro-bot-secret', p_secret)::text, false) $$;

-- Replaces a user's accounts through the same RPC the app uses.
create function t.set_accounts(p_user uuid, p_accounts jsonb) returns void
language plpgsql as $$
declare
  v_payload jsonb;
begin
  perform t.as_user(p_user);
  v_payload := public.finance_state_payload();
  perform public.save_finance_state(jsonb_set(v_payload->'state', '{accounts}', p_accounts), (v_payload->>'revision')::bigint);
end;
$$;

create function t.account(p_id uuid, p_name text, p_kind text, p_date text, p_archived boolean default false, p_order int default 0)
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'name', p_name, 'kind', p_kind, 'initial', 0, 'date', p_date, 'archived', p_archived, 'order', p_order)
$$;

create function t.add_expense_category(p_user uuid, p_id uuid, p_name text, p_icon text) returns void
language plpgsql as $$
declare
  v_payload jsonb;
begin
  perform t.as_user(p_user);
  v_payload := public.finance_state_payload();
  perform public.save_finance_state(
    jsonb_set(v_payload->'state', '{categories}',
      (v_payload#>'{state,categories}') || jsonb_build_object('id', p_id, 'name', p_name, 'type', 'expense', 'color', '#6588da', 'icon', p_icon, 'order', 99)),
    (v_payload->>'revision')::bigint);
end;
$$;

grant execute on all functions in schema t to public;
