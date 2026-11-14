-- Coach Attendance: which coaches were present at a location on a given day, and how many
-- sessions (1-3) each took. Used by the "Coach Attendance" page and the Super Admin report
-- Reports > "Coach Sessions (Month)".
--
-- Run once in the Supabase SQL Editor (Dashboard > SQL Editor > New query > paste > Run).
-- Safe to re-run: every step checks whether it has already been done.
--
-- Not a duplicate of an existing table: coach_locations says where a coach CAN work and
-- session_coaches says who is SCHEDULED for a training session; neither records sessions actually
-- taken per day.

-- 1. Table. Column types for coach_id / location_id are copied from coaches.id / locations.id
--    so the foreign keys always match, whatever type those ids use.
do $$
declare
  coach_id_type text;
  location_id_type text;
begin
  select format_type(a.atttypid, a.atttypmod) into coach_id_type
  from pg_attribute a where a.attrelid = 'public.coaches'::regclass and a.attname = 'id';
  select format_type(a.atttypid, a.atttypmod) into location_id_type
  from pg_attribute a where a.attrelid = 'public.locations'::regclass and a.attname = 'id';

  execute format($f$
    create table if not exists public.coach_attendance (
      id uuid primary key default gen_random_uuid(),
      coach_id %s not null references public.coaches(id) on delete restrict,
      location_id %s not null references public.locations(id) on delete restrict,
      date date not null,
      sessions_count smallint not null check (sessions_count between 1 and 3),
      updated_by uuid default auth.uid(),
      updated_at timestamptz not null default now(),
      constraint coach_attendance_one_per_day unique (coach_id, location_id, date)
    )
  $f$, coach_id_type, location_id_type);
end $$;

create index if not exists coach_attendance_date_idx on public.coach_attendance (date);
create index if not exists coach_attendance_location_date_idx on public.coach_attendance (location_id, date);

-- 2. Keep "who changed it / when" current when an existing entry is edited.
create or replace function public.coach_attendance_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists coach_attendance_touch on public.coach_attendance;
create trigger coach_attendance_touch
  before update on public.coach_attendance
  for each row execute function public.coach_attendance_touch();

-- 3. Row Level Security — explicit policies for all four actions (see CLAUDE.md "Known gotchas").
--    Super admins: every location. Location admins: only locations in their admin_location_access.
--    Future dates are refused (dates are compared in UAE time, so "today" matches the app).
alter table public.coach_attendance enable row level security;

drop policy if exists "coach_attendance select" on public.coach_attendance;
create policy "coach_attendance select" on public.coach_attendance
  for select using (public.is_super_admin() or public.has_location_access(location_id));

drop policy if exists "coach_attendance insert" on public.coach_attendance;
create policy "coach_attendance insert" on public.coach_attendance
  for insert with check (
    (public.is_super_admin() or public.has_location_access(location_id))
    and date <= (now() at time zone 'Asia/Dubai')::date
  );

drop policy if exists "coach_attendance update" on public.coach_attendance;
create policy "coach_attendance update" on public.coach_attendance
  for update
  using (public.is_super_admin() or public.has_location_access(location_id))
  with check (
    (public.is_super_admin() or public.has_location_access(location_id))
    and date <= (now() at time zone 'Asia/Dubai')::date
  );

drop policy if exists "coach_attendance delete" on public.coach_attendance;
create policy "coach_attendance delete" on public.coach_attendance
  for delete using (public.is_super_admin() or public.has_location_access(location_id));

-- 4. Quick check — should list the four policies above.
select policyname, cmd from pg_policies where tablename = 'coach_attendance' order by cmd;
