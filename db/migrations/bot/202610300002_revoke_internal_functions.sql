-- Supabase can grant new functions in public directly to anon and authenticated, and "revoke from
-- public" does not remove those grants. These functions run with the owner's privileges, and none
-- of them is part of the API, so close them whatever the project's default privileges are.
begin;

-- Called only from handle_new_user, which runs as the owner. Open, it would let a caller add
-- categories to any user id.
revoke all on function public.ensure_default_categories(uuid) from public,anon,authenticated;

-- Fires as a trigger, which does not check execute at run time.
revoke all on function public.handle_new_user() from public,anon,authenticated;

-- authenticated and supabase_auth_admin keep their grants: deferred triggers run these validators
-- as the caller. capture_expense runs them under its own role, so anon needs nothing here.
revoke all on function public.assert_financial_event_integrity(uuid) from public,anon;
revoke all on function public.assert_invoice_balance(uuid) from public,anon;

commit;
