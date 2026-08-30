-- Run this in the Supabase SQL editor (or via `supabase db push` if you adopt migrations).
-- Adds the Payment Mode field to the Fee Update "Record Payment" screen.

alter table payments
  add column if not exists payment_mode text not null default 'Cash'
    check (payment_mode in ('Cash', 'Card', 'Bank Transfer', 'Payment Link'));

-- Drop the default once existing rows are backfilled, so future inserts must
-- explicitly choose a mode (the frontend always sends one).
alter table payments alter column payment_mode drop default;
