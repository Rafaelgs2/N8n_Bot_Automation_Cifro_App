-- Opens the Telegram bot to every user. The automation now proves itself with one bot secret, sent
-- as a request header, and a chat only maps to a user after a one-time link proves who owns it.
-- Replaces the per-user secret: until the automation is updated, the bot answers with a failure.
begin;

drop function public.capture_expense(bigint,text,bigint,text,bigint);
drop function public.link_telegram(bigint,uuid);
alter table public.telegram_links drop column secret_hash;

create table public.telegram_bot_settings (
  id boolean primary key default true,
  secret_hash text not null,
  updated_at timestamptz not null default now(),
  constraint telegram_bot_settings_single_row check (id)
);

alter table public.telegram_bot_settings enable row level security;
revoke all on table public.telegram_bot_settings from anon,authenticated;

create table public.telegram_link_tokens (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  default_account_id uuid,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  foreign key (default_account_id,user_id) references public.financial_accounts(id,user_id) on delete set null (default_account_id)
);

alter table public.telegram_link_tokens enable row level security;
revoke all on table public.telegram_link_tokens from anon,authenticated;

-- Run once in the SQL Editor to set or replace the bot secret. It is shown only in that result.
create function public.rotate_telegram_bot_secret()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
begin
  insert into public.telegram_bot_settings (id,secret_hash)
  values (true,encode(sha256(convert_to(v_secret,'UTF8')),'hex'))
  on conflict (id) do update set secret_hash=excluded.secret_hash,updated_at=now();
  return v_secret;
end;
$$;

-- With no secret set, nothing matches and every bot call is refused.
create function public.telegram_bot_authorized()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.telegram_bot_settings
    where secret_hash = encode(sha256(convert_to(coalesce(nullif(current_setting('request.headers',true),'')::json->>'x-cifro-bot-secret',''),'UTF8')),'hex')
  );
$$;

