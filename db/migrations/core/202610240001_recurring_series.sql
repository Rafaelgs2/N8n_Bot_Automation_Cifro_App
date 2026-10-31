-- A recurring event starts a series: the app plans its later months (or years) as commitments,
-- and each one only becomes an event when the user confirms it. Nothing here posts automatically.
begin;

alter table public.financial_events
  add column recurrence_frequency text not null default 'monthly',
  add column recurrence_until date,
  add column series_event_id uuid,
  add column series_month date,
  add constraint financial_events_recurrence_frequency check (recurrence_frequency in ('monthly','yearly')),
  add constraint financial_events_recurrence_until_shape check (recurrence_until is null or (recurrence_until = date_trunc('month',recurrence_until)::date and recurrence_until >= date_trunc('month',occurred_on)::date)),
  add constraint financial_events_series_shape check ((series_event_id is null) = (series_month is null) and (series_month is null or series_month = date_trunc('month',series_month)::date)),
  add constraint financial_events_not_own_series check (series_event_id is null or series_event_id <> id),
  -- Deferred: save_finance_state rewrites every event before deleting the removed ones, so the
  -- series links only have to hold once the whole state is in place.
  add constraint financial_events_series_month_unique unique (series_event_id,series_month) deferrable initially deferred,
  add constraint financial_events_series_fk foreign key (series_event_id,user_id) references public.financial_events(id,user_id) deferrable initially deferred;

create or replace function public.finance_state_payload()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_state jsonb;
  v_revision bigint;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;

  insert into public.finance_revisions (user_id) values (v_user_id) on conflict (user_id) do nothing;
  select revision into v_revision from public.finance_revisions where user_id = v_user_id;

  select jsonb_build_object(
    'profile',jsonb_build_object('name',coalesce((select display_name from public.profiles where id = v_user_id),'')),
    'categories',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',id::text,'name',name,'type',kind::text,'color',lower(color_hex),
        'icon',icon_key,'order',sort_order
      ) order by sort_order,id)
      from public.categories where user_id = v_user_id and archived_at is null
    ),'[]'::jsonb),
    'accounts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',id::text,'name',name,
        'kind',case when kind = 'meal_benefit' then 'vr' else kind::text end,
        'initial',opening_balance_amount_cents,'date',balance_as_of_date::text,
        'archived',archived_at is not null,'order',sort_order
      ) order by sort_order,id)
      from public.financial_accounts where user_id = v_user_id
    ),'[]'::jsonb),
    'cards',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id::text,'name',c.name,'institution',c.institution,
        'limit',c.credit_limit_amount_cents,'closing',c.closing_day,'due',c.due_day,
        'initial',coalesce((select i.opening_balance_amount_cents from public.credit_card_invoices i where i.card_id = c.id and i.invoice_month = c.initial_invoice_month),0),
        'initialMonth',to_char(c.initial_invoice_month,'YYYY-MM')
      ) order by c.sort_order,c.id)
      from public.credit_cards c where c.user_id = v_user_id and c.archived_at is null
    ),'[]'::jsonb),
    'transactions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id::text,
        'type',case e.kind when 'card_purchase' then 'purchase' when 'invoice_payment' then 'payment' else e.kind::text end,
        'description',e.description,
        'amount',case e.kind
          when 'card_purchase' then (select ct.total_amount_cents from public.credit_card_transactions ct where ct.event_id=e.id)
          when 'invoice_payment' then (select ip.amount_cents from public.invoice_payments ip where ip.event_id=e.id)
          when 'transfer' then (select abs(ae.amount_cents) from public.transfers t join public.account_entries ae on ae.id=t.source_entry_id where t.event_id=e.id)
          else (select abs(ae.amount_cents) from public.account_entries ae where ae.event_id=e.id limit 1)
        end,
        'date',e.occurred_on::text,
        'accountId',coalesce(case e.kind
          when 'transfer' then (select ae.account_id::text from public.transfers t join public.account_entries ae on ae.id=t.source_entry_id where t.event_id=e.id)
          when 'invoice_payment' then (select ae.account_id::text from public.invoice_payments ip join public.account_entries ae on ae.id=ip.account_entry_id where ip.event_id=e.id)
          when 'income' then (select ae.account_id::text from public.account_entries ae where ae.event_id=e.id limit 1)
          when 'expense' then (select ae.account_id::text from public.account_entries ae where ae.event_id=e.id limit 1)
          else '' end,''),
        'destinationId',coalesce((select ae.account_id::text from public.transfers t join public.account_entries ae on ae.id=t.destination_entry_id where t.event_id=e.id),''),
        'cardId',coalesce(case e.kind
          when 'card_purchase' then (select ct.card_id::text from public.credit_card_transactions ct where ct.event_id=e.id)
          when 'invoice_payment' then (select i.card_id::text from public.invoice_payments ip join public.credit_card_invoices i on i.id=ip.invoice_id where ip.event_id=e.id)
          else '' end,''),
        'categoryId',coalesce(e.category_id::text,''),
        'notes',coalesce(e.notes,''),
        'recurring',e.is_recurring_hint,
        'frequency',e.recurrence_frequency,
        'recurringUntil',coalesce(to_char(e.recurrence_until,'YYYY-MM'),''),
        'seriesId',coalesce(e.series_event_id::text,''),
        'seriesMonth',coalesce(to_char(e.series_month,'YYYY-MM'),''),
        'installments',coalesce((select ct.installment_count from public.credit_card_transactions ct where ct.event_id=e.id),1),
        'invoiceMonth',coalesce((select to_char(i.invoice_month,'YYYY-MM') from public.invoice_payments ip join public.credit_card_invoices i on i.id=ip.invoice_id where ip.event_id=e.id),'')
      ) order by e.occurred_on,e.created_at,e.id)
      from public.financial_events e where e.user_id = v_user_id and e.status = 'posted'
    ),'[]'::jsonb),
    'bills',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',id::text,'name',name,'amount',amount_cents,'date',due_on::text,
        'type',kind::text,'accountId',account_id::text,'categoryId',category_id::text,
        'transactionId',coalesce(settled_event_id::text,'')
      ) order by due_on,id)
      from public.commitments where user_id = v_user_id
    ),'[]'::jsonb),
    'goals',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',id::text,'name',name,'target',target_amount_cents,
        'accountId',account_id::text,'date',target_date::text
      ) order by target_date,id)
      from public.goals where user_id = v_user_id and archived_at is null
    ),'[]'::jsonb)
  ) into v_state;

  return jsonb_build_object('state',v_state,'revision',v_revision);
