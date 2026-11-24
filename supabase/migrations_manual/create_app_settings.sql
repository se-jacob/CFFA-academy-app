-- App Settings: one row of app-wide settings, edited on the Settings page (Super Admins only).
--   fee_history_from      Fee History hides payments made before this date (display only)
--   term_start/term_end   Current term dates (term start also sets the Dashboard start month)
--   dashboard_start_month Earliest month the Dashboard month picker offers (stored as the 1st)
--
-- Run once in the Supabase SQL Editor (SQL Editor > New query > paste > Run). Safe to re-run.
-- Not a duplicate of any existing table: the app had no settings storage before this.

create table if not exists public.app_settings (
  id smallint primary key default 1 check (id = 1),   -- exactly one row
  fee_history_from date,
  term_start date,
  term_end date,
  dashboard_start_month date check (dashboard_start_month is null or extract(day from dashboard_start_month) = 1),
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  constraint app_settings_term_order check (term_start is null or term_end is null or term_end >= term_start)
);

-- The single settings row (empty = built-in defaults).
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

-- Keep "who changed it / when" current.
create or replace function public.app_settings_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists app_settings_touch on public.app_settings;
create trigger app_settings_touch
  before update on public.app_settings
  for each row execute function public.app_settings_touch();

-- Row Level Security: every signed-in admin can READ (the app needs the values everywhere);
-- only Super Admins can add or change; nobody can delete the row.
alter table public.app_settings enable row level security;

drop policy if exists "app_settings select" on public.app_settings;
create policy "app_settings select" on public.app_settings
  for select using (auth.uid() is not null);

drop policy if exists "app_settings insert" on public.app_settings;
create policy "app_settings insert" on public.app_settings
  for insert with check (public.is_super_admin());

drop policy if exists "app_settings update" on public.app_settings;
create policy "app_settings update" on public.app_settings
  for update using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "app_settings delete" on public.app_settings;
create policy "app_settings delete" on public.app_settings
  for delete using (false);

-- Quick check — should show the settings row and the four policies.
select id, fee_history_from, term_start, term_end, dashboard_start_month from public.app_settings;
select policyname, cmd from pg_policies where tablename = 'app_settings' order by cmd;
