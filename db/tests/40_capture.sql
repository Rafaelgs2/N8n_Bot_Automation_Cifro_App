-- Capturing an expense: who it belongs to, where it goes, how it is categorised, and what it refuses.
-- Chat 1001 belongs to user A (account "Conta A"), chat 2002 to user B.
set role anon;
select t.bot(:'botsecret');

-- CAP: the happy path
select public.capture_telegram_expense(1001, 10, 'almoço no centro', 3250) as r1 \gset
select t.eq('CAP', 'grava e responde ok', (:'r1'::jsonb)->>'ok', 'true');
select t.eq('CAP', 'informa a conta de destino', (:'r1'::jsonb)->>'account', 'Conta A');
select t.eq('CAP', 'almoço vai para Alimentação', (:'r1'::jsonb)->>'category', 'Alimentação');
select t.eq('CAP', 'não é marcada como reenvio', (:'r1'::jsonb)->>'duplicate', 'false');
reset role;

select t.eq('CAP', 'o valor sai da conta, em centavos',
  (select ae.amount_cents::text from public.account_entries ae join public.financial_events e on e.id = ae.event_id where e.description = 'almoço no centro'), '-3250');
select t.eq('CAP', 'a data é o dia de hoje em São Paulo',
  (select (occurred_on = (now() at time zone 'America/Sao_Paulo')::date)::text from public.financial_events where description = 'almoço no centro'), 'true');

-- CAT: how the category is chosen
set role anon;
select t.bot(:'botsecret');
select t.eq('CAT', 'palavra conhecida sem acento (hotdog)', public.capture_telegram_expense(1001, 11, 'hotdog na facul', 800)->>'category', 'Alimentação');
select t.eq('CAT', 'maiúsculas e acentos não atrapalham (ALMOÇO)', public.capture_telegram_expense(1001, 12, 'ALMOÇO executivo', 3000)->>'category', 'Alimentação');
select t.eq('CAT', 'uber vai para Transporte', public.capture_telegram_expense(1001, 13, 'uber para casa', 2000)->>'category', 'Transporte');
select t.eq('CAT', 'farmácia vai para Saúde', public.capture_telegram_expense(1001, 14, 'farmácia', 1500)->>'category', 'Saúde');
select t.eq('CAT', 'sem palavra conhecida cai em Outros', public.capture_telegram_expense(1001, 15, 'barco', 1500)->>'category', 'Outros');
select t.eq('CAT', 'o nome de uma categoria do usuário vence', public.capture_telegram_expense(1001, 16, 'lazer do fim de semana', 1000)->>'category', 'Lazer');
select t.eq('CAT', 'categoria com símbolos no nome (C++ (curso))', public.capture_telegram_expense(1001, 17, 'c++ (curso) udemy', 100)->>'category', 'C++ (curso)');
reset role;

-- VAL: what it refuses
set role anon;
select t.bot(:'botsecret');
select t.has('VAL', 'valor zero', public.capture_telegram_expense(1001, 20, 'x', 0)->>'message', 'maior que zero');
select t.has('VAL', 'valor negativo', public.capture_telegram_expense(1001, 21, 'x', -5)->>'message', 'maior que zero');
select t.has('VAL', 'valor acima do teto', public.capture_telegram_expense(1001, 22, 'x', 100000000000)->>'message', 'maior que zero');
select t.has('VAL', 'valor nulo', public.capture_telegram_expense(1001, 23, 'x', null)->>'message', 'maior que zero');
select t.has('VAL', 'descrição nula', public.capture_telegram_expense(1001, 24, null, 100)->>'message', 'de 1 a 100');
select t.has('VAL', 'descrição só com espaços', public.capture_telegram_expense(1001, 25, E'  \t ', 100)->>'message', 'de 1 a 100');
select t.has('VAL', 'descrição com 101 caracteres', public.capture_telegram_expense(1001, 26, repeat('a', 101), 100)->>'message', 'de 1 a 100');
select t.has('VAL', 'descrição com 51 emojis (o app conta 2 por emoji)', public.capture_telegram_expense(1001, 27, repeat('😀', 51), 100)->>'message', 'de 1 a 100');
select t.eq('VAL', 'descrição com 100 caracteres é aceita', public.capture_telegram_expense(1001, 28, repeat('a', 100), 100)->>'ok', 'true');
select t.eq('VAL', 'descrição com 50 emojis é aceita', public.capture_telegram_expense(1001, 29, repeat('😀', 50), 100)->>'ok', 'true');
select t.has('VAL', 'mensagem sem id', public.capture_telegram_expense(1001, null, 'x', 100)->>'message', 'Mensagem inválida');
reset role;

