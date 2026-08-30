-- Run this in the Supabase SQL editor.
-- Adds the Payment Month field to the Fee Update "Record Payment" screen.
--
-- Nullable with no default (learned from the payment_mode rollout): existing
-- rows come in blank rather than being defaulted to a fabricated value. The
-- frontend enforces Payment Month as mandatory for new payments and edits.

alter table payments
  add column if not exists payment_month text
    check (payment_month in (
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ));
