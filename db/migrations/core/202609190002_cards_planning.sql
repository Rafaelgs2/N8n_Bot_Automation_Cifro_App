-- CIFRO credit cards, invoices, planning and goals.
begin;

create table public.credit_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  institution text not null,
  credit_limit_amount_cents bigint not null,
  closing_day smallint not null,
  due_day smallint not null,
  sort_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_cards_name_not_blank check (char_length(trim(name)) between 1 and 100),
  constraint credit_cards_institution_not_blank check (char_length(trim(institution)) between 1 and 100),
  constraint credit_cards_positive_limit check (credit_limit_amount_cents > 0),
  constraint credit_cards_closing_day check (closing_day between 1 and 31),
  constraint credit_cards_due_day check (due_day between 1 and 31),
  constraint credit_cards_sort_order check (sort_order >= 0),
  unique (id,user_id)
);

create index credit_cards_active_order_idx on public.credit_cards (user_id,sort_order) where archived_at is null;

create table public.credit_card_invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null,
  invoice_month date not null,
  opening_balance_amount_cents bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_card_invoices_month_start check (invoice_month = date_trunc('month',invoice_month)::date),
  constraint credit_card_invoices_nonnegative_opening check (opening_balance_amount_cents >= 0),
  unique (id,user_id),
  unique (id,user_id,card_id),
  unique (card_id,invoice_month),
  foreign key (card_id,user_id) references public.credit_cards(id,user_id) on delete restrict
);

create index credit_card_invoices_user_month_idx on public.credit_card_invoices (user_id,invoice_month desc);

create table public.credit_card_transactions (
  event_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null,
  total_amount_cents bigint not null,
  installment_count smallint not null default 1,
  created_at timestamptz not null default now(),
  constraint credit_card_transactions_positive_total check (total_amount_cents > 0),
  constraint credit_card_transactions_installment_count check (installment_count between 1 and 48),
  constraint credit_card_transactions_splittable check (total_amount_cents >= installment_count),
  unique (event_id,user_id),
  unique (event_id,user_id,card_id),
  foreign key (event_id,user_id) references public.financial_events(id,user_id) on delete restrict,
  foreign key (card_id,user_id) references public.credit_cards(id,user_id) on delete restrict
);

create index credit_card_transactions_user_card_idx on public.credit_card_transactions (user_id,card_id,event_id);

create table public.credit_card_installments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null,
  transaction_event_id uuid not null,
  invoice_id uuid not null,
  installment_number smallint not null,
  amount_cents bigint not null,
  created_at timestamptz not null default now(),
  constraint credit_card_installments_positive_number check (installment_number > 0),
  constraint credit_card_installments_positive_amount check (amount_cents > 0),
  unique (id,user_id),
  unique (transaction_event_id,installment_number),
  foreign key (transaction_event_id,user_id,card_id) references public.credit_card_transactions(event_id,user_id,card_id) on delete restrict,
  foreign key (invoice_id,user_id,card_id) references public.credit_card_invoices(id,user_id,card_id) on delete restrict
);

create index credit_card_installments_user_invoice_idx on public.credit_card_installments (user_id,invoice_id,installment_number);

create table public.invoice_payments (
  event_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  invoice_id uuid not null,
  account_entry_id uuid not null,
  amount_cents bigint not null,
  created_at timestamptz not null default now(),
  constraint invoice_payments_positive_amount check (amount_cents > 0),
  unique (event_id,user_id),
  unique (account_entry_id),
  foreign key (event_id,user_id) references public.financial_events(id,user_id) on delete restrict,
  foreign key (invoice_id,user_id) references public.credit_card_invoices(id,user_id) on delete restrict,
  foreign key (account_entry_id,user_id) references public.account_entries(id,user_id) on delete restrict
);

create index invoice_payments_user_invoice_idx on public.invoice_payments (user_id,invoice_id,event_id);

