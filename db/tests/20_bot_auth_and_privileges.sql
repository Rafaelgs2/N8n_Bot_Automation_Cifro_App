-- The automation proves itself with one secret, sent as a header. Everything is refused until it is set,
-- and the API roles can reach only what they are meant to.

-- AUTH: no secret configured yet
set role anon;
select t.eq('AUTH', 'sem segredo configurado, a captura é recusada', public.capture_telegram_expense(1, 1, 'x', 100)->>'message', 'Bot não autorizado.');
select t.eq('AUTH', 'sem segredo configurado, a confirmação é recusada', public.confirm_telegram_link(1, 'x')->>'message', 'Bot não autorizado.');
reset role;

select public.rotate_telegram_bot_secret() as botsecret \gset

set role anon;
select t.bot('errado');
select t.eq('AUTH', 'segredo errado é recusado', public.capture_telegram_expense(1, 1, 'x', 100)->>'message', 'Bot não autorizado.');
select set_config('request.headers', '{}', false);
select t.eq('AUTH', 'cabeçalho ausente é recusado', public.confirm_telegram_link(1, 'x')->>'message', 'Bot não autorizado.');
select set_config('request.headers', '', false);
select t.eq('AUTH', 'sem nenhum cabeçalho é recusado', public.capture_telegram_expense(1, 1, 'x', 100)->>'message', 'Bot não autorizado.');
select t.bot('');
select t.eq('AUTH', 'segredo vazio é recusado', public.capture_telegram_expense(1, 1, 'x', 100)->>'message', 'Bot não autorizado.');
reset role;

-- PRIV: who can call what
set role anon;
select t.raises('PRIV', 'anon não gera o segredo do bot', 'select public.rotate_telegram_bot_secret()', 'permission denied');
select t.raises('PRIV', 'anon não consulta a autorização', 'select public.telegram_bot_authorized()', 'permission denied');
select t.raises('PRIV', 'anon não inicia vínculo', format('select public.start_telegram_link(%L)', :A1), 'permission denied');
select t.raises('PRIV', 'anon não troca a conta', format('select public.update_telegram_account(%L)', :A1), 'permission denied');
select t.raises('PRIV', 'anon não lê o segredo do bot', 'select * from public.telegram_bot_settings', 'permission denied');
select t.raises('PRIV', 'anon não lê os links pendentes', 'select * from public.telegram_link_tokens', 'permission denied');
select t.raises('PRIV', 'anon não lê os vínculos', 'select * from public.telegram_links', 'permission denied');
select t.raises('PRIV', 'anon não carrega o estado financeiro', 'select public.finance_state_payload()', 'permission denied');
select t.raises('PRIV', 'anon não executa o validador de integridade', format('select public.assert_financial_event_integrity(%L)', :A1), 'permission denied');
select t.raises('PRIV', 'anon não cria categorias padrão para outro usuário', format('select public.ensure_default_categories(%L)', :UA), 'permission denied');
reset role;

set role authenticated;
select t.as_user(:UA);
select t.raises('PRIV', 'usuário logado não gera o segredo do bot', 'select public.rotate_telegram_bot_secret()', 'permission denied');
select t.raises('PRIV', 'usuário logado não confirma vínculo no lugar do bot', 'select public.confirm_telegram_link(1, ''x'')', 'permission denied');
select t.raises('PRIV', 'usuário logado não grava pela função do bot', 'select public.capture_telegram_expense(1, 1, ''x'', 100)', 'permission denied');
select t.raises('PRIV', 'usuário logado não lê o segredo do bot', 'select * from public.telegram_bot_settings', 'permission denied');
select t.raises('PRIV', 'usuário logado não lê os vínculos de ninguém', 'select * from public.telegram_links', 'permission denied');
reset role;

select t.eq('PRIV', 'o anon só executa as duas funções do bot',
  (select string_agg(p.proname, ', ' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')),
  'capture_telegram_expense, confirm_telegram_link');
select t.eq('PRIV', 'o segredo do bot é guardado só como hash', (select (secret_hash <> :'botsecret' and length(secret_hash) = 64)::text from public.telegram_bot_settings), 'true');