-- Starts a link for the signed-in user. A new one replaces any pending link of the same user.
create function public.start_telegram_link(p_account_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := replace(gen_random_uuid()::text,'-','');
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not exists (select 1 from public.financial_accounts where id = p_account_id and user_id = v_user_id and archived_at is null) then
    raise exception 'Account not found' using errcode = '22023';
  end if;
  insert into public.telegram_link_tokens (user_id,token_hash,default_account_id,expires_at)
  values (v_user_id,encode(sha256(convert_to(v_token,'UTF8')),'hex'),p_account_id,now() + interval '15 minutes')
  on conflict (user_id) do update set token_hash=excluded.token_hash,default_account_id=excluded.default_account_id,expires_at=excluded.expires_at,created_at=now();
  return v_token;
end;
$$;

-- Called by the bot when someone opens the link: holding the token proves the app account, and the
-- chat id comes from Telegram, so together they prove that both belong to the same person.
create function public.confirm_telegram_link(p_chat_id bigint,p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token public.telegram_link_tokens%rowtype;
  v_owner uuid;
  v_account_name text;
begin
  if not public.telegram_bot_authorized() then return jsonb_build_object('ok',false,'message','Bot não autorizado.'); end if;
  if p_chat_id is null then return jsonb_build_object('ok',false,'message','Mensagem inválida.'); end if;

  select * into v_token from public.telegram_link_tokens
  where token_hash = encode(sha256(convert_to(coalesce(p_token,''),'UTF8')),'hex') and expires_at > now()
  for update;
  if not found then
    return jsonb_build_object('ok',false,'message','Este link expirou ou já foi usado. Gere outro em Perfil, no Cifro.');
  end if;

  select user_id into v_owner from public.telegram_links where chat_id = p_chat_id;
  if found and v_owner <> v_token.user_id then
    return jsonb_build_object('ok',false,'message','Este Telegram já está conectado a outra conta do Cifro. Desconecte por lá primeiro.');
  end if;

  insert into public.telegram_links (user_id,chat_id,default_account_id)
  values (v_token.user_id,p_chat_id,v_token.default_account_id)
  on conflict (user_id) do update set chat_id=excluded.chat_id,default_account_id=excluded.default_account_id,updated_at=now();
  delete from public.telegram_link_tokens where user_id = v_token.user_id;

  select name into v_account_name from public.financial_accounts where id = v_token.default_account_id;
  return jsonb_build_object('ok',true,'message','✅ Telegram conectado! As despesas vão para ' || coalesce(v_account_name,'sua primeira conta ativa') || '. Mande algo como: almoço 32,50');
end;
$$;

create or replace function public.unlink_telegram()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  delete from public.telegram_links where user_id = auth.uid();
  delete from public.telegram_link_tokens where user_id = auth.uid();
end;
$$;

-- Business failures come back as {ok:false,message} so the bot can repeat the message to the user.
-- Anything written here must also pass validateState in lib/finance.ts: the app refuses to load a
-- state that fails it, so a bad row would lock the user out of all their data.
create function public.capture_telegram_expense(p_chat_id bigint,p_message_id bigint,p_description text,p_amount_cents bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_default_account uuid;
  v_today date := (now() at time zone 'America/Sao_Paulo')::date;
  v_description text := btrim(coalesce(p_description,''),E' \t\r\n');
  v_search text;
  v_account_id uuid;
  v_account_name text;
  v_category_id uuid;
  v_category_name text;
  -- A message retried by Telegram or n8n maps to the same event instead of charging twice.
  v_event_id uuid := md5(p_chat_id::text || ':' || p_message_id::text)::uuid;
begin
  if not public.telegram_bot_authorized() then return jsonb_build_object('ok',false,'message','Bot não autorizado.'); end if;

  select user_id,default_account_id into v_user_id,v_default_account
  from public.telegram_links where chat_id = p_chat_id;
  if v_user_id is null then
    return jsonb_build_object('ok',false,'message','Este Telegram ainda não está conectado. Abra Perfil, no Cifro, e toque em Conectar Telegram.');
  end if;
  if p_message_id is null then return jsonb_build_object('ok',false,'message','Mensagem inválida.'); end if;

  if p_amount_cents is null or p_amount_cents < 1 or p_amount_cents > 99999999999 then
    return jsonb_build_object('ok',false,'message','Informe um valor maior que zero.');
  end if;
  -- The app measures length in UTF-16 units, where an emoji counts twice.
  if v_description = '' or char_length(v_description) + regexp_count(v_description,'[\U00010000-\U0010FFFF]') > 100 then
    return jsonb_build_object('ok',false,'message','A descrição precisa ter de 1 a 100 caracteres.');
  end if;

  -- Same lock save_finance_state takes first, so the two never interleave.
  insert into public.finance_revisions (user_id) values (v_user_id) on conflict (user_id) do nothing;
  perform 1 from public.finance_revisions where user_id = v_user_id for update;

  if (select count(*) from public.financial_events where user_id = v_user_id) >= 20000 then
    return jsonb_build_object('ok',false,'message','O limite de lançamentos da conta foi atingido.');
  end if;

  -- An expense cannot predate the account's opening balance date.
  select id,name into v_account_id,v_account_name
  from public.financial_accounts
  where user_id = v_user_id and archived_at is null and balance_as_of_date <= v_today
  order by (id = v_default_account) is true desc,sort_order,id
  limit 1;
  if v_account_id is null then
    return jsonb_build_object('ok',false,'message','Nenhuma conta ativa pode receber este lançamento. Confira suas contas no Cifro.');
  end if;

  v_search := translate(lower(v_description),'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc');

  -- The user's own category names win over the built-in hints, and hints go through the icon,
  -- so renaming "Alimentação" keeps working.
  select id,name into v_category_id,v_category_name
  from public.categories
  where user_id = v_user_id and kind = 'expense' and archived_at is null
    -- Not \y: it needs a letter or digit at the edge, so "C++ (curso)" would never match.
    and v_search ~ ('(^|[^[:alnum:]])' || regexp_replace(translate(lower(name),'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),'([^[:alnum:][:space:]])','\\\1','g') || '($|[^[:alnum:]])')
  order by char_length(name) desc,sort_order,id
  limit 1;

  if v_category_id is null then
    select c.id,c.name into v_category_id,v_category_name
    from (values
      ('food','\y(almoco|janta|jantar|lanche|cafe|hotdog|pizza|hamburguer|restaurante|ifood|padaria|marmita|salgado|sorvete)\y',1),
      ('market','\y(mercado|supermercado|feira|hortifruti|acougue)\y',2),
      ('car','\y(uber|99|onibus|metro|gasolina|combustivel|estacionamento|pedagio|passagem)\y',3),
      ('health','\y(farmacia|remedio|medico|consulta|exame|dentista)\y',4),
      ('fun','\y(cinema|show|bar|netflix|spotify|jogo)\y',5),
      ('home','\y(aluguel|condominio|luz|energia|agua|internet)\y',6)
    ) as hint(icon_key,pattern,priority)
    join public.categories c on c.icon_key = hint.icon_key
    where c.user_id = v_user_id and c.kind = 'expense' and c.archived_at is null and v_search ~ hint.pattern
    order by hint.priority,c.sort_order,c.id
    limit 1;
  end if;

  if v_category_id is null then
    select id,name into v_category_id,v_category_name
    from public.categories
    where user_id = v_user_id and kind = 'expense' and archived_at is null
    order by (icon_key = 'other') desc,sort_order,id
    limit 1;
  end if;
  if v_category_id is null then
    return jsonb_build_object('ok',false,'message','Crie uma categoria de despesa no Cifro para registrar pelo bot.');
  end if;

  insert into public.financial_events (id,user_id,kind,occurred_on,description,category_id)
  values (v_event_id,v_user_id,'expense',v_today,v_description,v_category_id)
  on conflict (id) do nothing;
  if not found then
    return jsonb_build_object('ok',true,'duplicate',true,'account',v_account_name,'category',v_category_name,'amount_cents',p_amount_cents);
  end if;

  insert into public.account_entries (user_id,event_id,account_id,amount_cents)
  values (v_user_id,v_event_id,v_account_id,-p_amount_cents);

  -- Run the deferred integrity triggers here, under this function's role. At commit they would run
  -- as the anon caller, and the capture must not depend on what anon can execute.
  set constraints all immediate;

  update public.finance_revisions set revision=revision+1,updated_at=now() where user_id=v_user_id;
  return jsonb_build_object('ok',true,'duplicate',false,'account',v_account_name,'category',v_category_name,'amount_cents',p_amount_cents);
end;
$$;

revoke all on function public.rotate_telegram_bot_secret() from public,anon,authenticated;
revoke all on function public.telegram_bot_authorized() from public,anon,authenticated;
revoke all on function public.start_telegram_link(uuid) from public,anon,authenticated;
revoke all on function public.confirm_telegram_link(bigint,text) from public,anon,authenticated;
revoke all on function public.capture_telegram_expense(bigint,bigint,text,bigint) from public,anon,authenticated;
grant execute on function public.start_telegram_link(uuid) to authenticated;
grant execute on function public.confirm_telegram_link(bigint,text) to anon;
grant execute on function public.capture_telegram_expense(bigint,bigint,text,bigint) to anon;

commit;