create table public.commitments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  kind public.category_kind not null,
  amount_cents bigint not null,
  due_on date not null,
  account_id uuid not null,
  category_id uuid not null,
  settled_event_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commitments_name_not_blank check (char_length(trim(name)) between 1 and 100),
  constraint commitments_positive_amount check (amount_cents > 0),
  unique (id,user_id),
  unique (user_id,settled_event_id),
  foreign key (account_id,user_id) references public.financial_accounts(id,user_id) on delete restrict,
  foreign key (category_id,user_id) references public.categories(id,user_id) on delete restrict,
  foreign key (settled_event_id,user_id) references public.financial_events(id,user_id) on delete restrict
);

create index commitments_user_due_idx on public.commitments (user_id,due_on);

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  account_id uuid not null,
  name text not null,
  target_amount_cents bigint not null,
  target_date date not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint goals_name_not_blank check (char_length(trim(name)) between 1 and 100),
  constraint goals_positive_target check (target_amount_cents > 0),
  unique (id,user_id),
  foreign key (account_id,user_id) references public.financial_accounts(id,user_id) on delete restrict
);

create index goals_user_target_date_idx on public.goals (user_id,target_date) where archived_at is null;

create trigger credit_cards_set_updated_at before update on public.credit_cards for each row execute function public.set_updated_at();
create trigger credit_card_invoices_set_updated_at before update on public.credit_card_invoices for each row execute function public.set_updated_at();
create trigger commitments_set_updated_at before update on public.commitments for each row execute function public.set_updated_at();
create trigger goals_set_updated_at before update on public.goals for each row execute function public.set_updated_at();

alter table public.financial_events drop constraint financial_events_category_shape;
alter table public.financial_events add constraint financial_events_category_shape check (
  (kind in ('income','expense','card_purchase') and category_id is not null)
  or (kind in ('transfer','invoice_payment') and category_id is null)
);

create or replace function public.ensure_default_categories(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (user_id,kind,name,icon_key,color_hex,sort_order)
  values
    (p_user_id,'expense','Moradia','home','#6588DA',0),
    (p_user_id,'expense','Alimentação','food','#EDAB62',1),
    (p_user_id,'expense','Transporte','car','#86B6C6',2),
    (p_user_id,'expense','Lazer','fun','#A18BD5',3),
    (p_user_id,'expense','Saúde','health','#DC8592',4),
    (p_user_id,'expense','Outros','other','#93A0B5',5),
    (p_user_id,'income','Salário','work','#4F87DE',6),
    (p_user_id,'income','Vale-refeição','food','#3D9B8B',7),
    (p_user_id,'income','Renda extra','gift','#A18BD5',8),
    (p_user_id,'income','Reembolso','other','#86B6C6',9)
  on conflict do nothing;
end;
$$;

revoke all on function public.ensure_default_categories(uuid) from public;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id,display_name)
  values (new.id,nullif(trim(new.raw_user_meta_data ->> 'display_name'),''));
  perform public.ensure_default_categories(new.id);
  return new;
end;
$$;

do $$
declare profile_id uuid;
begin
  for profile_id in select id from public.profiles loop
    perform public.ensure_default_categories(profile_id);
  end loop;
end;
$$;