-- IDEM: retries never charge twice
set role anon;
select t.bot(:'botsecret');
select t.eq('IDEM', 'o reenvio é reconhecido', public.capture_telegram_expense(1001, 10, 'almoço no centro', 3250)->>'duplicate', 'true');
select t.eq('IDEM', 'o mesmo id de mensagem em outro chat não colide', public.capture_telegram_expense(2002, 10, 'almoço no centro', 3250)->>'duplicate', 'false');
reset role;
select t.eq('IDEM', 'só existe um lançamento para o usuário A', (select count(*)::text from public.financial_events where user_id = :UA and description = 'almoço no centro'), '1');
select t.eq('IDEM', 'o usuário B tem o seu próprio lançamento', (select count(*)::text from public.financial_events where user_id = :UB and description = 'almoço no centro'), '1');

-- ISO: each chat writes only to its own owner
set role anon;
select t.bot(:'botsecret');
select public.capture_telegram_expense(1001, 50, 'isolamento', 1000)->>'account' as iso_a \gset
select public.capture_telegram_expense(2002, 50, 'isolamento', 2000)->>'account' as iso_b \gset
reset role;
select t.eq('ISO', 'A grava na própria conta', :'iso_a', 'Conta A');
select t.eq('ISO', 'B grava na própria conta', :'iso_b', 'Conta B');
select t.eq('ISO', 'o lançamento de A tem o valor de A',
  (select sum(ae.amount_cents)::text from public.account_entries ae join public.financial_events e on e.id = ae.event_id where e.user_id = :UA and e.description = 'isolamento'), '-1000');
select t.eq('ISO', 'o lançamento de B tem o valor de B',
  (select sum(ae.amount_cents)::text from public.account_entries ae join public.financial_events e on e.id = ae.event_id where e.user_id = :UB and e.description = 'isolamento'), '-2000');

-- ACC: choosing the destination account
set role authenticated;
select t.as_user(:UA);
select t.raises('ACC', 'a conta de outro usuário não pode ser escolhida', format('select public.update_telegram_account(%L)', :B1), 'Account not found');
select public.update_telegram_account(:A2);
select t.eq('ACC', 'trocar a conta mantém o vínculo', public.telegram_link_status()->>'chatId', '1001');
reset role;
set role anon;
select t.bot(:'botsecret');
select t.eq('ACC', 'o mesmo chat passa a gravar na conta nova', public.capture_telegram_expense(1001, 60, 'depois da troca', 100)->>'account', 'Conta A2');
reset role;

-- Archiving the chosen account: the next active one takes over, and an archived one cannot be chosen.
set role authenticated;
select t.set_accounts(:UA, jsonb_build_array(
  t.account(:A1, 'Conta A', 'salary', '2026-01-01', false, 0),
  t.account(:A2, 'Conta A2', 'other', '2026-01-01', true, 1)));
select t.raises('ACC', 'conta arquivada não pode ser escolhida', format('select public.update_telegram_account(%L)', :A2), 'Account not found');
reset role;
set role anon;
select t.bot(:'botsecret');
select t.eq('ACC', 'conta arquivada: grava na primeira conta ativa', public.capture_telegram_expense(1001, 61, 'conta arquivada', 100)->>'account', 'Conta A');
reset role;

-- A user whose only account opens in the future has nowhere valid to put today's expense.
set role authenticated;
select t.as_user(:UC);
select public.start_telegram_link(:C1) as tokenc \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select public.confirm_telegram_link(3003, :'tokenc')->>'ok' as c_linked \gset
select t.eq('ACC', 'o usuário C conecta o chat', :'c_linked', 'true');
select t.has('ACC', 'conta com saldo no futuro não recebe o lançamento', public.capture_telegram_expense(3003, 1, 'x', 100)->>'message', 'Nenhuma conta ativa');
reset role;
