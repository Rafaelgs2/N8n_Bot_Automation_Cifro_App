-- A chat becomes a user's only after a one-time link proves who owns it: the token proves the signed-in
-- account, and the chat id comes from Telegram itself.
set role authenticated;
select t.as_user(:UA);
select t.raises('LINK', 'conta de outro usuário não pode receber o vínculo', format('select public.start_telegram_link(%L)', :B1), 'Account not found');
select t.raises('LINK', 'conta inexistente é recusada', 'select public.start_telegram_link(''ba000000-0000-4000-8000-00000000ffff'')', 'Account not found');
select public.start_telegram_link(:A2) as tokena \gset
select t.eq('LINK', 'sem vínculo, o status mostra desconectado', (public.telegram_link_status()->>'linked'), 'false');
reset role;

select t.eq('LINK', 'o token é guardado só como hash', (select (token_hash <> :'tokena' and length(token_hash) = 64)::text from public.telegram_link_tokens where user_id = :UA), 'true');

set role anon;
select t.bot(:'botsecret');
select t.has('LINK', 'chat sem vínculo não grava', public.capture_telegram_expense(1001, 1, 'almoço', 100)->>'message', 'ainda não está conectado');
select t.has('LINK', 'token inválido é recusado', public.confirm_telegram_link(1001, 'tokeninvalido')->>'message', 'expirou ou já foi usado');
select t.has('LINK', 'token nulo é recusado', public.confirm_telegram_link(1001, null)->>'message', 'expirou ou já foi usado');
select t.has('LINK', 'chat nulo é recusado', public.confirm_telegram_link(null, :'tokena')->>'message', 'Mensagem inválida');
select public.confirm_telegram_link(1001, :'tokena') as confirmed \gset
select t.eq('LINK', 'o link confirma e informa a conta', (:'confirmed'::jsonb)->>'ok', 'true');
select t.has('LINK', 'a confirmação cita a conta escolhida', (:'confirmed'::jsonb)->>'message', 'Conta A2');
select t.has('LINK', 'o token só vale uma vez', public.confirm_telegram_link(1002, :'tokena')->>'message', 'expirou ou já foi usado');
reset role;

-- Another user cannot take over a chat that is already linked.
set role authenticated;
select t.as_user(:UB);
select public.start_telegram_link(:B1) as tokenb \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select t.has('LINK', 'o chat de A não pode ser tomado por B', public.confirm_telegram_link(1001, :'tokenb')->>'message', 'já está conectado a outra conta');
select t.has('LINK', 'B conecta o próprio chat', public.confirm_telegram_link(2002, :'tokenb')->>'message', 'Conta B');
reset role;

-- An expired link is refused.
set role authenticated;
select t.as_user(:UA);
select public.start_telegram_link(:A1) as tokenold \gset
reset role;
update public.telegram_link_tokens set expires_at = now() - interval '1 second' where user_id = :UA;
set role anon;
select t.bot(:'botsecret');
select t.has('LINK', 'link vencido é recusado', public.confirm_telegram_link(1001, :'tokenold')->>'message', 'expirou ou já foi usado');
reset role;

-- A newer link replaces the pending one, and linking again moves the account without a second row.
set role authenticated;
select t.as_user(:UA);
select public.start_telegram_link(:A2) as tokenfirst \gset
select public.start_telegram_link(:A1) as tokensecond \gset
reset role;
set role anon;
select t.bot(:'botsecret');
select t.has('LINK', 'um link novo invalida o pendente', public.confirm_telegram_link(1001, :'tokenfirst')->>'message', 'expirou ou já foi usado');
select t.has('LINK', 'o link novo conecta a conta pedida', public.confirm_telegram_link(1001, :'tokensecond')->>'message', 'Conta A.');
reset role;
select t.eq('LINK', 'reconectar não duplica o vínculo', (select count(*)::text from public.telegram_links where user_id = :UA), '1');
select t.eq('LINK', 'o token usado é apagado', (select count(*)::text from public.telegram_link_tokens where user_id = :UA), '0');