end;
$$;

create or replace function public.save_finance_state(p_state jsonb,p_expected_revision bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
  item jsonb;
  tx jsonb;
  v_kind public.event_kind;
  v_source_entry uuid;
  v_destination_entry uuid;
  v_invoice_id uuid;
  v_invoice_month date;
  v_first_invoice date;
  v_installment_count integer;
  v_installment_number integer;
  v_base_amount bigint;
  v_remainder bigint;
  v_installment_amount bigint;
  v_closing_day integer;
  v_due_day integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if jsonb_typeof(p_state) <> 'object' then raise exception 'Invalid financial state'; end if;

  insert into public.finance_revisions (user_id) values (v_user_id) on conflict (user_id) do nothing;
  select revision into v_revision from public.finance_revisions where user_id = v_user_id for update;
  if v_revision <> p_expected_revision then
    raise exception 'Financial state changed in another session' using errcode = '40001';
  end if;

  update public.profiles
  set display_name = nullif(trim(p_state #>> '{profile,name}'),'')
  where id = v_user_id;

  for item in select value from jsonb_array_elements(p_state->'categories') loop
    insert into public.categories (id,user_id,kind,name,icon_key,color_hex,sort_order,archived_at)
    values ((item->>'id')::uuid,v_user_id,(item->>'type')::public.category_kind,item->>'name',item->>'icon',upper(item->>'color'),(item->>'order')::integer,null)
    on conflict (id) do update set kind=excluded.kind,name=excluded.name,icon_key=excluded.icon_key,color_hex=excluded.color_hex,sort_order=excluded.sort_order,archived_at=null,updated_at=now()
    where public.categories.user_id = v_user_id;
  end loop;

  for item in select value from jsonb_array_elements(p_state->'accounts') loop
    insert into public.financial_accounts (id,user_id,name,kind,opening_balance_amount_cents,balance_as_of_date,sort_order,archived_at)
    values ((item->>'id')::uuid,v_user_id,item->>'name',
      (case item->>'kind' when 'vr' then 'meal_benefit' else item->>'kind' end)::public.account_kind,
      (item->>'initial')::bigint,(item->>'date')::date,(item->>'order')::integer,
      case when (item->>'archived')::boolean then now() else null end)
    on conflict (id) do update set name=excluded.name,kind=excluded.kind,opening_balance_amount_cents=excluded.opening_balance_amount_cents,balance_as_of_date=excluded.balance_as_of_date,sort_order=excluded.sort_order,archived_at=excluded.archived_at,updated_at=now()
    where public.financial_accounts.user_id = v_user_id;
  end loop;

  for item in select value from jsonb_array_elements(p_state->'cards') loop
    insert into public.credit_cards (id,user_id,name,institution,credit_limit_amount_cents,closing_day,due_day,sort_order,initial_invoice_month,archived_at)
    values ((item->>'id')::uuid,v_user_id,item->>'name',item->>'institution',(item->>'limit')::bigint,(item->>'closing')::smallint,(item->>'due')::smallint,0,((item->>'initialMonth')||'-01')::date,null)
    on conflict (id) do update set name=excluded.name,institution=excluded.institution,credit_limit_amount_cents=excluded.credit_limit_amount_cents,closing_day=excluded.closing_day,due_day=excluded.due_day,initial_invoice_month=excluded.initial_invoice_month,archived_at=null,updated_at=now()
    where public.credit_cards.user_id = v_user_id;
  end loop;

  delete from public.commitments where user_id = v_user_id;
  delete from public.goals where user_id = v_user_id;
  delete from public.invoice_payments where user_id = v_user_id;
  delete from public.credit_card_installments where user_id = v_user_id;
  delete from public.credit_card_transactions where user_id = v_user_id;
  delete from public.transfers where user_id = v_user_id;
  delete from public.account_entries where user_id = v_user_id;
  delete from public.credit_card_invoices where user_id = v_user_id;

  for tx in select value from jsonb_array_elements(p_state->'transactions') loop
    v_kind := (case tx->>'type' when 'purchase' then 'card_purchase' when 'payment' then 'invoice_payment' else tx->>'type' end)::public.event_kind;
    insert into public.financial_events (id,user_id,kind,status,occurred_on,description,category_id,notes,is_recurring_hint,recurrence_frequency,recurrence_until,series_event_id,series_month,voided_at,reversal_of_event_id)
    values ((tx->>'id')::uuid,v_user_id,v_kind,'posted',(tx->>'date')::date,tx->>'description',nullif(tx->>'categoryId','')::uuid,nullif(tx->>'notes',''),coalesce((tx->>'recurring')::boolean,false),
      coalesce(nullif(tx->>'frequency',''),'monthly'),(nullif(tx->>'recurringUntil','')||'-01')::date,nullif(tx->>'seriesId','')::uuid,(nullif(tx->>'seriesMonth','')||'-01')::date,null,null)
    on conflict (id) do update set kind=excluded.kind,status='posted',occurred_on=excluded.occurred_on,description=excluded.description,category_id=excluded.category_id,notes=excluded.notes,is_recurring_hint=excluded.is_recurring_hint,recurrence_frequency=excluded.recurrence_frequency,recurrence_until=excluded.recurrence_until,series_event_id=excluded.series_event_id,series_month=excluded.series_month,voided_at=null,reversal_of_event_id=null,updated_at=now()
    where public.financial_events.user_id = v_user_id;
  end loop;

  delete from public.financial_events e
  where e.user_id = v_user_id
    and not exists (select 1 from jsonb_array_elements(p_state->'transactions') value where (value->>'id')::uuid = e.id);

  for item in select value from jsonb_array_elements(p_state->'cards') loop
    if (item->>'initial')::bigint > 0 then
      insert into public.credit_card_invoices (user_id,card_id,invoice_month,opening_balance_amount_cents)
      values (v_user_id,(item->>'id')::uuid,((item->>'initialMonth')||'-01')::date,(item->>'initial')::bigint)
      on conflict (card_id,invoice_month) do update set opening_balance_amount_cents=excluded.opening_balance_amount_cents,updated_at=now();
    end if;
  end loop;

  for tx in select value from jsonb_array_elements(p_state->'transactions') loop
    if tx->>'type' in ('income','expense') then
      insert into public.account_entries (user_id,event_id,account_id,amount_cents)
      values (v_user_id,(tx->>'id')::uuid,(tx->>'accountId')::uuid,
        case when tx->>'type'='income' then (tx->>'amount')::bigint else -(tx->>'amount')::bigint end);
    elsif tx->>'type' = 'transfer' then
      v_source_entry := gen_random_uuid();
      v_destination_entry := gen_random_uuid();
      insert into public.account_entries (id,user_id,event_id,account_id,amount_cents) values
        (v_source_entry,v_user_id,(tx->>'id')::uuid,(tx->>'accountId')::uuid,-(tx->>'amount')::bigint),
        (v_destination_entry,v_user_id,(tx->>'id')::uuid,(tx->>'destinationId')::uuid,(tx->>'amount')::bigint);
      insert into public.transfers (event_id,user_id,source_entry_id,destination_entry_id)
      values ((tx->>'id')::uuid,v_user_id,v_source_entry,v_destination_entry);
    elsif tx->>'type' = 'purchase' then
      select closing_day,due_day into v_closing_day,v_due_day from public.credit_cards where id=(tx->>'cardId')::uuid and user_id=v_user_id;
      v_first_invoice := public.invoice_month_for_purchase((tx->>'date')::date,v_closing_day,v_due_day);
      v_installment_count := (tx->>'installments')::integer;
      v_base_amount := (tx->>'amount')::bigint / v_installment_count;
      v_remainder := (tx->>'amount')::bigint % v_installment_count;
      insert into public.credit_card_transactions (event_id,user_id,card_id,total_amount_cents,installment_count)
      values ((tx->>'id')::uuid,v_user_id,(tx->>'cardId')::uuid,(tx->>'amount')::bigint,v_installment_count);
      for v_installment_number in 1..v_installment_count loop
        v_invoice_month := (v_first_invoice + make_interval(months => v_installment_number - 1))::date;
        insert into public.credit_card_invoices (user_id,card_id,invoice_month)
        values (v_user_id,(tx->>'cardId')::uuid,v_invoice_month)
        on conflict (card_id,invoice_month) do update set invoice_month=excluded.invoice_month
        returning id into v_invoice_id;
        v_installment_amount := v_base_amount + case when v_installment_number <= v_remainder then 1 else 0 end;
        insert into public.credit_card_installments (user_id,card_id,transaction_event_id,invoice_id,installment_number,amount_cents)
        values (v_user_id,(tx->>'cardId')::uuid,(tx->>'id')::uuid,v_invoice_id,v_installment_number,v_installment_amount);
      end loop;
    elsif tx->>'type' = 'payment' then
      v_invoice_month := ((tx->>'invoiceMonth')||'-01')::date;
      insert into public.credit_card_invoices (user_id,card_id,invoice_month)
      values (v_user_id,(tx->>'cardId')::uuid,v_invoice_month)
      on conflict (card_id,invoice_month) do update set invoice_month=excluded.invoice_month
      returning id into v_invoice_id;
      v_source_entry := gen_random_uuid();
      insert into public.account_entries (id,user_id,event_id,account_id,amount_cents)
      values (v_source_entry,v_user_id,(tx->>'id')::uuid,(tx->>'accountId')::uuid,-(tx->>'amount')::bigint);
      insert into public.invoice_payments (event_id,user_id,invoice_id,account_entry_id,amount_cents)
      values ((tx->>'id')::uuid,v_user_id,v_invoice_id,v_source_entry,(tx->>'amount')::bigint);
    end if;
  end loop;

  for item in select value from jsonb_array_elements(p_state->'bills') loop
    insert into public.commitments (id,user_id,name,kind,amount_cents,due_on,account_id,category_id,settled_event_id)
    values ((item->>'id')::uuid,v_user_id,item->>'name',(item->>'type')::public.category_kind,(item->>'amount')::bigint,(item->>'date')::date,(item->>'accountId')::uuid,(item->>'categoryId')::uuid,nullif(item->>'transactionId','')::uuid);
  end loop;

  for item in select value from jsonb_array_elements(p_state->'goals') loop
    insert into public.goals (id,user_id,account_id,name,target_amount_cents,target_date)
    values ((item->>'id')::uuid,v_user_id,(item->>'accountId')::uuid,item->>'name',(item->>'target')::bigint,(item->>'date')::date);
  end loop;

  delete from public.categories c where c.user_id=v_user_id and not exists (select 1 from jsonb_array_elements(p_state->'categories') value where (value->>'id')::uuid=c.id);
  delete from public.financial_accounts a where a.user_id=v_user_id and not exists (select 1 from jsonb_array_elements(p_state->'accounts') value where (value->>'id')::uuid=a.id);
  delete from public.credit_cards c where c.user_id=v_user_id and not exists (select 1 from jsonb_array_elements(p_state->'cards') value where (value->>'id')::uuid=c.id);

  update public.finance_revisions set revision=revision+1,updated_at=now() where user_id=v_user_id;
  return public.finance_state_payload();
end;
$$;

commit;
