grant usage on schema public to supabase_auth_admin;

grant execute
on function public.assert_financial_event_integrity(uuid)
to supabase_auth_admin;

alter function public.assert_financial_event_integrity(uuid)
security definer;