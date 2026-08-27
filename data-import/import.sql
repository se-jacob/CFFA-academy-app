-- CFFA Academy — Mass Data Import
--
-- How to use:
-- 1. Fill in CFFA-Data-Upload-Worksheet.xlsx first.
-- 2. For each VALUES(...) block below, replace the example rows with your own data
--    from the matching worksheet sheet (same column order, left to right).
-- 3. Run this whole script once in the Supabase SQL editor, top to bottom —
--    the order matters (Locations must exist before Payment Plans/Batches/Coaches,
--    which must exist before Players).
-- 4. Re-running this script is safe to do for NEW rows, but running it twice with
--    the SAME rows will create duplicates (there's no dedup here) — remove rows
--    you've already imported before re-running.

-- ============================== 1. LOCATIONS ==============================
-- Columns: name, address, contact, admin_name, admin_user_id
-- admin_user_id: leave as NULL unless you already know the actual login account's
-- UUID to link — most of the time this stays NULL and admins get linked via
-- Manage Admins > Invite Admin in the app instead.

insert into locations (name, address, contact, admin_name, admin_user_id)
values
  ('Downtown Arena', '12 Sheikh Zayed Road, Dubai', '+971 50 111 2233', 'Farah Khan', null),
  ('Marina Sports Hub', 'Marina Walk, Dubai', '+971 50 444 5566', 'Imran Sheikh', null);
  -- add more rows above, comma-separated, following the same (…), (…) pattern

-- ============================== 2. PAYMENT PLANS ==============================
-- Columns: location_name, name, gender, duration, sessions_count, amount
-- sessions_count: use NULL for anything that isn't "Fixed Sessions"

insert into payment_plans (location_id, name, gender, duration, sessions_count, amount)
select l.id, v.name, v.gender, v.duration, v.sessions_count, v.amount
from (values
  ('Downtown Arena', 'Monthly - Any', 'Any', 'Monthly', null::int, 450),
  ('Downtown Arena', 'Quarterly - Any', 'Any', 'Quarterly', null::int, 1200),
  ('Marina Sports Hub', '10 Session Pack', 'Any', 'Fixed Sessions', 10, 800)
) as v(location_name, name, gender, duration, sessions_count, amount)
join locations l on l.name = v.location_name;

-- ============================== 3. BATCHES ==============================
-- Columns: location_name, batch_code, name

insert into batches (location_id, batch_code, name)
select l.id, v.batch_code, v.name
from (values
  ('Downtown Arena', 'DA-U12', 'Under 12 Football'),
  ('Marina Sports Hub', 'MSH-SWM', 'Marina Swim Squad')
) as v(location_name, batch_code, name)
join locations l on l.name = v.location_name;

-- ============================== 4. COACHES ==============================
-- Columns: name, phone, email, specialty, location_names
-- location_names in the worksheet is semicolon-separated (e.g. "A;B") for coaches
-- working at multiple locations — this script inserts the coach once, then links
-- them to every location listed.

with new_coaches as (
  insert into coaches (name, phone, email, specialty)
  values
    ('Marcus Webb', '+971 55 222 1010', 'marcus.webb@academy.com', 'Football'),
    ('Daniel Osei', '+971 55 222 3030', 'daniel.osei@academy.com', 'Swimming')
  returning id, name
),
coach_location_map (coach_name, location_name) as (
  values
    ('Marcus Webb', 'Downtown Arena'),
    ('Daniel Osei', 'Marina Sports Hub')
    -- one row per (coach, location) pair — add a row here for each location a
    -- coach works at, e.g. if Marcus also works at Marina Sports Hub, add:
    -- ('Marcus Webb', 'Marina Sports Hub'),
)
insert into coach_locations (coach_id, location_id)
select nc.id, l.id
from coach_location_map m
join new_coaches nc on nc.name = m.coach_name
join locations l on l.name = m.location_name;

-- ============================== 5. PLAYERS ==============================
-- Columns: name, phone, email, dob, location_name, batch_name, jersey_name,
--          jersey_no, attendance_days, sessions_payment_plan_name, override_fee,
--          status, remark
--
-- attendance_days: comma-separated day names (Mon,Tue,Wed,Thu,Fri,Sat,Sun) —
-- this script converts them to the integer array the database expects
-- (0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat) and derives sessions_per_week
-- from however many days are listed, matching the app's own behavior.

insert into students (
  name, phone, email, dob, location_id, batch_id, jersey_name, jersey_no,
  attendance_days, sessions_per_week, payment_plan_id, override_fee, status, remark
)
select
  v.name, v.phone, v.email, v.dob::date, l.id, b.id, v.jersey_name, v.jersey_no,
  day_numbers, array_length(day_numbers, 1), pp.id,
  nullif(v.override_fee, '')::numeric, v.status, nullif(v.remark, '')
from (values
  ('Aarav Mehta', '+971 50 900 1111', 'aarav@example.com', '2013-04-12', 'Downtown Arena', 'Under 12 Football', 'AARAV', '7', 'Mon,Wed,Fri', 'Monthly - Any', '', 'Active', ''),
  ('Fatima Noor', '+971 50 900 4444', 'fatima@example.com', '2014-06-30', 'Marina Sports Hub', 'Marina Swim Squad', 'FATIMA', '21', 'Tue,Thu,Sat,Sun', '10 Session Pack', '', 'Active', '')
) as v(name, phone, email, dob, location_name, batch_name, jersey_name, jersey_no, attendance_days, payment_plan_name, override_fee, status, remark)
join locations l on l.name = v.location_name
left join batches b on b.name = v.batch_name and b.location_id = l.id
left join payment_plans pp on pp.name = v.payment_plan_name and pp.location_id = l.id
cross join lateral (
  select array_agg(
    case trim(day)
      when 'Sun' then 0 when 'Mon' then 1 when 'Tue' then 2 when 'Wed' then 3
      when 'Thu' then 4 when 'Fri' then 5 when 'Sat' then 6
    end
    order by case trim(day)
      when 'Sun' then 0 when 'Mon' then 1 when 'Tue' then 2 when 'Wed' then 3
      when 'Thu' then 4 when 'Fri' then 5 when 'Sat' then 6
    end
  ) as day_numbers
  from unnest(string_to_array(v.attendance_days, ',')) as day
) days;
