-- Separate migration so the enum value is committed before use.
alter type public.payment_status add value if not exists 'SIMULATED_PAID';
