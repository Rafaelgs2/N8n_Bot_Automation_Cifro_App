-- Enum values must be committed before they are referenced by later migrations.
alter type public.event_kind add value if not exists 'card_purchase';
alter type public.event_kind add value if not exists 'invoice_payment';
