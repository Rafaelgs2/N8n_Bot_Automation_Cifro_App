-- Constraint triggers run with the authenticated caller role, even when invoked by a security-definer RPC.
-- These functions keep RLS in effect and only validate already-authorized rows.
begin;

grant execute on function public.assert_financial_event_integrity(uuid) to authenticated;
grant execute on function public.assert_invoice_balance(uuid) to authenticated;

commit;
