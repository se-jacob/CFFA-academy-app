-- Run this in the Supabase SQL editor.
--
-- The earlier add_payment_mode.sql migration added payment_mode as
-- `not null default 'Cash'`, which silently backfilled every pre-existing
-- payment row to 'Cash' even though that mode was never actually recorded.
-- Payment Mode is now a mandatory field in the Record Payment form going
-- forward, but existing rows should show blank rather than a fabricated
-- 'Cash' value.
--
-- CAUTION: this assumes no admin has genuinely selected "Cash" through the
-- Record Payment / Update Last Payment screens since payment_mode was
-- introduced (i.e. every current 'Cash' value came from the column default,
-- not a real choice). If any payments have been recorded with a real,
-- intentional "Cash" selection since that rollout, review before running —
-- this cannot tell a real "Cash" apart from a defaulted one.

-- Allow the column to be blank at the database level for old/unrecorded
-- rows. The frontend enforces "mandatory" for new payments and edits.
-- (This must run before the update below, or nulling the column violates
-- the still-active not-null constraint.)
alter table payments alter column payment_mode drop not null;

update payments set payment_mode = null where payment_mode = 'Cash';
