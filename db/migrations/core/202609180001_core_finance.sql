-- CIFRO core financial ledger. Run through Supabase migrations; do not execute piecemeal.
begin;

create extension if not exists pgcrypto;

create type public.category_kind as enum ('income','expense');
create type public.account_kind as enum ('salary','meal_benefit','investment','reserve','other');
create type public.event_kind as enum ('income','expense','transfer');
create type public.event_status as enum ('posted','voided');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  timezone_name text not null default 'America/Sao_Paulo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (display_name is null or char_length(trim(display_name)) between 1 and 60)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind public.category_kind not null,
  name text not null,
  icon_key text not null default 'other',
  color_hex char(7) not null default '#6588DA',
  sort_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_name_not_blank check (char_length(trim(name)) between 1 and 100),
  constraint categories_color_hex check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  constraint categories_sort_order check (sort_order >= 0),
  unique (id,user_id)
);

create unique index categories_active_name_key on public.categories (user_id,kind,lower(name)) where archived_at is null;
create index categories_user_kind_order_idx on public.categories (user_id,kind,sort_order);

create table public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  kind public.account_kind not null default 'other',
  opening_balance_amount_cents bigint not null default 0,
  balance_as_of_date date not null,
  sort_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_accounts_name_not_blank check (char_length(trim(name)) between 1 and 100),
  constraint financial_accounts_sort_order check (sort_order >= 0),
  unique (id,user_id)
);

create index financial_accounts_active_order_idx on public.financial_accounts (user_id,sort_order) where archived_at is null;

create table public.financial_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind public.event_kind not null,
  status public.event_status not null default 'posted',
  occurred_on date not null,
  description text not null,
  category_id uuid,
  notes text,
  reversal_of_event_id uuid,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_events_description_not_blank check (char_length(trim(description)) between 1 and 100),
  constraint financial_events_notes_length check (notes is null or char_length(notes) <= 1000),
  constraint financial_events_voided_state check ((status = 'voided') = (voided_at is not null)),
  constraint financial_events_not_self_reversal check (reversal_of_event_id is null or reversal_of_event_id <> id),
  constraint financial_events_category_shape check ((kind in ('income','expense') and category_id is not null) or (kind = 'transfer' and category_id is null)),
  unique (id,user_id),
  foreign key (category_id,user_id) references public.categories(id,user_id) on delete restrict,
  foreign key (reversal_of_event_id,user_id) references public.financial_events(id,user_id) on delete restrict
);

create index financial_events_user_date_idx on public.financial_events (user_id,occurred_on desc);
create index financial_events_user_kind_date_idx on public.financial_events (user_id,kind,occurred_on desc);
create index financial_events_user_category_date_idx on public.financial_events (user_id,category_id,occurred_on desc) where category_id is not null;

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null,
  account_id uuid not null,
  amount_cents bigint not null,
  created_at timestamptz not null default now(),
  constraint account_entries_nonzero_amount check (amount_cents <> 0),
  unique (id,user_id),
  unique (event_id,account_id),
  foreign key (event_id,user_id) references public.financial_events(id,user_id) on delete restrict,
  foreign key (account_id,user_id) references public.financial_accounts(id,user_id) on delete restrict
);

create index account_entries_user_account_event_idx on public.account_entries (user_id,account_id,event_id);

create table public.transfers (
  event_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_entry_id uuid not null,
  destination_entry_id uuid not null,
  constraint transfers_distinct_entries check (source_entry_id <> destination_entry_id),
  unique (event_id,user_id),
  unique (source_entry_id),
  unique (destination_entry_id),
  foreign key (event_id,user_id) references public.financial_events(id,user_id) on delete restrict,
  foreign key (source_entry_id,user_id) references public.account_entries(id,user_id) on delete restrict,
  foreign key (destination_entry_id,user_id) references public.account_entries(id,user_id) on delete restrict
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger categories_set_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger financial_accounts_set_updated_at before update on public.financial_accounts for each row execute function public.set_updated_at();
create trigger financial_events_set_updated_at before update on public.financial_events for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id,display_name)
  values (new.id,nullif(trim(new.raw_user_meta_data ->> 'display_name'),''));
  return new;
end;
$$;

create trigger auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Backfill profiles for users created before this migration was applied.
insert into public.profiles (id,display_name)
select id,nullif(trim(raw_user_meta_data ->> 'display_name'),'')
from auth.users
on conflict (id) do nothing;

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
begin
  select * into event_row from public.financial_events where id = p_event_id;
  if not found or event_row.status = 'voided' then return; end if;

  select count(*),count(*) filter (where amount_cents > 0),count(*) filter (where amount_cents < 0),coalesce(sum(amount_cents),0)
  into entry_count,positive_count,negative_count,entry_total
  from public.account_entries where event_id = event_row.id;

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
  end if;
end;
$$;

create or replace function public.validate_event_from_event()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.id else new.id end);
  return null;
end;
$$;

create or replace function public.validate_event_from_entry()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.event_id else new.event_id end);
  return null;
end;
$$;

create or replace function public.validate_event_from_transfer()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public.assert_financial_event_integrity(case when tg_op = 'DELETE' then old.event_id else new.event_id end);
  return null;
end;
$$;

create constraint trigger financial_events_integrity_check after insert or update or delete on public.financial_events deferrable initially deferred for each row execute function public.validate_event_from_event();
create constraint trigger account_entries_integrity_check after insert or update or delete on public.account_entries deferrable initially deferred for each row execute function public.validate_event_from_entry();
create constraint trigger transfers_integrity_check after insert or update or delete on public.transfers deferrable initially deferred for each row execute function public.validate_event_from_transfer();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.financial_events enable row level security;
alter table public.account_entries enable row level security;
alter table public.transfers enable row level security;

revoke all on table public.profiles,public.categories,public.financial_accounts,public.financial_events,public.account_entries,public.transfers from anon;
grant select,update on public.profiles to authenticated;
grant select,insert,update on public.categories,public.financial_accounts to authenticated;
grant select on public.financial_events,public.account_entries,public.transfers to authenticated;

create policy profiles_select_own on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update_own on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy categories_select_own on public.categories for select to authenticated using ((select auth.uid()) = user_id);
create policy categories_insert_own on public.categories for insert to authenticated with check ((select auth.uid()) = user_id);
create policy categories_update_own on public.categories for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy accounts_select_own on public.financial_accounts for select to authenticated using ((select auth.uid()) = user_id);
create policy accounts_insert_own on public.financial_accounts for insert to authenticated with check ((select auth.uid()) = user_id);
create policy accounts_update_own on public.financial_accounts for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy financial_events_select_own on public.financial_events for select to authenticated using ((select auth.uid()) = user_id);
create policy account_entries_select_own on public.account_entries for select to authenticated using ((select auth.uid()) = user_id);
create policy transfers_select_own on public.transfers for select to authenticated using ((select auth.uid()) = user_id);

commit;