create or replace function public.assert_invoice_balance(p_invoice_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  invoice_total bigint;
  payment_total bigint;
begin
  select i.opening_balance_amount_cents + coalesce(sum(ci.amount_cents),0)
  into invoice_total
  from public.credit_card_invoices i
  left join public.credit_card_installments ci on ci.invoice_id = i.id
  where i.id = p_invoice_id
  group by i.id;
  if not found then return; end if;

  select coalesce(sum(ip.amount_cents),0) into payment_total
  from public.invoice_payments ip where ip.invoice_id = p_invoice_id;

  if payment_total > invoice_total then
    raise exception 'Invoice payments cannot exceed the invoice total';
  end if;
end;
$$;

create or replace function public.assert_financial_event_integrity(p_event_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  event_row public.financial_events%rowtype;
  entry_count integer;
  positive_count integer;
  negative_count integer;
  entry_total bigint;
  category_row public.categories%rowtype;
  transfer_row public.transfers%rowtype;
  source_row public.account_entries%rowtype;
  destination_row public.account_entries%rowtype;
  card_transaction_row public.credit_card_transactions%rowtype;
  installment_count integer;
  installment_total bigint;
  first_installment_number integer;
  last_installment_number integer;
  payment_row public.invoice_payments%rowtype;
  payment_entry public.account_entries%rowtype;
begin
  select * into event_row from public.financial_events where id = p_event_id;
  if not found or event_row.status = 'voided' then return; end if;

  select count(*),count(*) filter (where amount_cents > 0),count(*) filter (where amount_cents < 0),coalesce(sum(amount_cents),0)
  into entry_count,positive_count,negative_count,entry_total
  from public.account_entries where event_id = event_row.id;

  if event_row.kind <> 'transfer' and exists (select 1 from public.transfers where event_id = event_row.id) then
    raise exception 'Transfer details require a transfer event';
  end if;
  if event_row.kind <> 'card_purchase' and exists (select 1 from public.credit_card_transactions where event_id = event_row.id) then
    raise exception 'Card transaction details require a card purchase event';
  end if;
  if event_row.kind <> 'invoice_payment' and exists (select 1 from public.invoice_payments where event_id = event_row.id) then
    raise exception 'Invoice payment details require an invoice payment event';
  end if;

  if event_row.kind = 'income' then
    if entry_count <> 1 or positive_count <> 1 then raise exception 'Income events require exactly one positive account entry'; end if;
    select * into category_row from public.categories where id = event_row.category_id;
    if not found or category_row.kind <> 'income' then raise exception 'Income events require an income category'; end if;
  elsif event_row.kind = 'expense' then
    if entry_count <> 1 or negative_count <> 1 then raise exception 'Expense events require exactly one negative account entry'; end if;
    select * into category_row from public.categories where id = event_row.category_id;
    if not found or category_row.kind <> 'expense' then raise exception 'Expense events require an expense category'; end if;
  elsif event_row.kind = 'transfer' then
    if entry_count <> 2 or positive_count <> 1 or negative_count <> 1 or entry_total <> 0 then raise exception 'Transfers require two equal and opposite account entries'; end if;
    select * into transfer_row from public.transfers where event_id = event_row.id;
    if not found then raise exception 'Transfer event requires transfer details'; end if;
    select * into source_row from public.account_entries where id = transfer_row.source_entry_id;
    select * into destination_row from public.account_entries where id = transfer_row.destination_entry_id;
    if source_row.event_id <> event_row.id or destination_row.event_id <> event_row.id or source_row.amount_cents >= 0 or destination_row.amount_cents <= 0 or abs(source_row.amount_cents) <> destination_row.amount_cents or source_row.account_id = destination_row.account_id then
      raise exception 'Transfer entries are inconsistent';
    end if;
  elsif event_row.kind = 'card_purchase' then
    if entry_count <> 0 then raise exception 'Card purchases cannot create account entries'; end if;
    select * into category_row from public.categories where id = event_row.category_id;
    if not found or category_row.kind <> 'expense' then raise exception 'Card purchases require an expense category'; end if;
    select * into card_transaction_row from public.credit_card_transactions where event_id = event_row.id;
    if not found then raise exception 'Card purchase requires card transaction details'; end if;
    select count(*),coalesce(sum(amount_cents),0),min(installment_number),max(installment_number)
    into installment_count,installment_total,first_installment_number,last_installment_number
    from public.credit_card_installments where transaction_event_id = event_row.id;
    if installment_count <> card_transaction_row.installment_count
      or installment_total <> card_transaction_row.total_amount_cents
      or first_installment_number <> 1
      or last_installment_number <> card_transaction_row.installment_count then
      raise exception 'Card purchase installments must match count and total';
    end if;
  elsif event_row.kind = 'invoice_payment' then
    if entry_count <> 1 or negative_count <> 1 then raise exception 'Invoice payments require exactly one negative account entry'; end if;
    select * into payment_row from public.invoice_payments where event_id = event_row.id;
    if not found then raise exception 'Invoice payment requires payment details'; end if;
    select * into payment_entry from public.account_entries where id = payment_row.account_entry_id;
    if payment_entry.event_id <> event_row.id or payment_entry.amount_cents >= 0 or abs(payment_entry.amount_cents) <> payment_row.amount_cents then
      raise exception 'Invoice payment entry is inconsistent';
    end if;
  end if;
end;
$$;

create or replace function public.validate_commitment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  category_kind public.category_kind;
  settled_kind public.event_kind;
begin
  select kind into category_kind from public.categories where id = new.category_id and user_id = new.user_id;
  if not found or category_kind <> new.kind then
    raise exception 'Commitment category must have the same kind';
  end if;
  if new.settled_event_id is not null then
    select kind into settled_kind from public.financial_events where id = new.settled_event_id and user_id = new.user_id;
    if not found or settled_kind::text <> new.kind::text then
      raise exception 'Commitment settlement must use a matching income or expense event';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.validate_event_from_card_transaction()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.event_id else new.event_id end);
  return null;
end;
$$;

create or replace function public.validate_event_from_installment()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.transaction_event_id else new.transaction_event_id end);
  perform public.assert_invoice_balance(case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end);
  return null;
