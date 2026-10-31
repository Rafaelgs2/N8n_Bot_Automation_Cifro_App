-- Deleting an Auth user cascades through the financial tables as
-- supabase_auth_admin. Deferred constraint triggers call this validator
-- during that cascade, so the Auth role needs to execute it.
grant usage on schema public to supabase_auth_admin;

grant execute
on function public.assert_invoice_balance(uuid)
to supabase_auth_admin;

-- The validator reads RLS-protected finance tables while a user cascade is
-- running. Its fixed search_path and no-argument-free signature make this
-- safe to run with the function owner's privileges.
alter function public.assert_invoice_balance(uuid)
security definer;
