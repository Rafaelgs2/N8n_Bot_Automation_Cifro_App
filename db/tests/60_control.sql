-- Negative control. The capture function runs `set constraints all immediate` so the deferred integrity
-- triggers fire under its own role. Here the same function is rebuilt WITHOUT that line, to prove the line
-- is what makes anon captures work, and that this suite would notice if someone removed it.

-- Precondition: the earlier cleanup disconnected A, so connect again to have a chat that can write.
set role authenticated;
select t.as_user(:UA);
select public.start_telegram_link(:A1) as tokenctl \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select public.confirm_telegram_link(1001, :'tokenctl')->>'ok' as ctl_linked \gset
reset role;
select t.eq('CONTROL', 'precondição: A volta a estar conectado', :'ctl_linked', 'true');

-- With the line, as shipped. This is a normal call in its own transaction, like a PostgREST request.
set role anon;
select t.bot(:'botsecret');
select t.eq('CONTROL', 'com a linha, a captura do anon funciona', public.capture_telegram_expense(1001, 90, 'controle com a linha', 100)->>'ok', 'true');
reset role;

-- Without the line. This runs in a transaction that is rolled back, so the schema is untouched afterwards.
-- (SET CONSTRAINTS lasts until the end of the transaction, which is why each variant gets its own.)
begin;

do $$
begin
  execute replace(pg_get_functiondef('public.capture_telegram_expense(bigint,bigint,text,bigint)'::regprocedure),
                  'set constraints all immediate;', '');
end $$;

set role anon;
select t.bot(:'botsecret');
select public.capture_telegram_expense(1001, 91, 'controle sem a linha', 100)->>'ok' as without_line \gset
-- COMMIT would run the deferred checks as the caller; forcing them now shows the same failure.
select t.raises('CONTROL', 'sem a linha, as verificações falham para o anon', 'set constraints all immediate', 'permission denied');
reset role;
select ok::text as raised_ok, coalesce(detail, '') as raised_detail from t.results order by id desc limit 1 \gset

rollback;

-- Results written inside the transaction were rolled back with it, so they are recorded again here.
select t.eq('CONTROL', 'sem a linha, a captura ainda parece funcionar (o erro só aparece no commit)', :'without_line', 'true');
insert into t.results (scenario, name, ok, detail)
values ('CONTROL', 'sem a linha, as verificações falham para o anon', :'raised_ok'::boolean, nullif(:'raised_detail', ''));
select t.eq('CONTROL', 'o rollback devolveu a função original',
  (select (position('set constraints all immediate' in prosrc) > 0)::text from pg_proc where oid = 'public.capture_telegram_expense(bigint,bigint,text,bigint)'::regprocedure), 'true');
select t.eq('CONTROL', 'o rollback descartou o lançamento da variante sem a linha', (select count(*)::text from public.financial_events where description = 'controle sem a linha'), '0');
