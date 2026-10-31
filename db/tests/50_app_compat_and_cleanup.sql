-- The app and the bot write to the same ledger. They have to coexist, and removing things has to be clean.
set role authenticated;
select t.as_user(:UA);

-- COMPAT: optimistic concurrency between the app and the bot
select (public.finance_state_payload()->>'revision')::int as rev_before \gset
select jsonb_array_length(public.finance_state_payload()#>'{state,transactions}')::int as tx_before \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select public.capture_telegram_expense(1001, 70, 'revisão sobe', 100)->>'ok' as rev_ok \gset
reset role;
set role authenticated;
select t.as_user(:UA);
select t.eq('COMPAT', 'cada captura incrementa a revisão do usuário', ((public.finance_state_payload()->>'revision')::int - :rev_before)::text, '1');
select t.raises('COMPAT', 'uma aba desatualizada é recusada', format('select public.save_finance_state(public.finance_state_payload()->''state'', %s)', :rev_before), 'Financial state changed');
select (public.save_finance_state(p->'state', (p->>'revision')::bigint))->>'revision' as rev_saved from public.finance_state_payload() p \gset
select t.eq('COMPAT', 'salvar pelo app preserva as despesas do bot',
  jsonb_array_length(public.finance_state_payload()#>'{state,transactions}')::text, (:tx_before + 1)::text);
reset role;

-- CLEAN: removing the chosen account must not block the app, and must leave nothing to write to
set role authenticated;
select t.as_user(:UE);
select public.start_telegram_link(:E1) as tokene \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select public.confirm_telegram_link(5005, :'tokene')->>'ok' as e_linked \gset
reset role;
select t.eq('CLEAN', 'o usuário E conecta o chat', :'e_linked', 'true');
set role authenticated;
select t.as_user(:UE);
select t.set_accounts(:UE, '[]'::jsonb);
select t.eq('CLEAN', 'apagar a conta limpa a escolha sem bloquear o app', public.telegram_link_status()->>'accountId', '');
reset role;
set role anon;
select t.bot(:'botsecret');
select t.has('CLEAN', 'sem conta, a captura explica o problema', public.capture_telegram_expense(5005, 1, 'x', 100)->>'message', 'Nenhuma conta ativa');
reset role;

-- Disconnecting cuts the bot off and drops any pending link.
set role authenticated;
select t.as_user(:UA);
select public.start_telegram_link(:A1) as tokenpending \gset
select public.unlink_telegram();
select t.eq('CLEAN', 'desconectar mostra desconectado', public.telegram_link_status()->>'linked', 'false');
reset role;
select t.eq('CLEAN', 'desconectar apaga o link pendente', (select count(*)::text from public.telegram_link_tokens where user_id = :UA), '0');
set role anon;
select t.bot(:'botsecret');
select t.has('CLEAN', 'depois de desconectar, o chat não grava mais', public.capture_telegram_expense(1001, 80, 'x', 100)->>'message', 'ainda não está conectado');
reset role;

-- Rotating the bot secret invalidates the old one at once.
select public.rotate_telegram_bot_secret() as newsecret \gset
set role anon;
select t.bot(:'botsecret');
select t.eq('CLEAN', 'o segredo antigo deixa de valer', public.capture_telegram_expense(2002, 81, 'x', 100)->>'message', 'Bot não autorizado.');
select t.bot(:'newsecret');
select t.eq('CLEAN', 'o segredo novo vale', public.capture_telegram_expense(2002, 82, 'segredo novo', 100)->>'ok', 'true');
reset role;
\set botsecret :newsecret

-- Deleting an auth user (done by the auth service) removes the links and every row they own.
set role supabase_auth_admin;
delete from auth.users where id = :UB;
reset role;
select t.eq('CLEAN', 'excluir o usuário remove o vínculo', (select count(*)::text from public.telegram_links where user_id = :UB), '0');
select t.eq('CLEAN', 'excluir o usuário remove os lançamentos', (select count(*)::text from public.financial_events where user_id = :UB), '0');
