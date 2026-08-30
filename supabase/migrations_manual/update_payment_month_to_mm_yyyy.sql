-- Run this in the Supabase SQL editor.
-- Changes payment_month from a bare month name (e.g. "August") to "MM/YYYY"
-- (e.g. "08/2026") so it's no longer ambiguous across years — the Dashboard's
-- Income figure now matches Fee amounts against payment_month, and a
-- name-only value would otherwise match that month in every year.
--
-- Backfill uses the year of each payment's own `date` column, since the old
-- month-name-only values never recorded a year. This is correct for the
-- common case (a fee paid a little early or late in the same year); it will
-- backfill a December fee that was actually paid in January the next year
-- under the January date's year instead of December's — spot-check rows
-- where date's month is January/February and payment_month was 'December'
-- if that matters for your records.

alter table payments drop constraint if exists payments_payment_month_check;

update payments
set payment_month = lpad(
      (array_position(
        array['January','February','March','April','May','June',
              'July','August','September','October','November','December'],
        payment_month
      ))::text, 2, '0'
    ) || '/' || extract(year from date)::text
where payment_month is not null
  and payment_month <> ''
  and payment_month !~ '^(0[1-9]|1[0-2])/\d{4}$';

alter table payments
  add constraint payments_payment_month_check
  check (payment_month is null or payment_month ~ '^(0[1-9]|1[0-2])/\d{4}$');
