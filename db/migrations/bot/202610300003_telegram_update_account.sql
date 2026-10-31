-- Changing where bot expenses go must not replace the secret, or the automation stops working.
begin;

create or replace function public.update_telegram_account(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if not exists (select 1 from public.financial_accounts where id = p_account_id and user_id = v_user_id and archived_at is null) then
    raise exception 'Account not found' using errcode = '22023';
  end if;
  update public.telegram_links set default_account_id = p_account_id where user_id = v_user_id;
  if not found then raise exception 'Telegram not linked' using errcode = 'P0002'; end if;
end;
$$;

revoke all on function public.update_telegram_account(uuid) from public,anon,authenticated;
grant execute on function public.update_telegram_account(uuid) to authenticated;

commit;
