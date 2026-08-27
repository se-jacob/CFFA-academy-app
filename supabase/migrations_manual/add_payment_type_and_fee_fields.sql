-- Run this in the Supabase SQL editor (or via `supabase db push` if you adopt migrations).
-- Adds fields needed for the Fee Update "Record Payment" screen's Payment Type split.

alter table payments
  add column if not exists payment_type text not null default 'Fee'
    check (payment_type in ('Fee', 'Extra Jersey', 'Full Kit')),
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists registration_fee_amount numeric(10,2);

-- Drop the default once existing rows are backfilled, so future inserts must
-- explicitly choose a type (the frontend always sends one).
alter table payments alter column payment_type drop default;