end;
$$;

create or replace function public.validate_event_from_invoice_payment()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.event_id else new.event_id end);
  perform public.assert_invoice_balance(case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end);
  return null;
end;
$$;

create or replace function public.validate_invoice_balance_from_invoice()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_invoice_balance(case when tg_op = 'DELETE' then old.id else new.id end);
  return null;
end;
$$;

create constraint trigger credit_card_transactions_integrity_check after insert or update or delete on public.credit_card_transactions deferrable initially deferred for each row execute function public.validate_event_from_card_transaction();
create constraint trigger credit_card_installments_integrity_check after insert or update or delete on public.credit_card_installments deferrable initially deferred for each row execute function public.validate_event_from_installment();
create constraint trigger invoice_payments_integrity_check after insert or update or delete on public.invoice_payments deferrable initially deferred for each row execute function public.validate_event_from_invoice_payment();
create constraint trigger credit_card_invoices_balance_check after insert or update or delete on public.credit_card_invoices deferrable initially deferred for each row execute function public.validate_invoice_balance_from_invoice();
create trigger commitments_integrity_check before insert or update on public.commitments for each row execute function public.validate_commitment();

revoke all on function public.assert_invoice_balance(uuid),public.assert_financial_event_integrity(uuid) from public;

alter table public.credit_cards enable row level security;
alter table public.credit_card_invoices enable row level security;
alter table public.credit_card_transactions enable row level security;
alter table public.credit_card_installments enable row level security;
alter table public.invoice_payments enable row level security;
alter table public.commitments enable row level security;
alter table public.goals enable row level security;

revoke all on table public.credit_cards,public.credit_card_invoices,public.credit_card_transactions,public.credit_card_installments,public.invoice_payments,public.commitments,public.goals from anon;
grant select,insert,update on public.credit_cards,public.commitments,public.goals to authenticated;
grant select on public.credit_card_invoices,public.credit_card_transactions,public.credit_card_installments,public.invoice_payments to authenticated;

create policy credit_cards_select_own on public.credit_cards for select to authenticated using ((select auth.uid()) = user_id);
create policy credit_cards_insert_own on public.credit_cards for insert to authenticated with check ((select auth.uid()) = user_id);
create policy credit_cards_update_own on public.credit_cards for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy credit_card_invoices_select_own on public.credit_card_invoices for select to authenticated using ((select auth.uid()) = user_id);
create policy credit_card_transactions_select_own on public.credit_card_transactions for select to authenticated using ((select auth.uid()) = user_id);
create policy credit_card_installments_select_own on public.credit_card_installments for select to authenticated using ((select auth.uid()) = user_id);
create policy invoice_payments_select_own on public.invoice_payments for select to authenticated using ((select auth.uid()) = user_id);

create policy commitments_select_own on public.commitments for select to authenticated using ((select auth.uid()) = user_id);
create policy commitments_insert_own on public.commitments for insert to authenticated with check ((select auth.uid()) = user_id);
create policy commitments_update_own on public.commitments for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy goals_select_own on public.goals for select to authenticated using ((select auth.uid()) = user_id);
create policy goals_insert_own on public.goals for insert to authenticated with check ((select auth.uid()) = user_id);
create policy goals_update_own on public.goals for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

commit;
