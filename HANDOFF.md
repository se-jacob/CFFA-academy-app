# CFFA Academy Admin — Project Handoff

Paste this whole document into a new chat to resume work with full context.

## 1. What this is

A React/Vite + Supabase admin panel for a sports academy (brand: CFFA, domain: sportsplayuae.com). It manages locations, players, coaches, batches, payment plans, attendance, fees, training schedules, and admin access, with role-based scoping (super_admin sees everything, location_admin sees only their assigned location(s)).

It started as a static prototype (`sports-academy-manager.jsx`, in-memory data only) and was converted end-to-end to a real Supabase-backed app, following a phased plan (`phase-4-connect-supabase-detailed.md`) and a schema doc (`database-schema-final.md`) — both of which live one level up from the app folder, not inside the repo itself.

## 2. Tech stack

- **Frontend**: React 19 + Vite 8, single file `src/App.jsx` (~3400 lines)
- **Backend**: Supabase — Postgres, Auth, Edge Functions, Row Level Security (RLS) does all access control; the frontend never filters by role/location for security purposes
- **Charts**: recharts · **Icons**: lucide-react
- **Excel export**: `xlsx`, installed from SheetJS's own CDN (`cdn.sheetjs.com`), not npm — the npm-published version has unresolved prototype-pollution/ReDoS advisories that only SheetJS's own distribution channel has patched
- **PWA**: `vite-plugin-pwa` — installable, icons generated from the embedded logo padded onto a navy square background
- **Hosting**: Vercel (GitHub-connected, auto-deploy on push)
- **Repo**: `https://github.com/se-jacob/cffa-academy-app`
- **Domain**: `sportsplayuae.com`
- **Supabase project ref**: `wfazohsqujucihzknhgz`

## 3. Architecture

`src/App.jsx` is organized into banner-delimited sections in this order: Constants → Utilities → Supabase data loading → Domain helpers → Shared UI → Shell (Sidebar/Topbar) → one section per page (Dashboard, Locations, Payment Plans, Batches, Students, Attendance, Coaches, Training Schedules, Fee Update, Reports, Manage Admins) → Login/PasswordSetup → App Root → Styles (one big CSS template-literal string rendered via `<style>{STYLES}</style>`).

**Data flow.** `loadAllData()` fetches every operational table in parallel once and maps snake_case DB columns to camelCase. The App root owns the single `data` object plus a `refetchData()` callback passed to every page. There's no local reducer/optimistic-update pattern — every write handler calls Supabase directly, then `refetchData()` to reload fresh state. Write errors surface inline via a local `saveError` state rather than failing silently.

**Auth.** `admin_profiles` and `admin_location_access` are fetched as two separate queries (no FK between them — both independently reference `auth.users`, so PostgREST can't embed one in the other). The App root detects Supabase invite/recovery links via `window.location.hash` containing `type=invite`/`type=recovery` and routes to a `PasswordSetupPage` before showing the normal app shell; on completion it flips that admin's `status` from `Invited` to `Active`.

**Inviting new admins** requires the service role key (creating an `auth.users` row), so it's the one write path that goes through a Supabase Edge Function (`supabase/functions/invite-admin/index.ts`) instead of the frontend directly: it verifies the caller is `super_admin` using an anon-key client scoped to the caller's own JWT, then switches to a service-role client for the actual invite + profile/access inserts. Editing an existing admin's role/locations, or revoking access (soft-delete via `status = 'Revoked'`, not a hard delete), happens directly from the frontend since those don't need the service role key. The Edge Function passes `redirectTo: "https://sportsplayuae.com"` explicitly to `inviteUserByEmail`, since the Supabase project's global "Site URL" setting couldn't be changed directly (only "Redirect URLs" was editable) — the explicit `redirectTo` overrides Site URL for that call as long as it's in the Redirect URLs allow list.

**Responsive layout.** Below 900px, the sidebar becomes a `position: fixed` slide-out drawer (`transform: translateX(...)` + CSS transition) toggled by a hamburger button, with a click-to-close backdrop; above 900px it's the normal in-flow sidebar with its own collapse/expand toggle. Pure CSS inside one `@media (max-width: 900px)` block plus a `mobileNavOpen` state in the App root.

## 4. Database schema

Tables (Postgres, via Supabase), RLS enabled on all:

- **locations**: id, name, address, contact, admin_name, admin_user_id
- **payment_plans**: id, location_id, name, gender, duration, sessions_count, amount
- **batches**: id, location_id, batch_code, name
- **coaches**: id, name, phone, email, specialty
- **coach_locations** (join): coach_id, location_id
- **students**: id, name, phone, email, dob, batch_id, location_id, jersey_name, jersey_no, sessions_per_week, payment_plan_id, override_fee, status, remark, **attendance_days** (`integer[]`, added mid-project — see §6)
- **sessions**: id, location_id, batch_id, date, start_time, end_time
- **session_coaches** (join): session_id, coach_id
- **attendance**: id, session_id, student_id, status — unique on (session_id, student_id) for upsert
- **payments**: id, student_id, date, receipt_no, amount, next_payment_date, comment
- **admin_profiles**: id (FK → auth.users), name, role (`super_admin`|`location_admin`), status (`Active`|`Invited`|`Revoked`)
- **admin_location_access** (join): user_id, location_id

RLS uses two security-definer helper functions (`is_super_admin()`, `has_location_access(location_id)`) referenced across policies.

**RLS gaps found and fixed during this build** (worth knowing if adding new tables — don't assume "reads fine" means writes will work; RLS-without-a-policy returns zero rows silently on SELECT but throws `42501` on write):
- `coaches`, `coach_locations`, `session_coaches` originally had **no policies at all**.
- `attendance`, `payments` originally had **only a SELECT policy** (insert/update/delete were missing).
- `admin_profiles`, `admin_location_access` only had a "super admin manages everything" policy — added a "user reads their own row" SELECT policy on each, otherwise a `location_admin` can authenticate but can't read their own profile on login.

All four are now fully patched with explicit select/insert/update/delete policies following the `has_location_access(...)` pattern.

## 5. Business rules

- **Fee status** (Paid/Due/Overdue) is derived from the student's latest payment's `next_payment_date` vs today — no separate "status" column on payments.
- **Attendance Days**: admin checks which days of the week (Mon–Sun) a player is expected to attend on the Add/Edit Player form; **Sessions/Week auto-derives from the count of checked days** and is no longer manually editable. Stored as `attendance_days` (`integer[]`), using JS `Date.getDay()` convention (0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat) — same convention used for recurring session bulk-create.
- **Bulk session creation** dedups by `(location, date, batch, start_time)` so re-running it for an overlapping range doesn't create duplicate sessions — but a *different* batch/coach at the same time slot is allowed (parallel batches).
- **Location scoping** is enforced entirely by RLS — `super_admin` sees all locations; `location_admin` sees only what's in their `admin_location_access` rows. The frontend's location dropdown is a UX filter only, not a security boundary.
- **Revoking an admin** sets `status = 'Revoked'` (soft delete) rather than deleting the row, matching the schema's own status field design.

## 6. Environment / secrets

`.env.local` (gitignored, not in the repo):
```
VITE_SUPABASE_URL=https://wfazohsqujucihzknhgz.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_iGka5Il3oZRfxrDdAbZpsQ_1Ch1Wo5W
```
The anon/publishable key is safe for frontend use by design. The **service role key is never in frontend code or committed anywhere** — it only exists as an auto-injected secret inside the `invite-admin` Edge Function's runtime.

Same two variables need to be set in Vercel's project environment variables (Production/Preview/Development — all three point at the same single Supabase project since there's no separate staging backend).

## 7. Deployment status (as of handoff)

- ✅ Pushed to GitHub (`se-jacob/cffa-academy-app`)
- ✅ Vercel deployment walked through (framework: Vite, build: `npm run build`, output: `dist`), env vars set via .env import
- ✅ Custom domain `sportsplayuae.com` registered and being connected
- ⚠️ **Not yet confirmed**: whether the Vercel deployment is fully live and DNS has propagated for the custom domain — last step in progress when this handoff was written
- Supabase Auth **Site URL** could not be changed directly in the dashboard (reason unclear — possibly a permissions/UI quirk); worked around via explicit `redirectTo` in the Edge Function instead. **Redirect URLs** list was editable and updated to include `https://sportsplayuae.com/**`.

## 8. Known issues / open items

- **Manage Admins page doesn't show admin email addresses** — `auth.users` isn't queryable via the anon key, so this needs another service-role-backed lookup (similar pattern to `invite-admin`) to fetch and display emails. Not built yet.
- **Real mobile/tablet device testing not done** — only verified via browser responsive-mode/automated viewport checks, not an actual phone/tablet. Recommended before calling mobile support "done."
- **Leftover test data in the real database** from verification testing this session:
  - A payment with receipt no. `RC-VERIFY-1` for Liam Carter (AED 75) — no delete-payment UI exists, needs manual SQL removal if unwanted: `delete from payments where receipt_no = 'RC-VERIFY-1';`
  - Aarav Mehta marked "Present" for a test date during Attendance testing — no unmark control in the UI.
  - A player literally named "Should Not Exist" was spotted early on (flagged to the user, may or may not still be in the DB).
- **JS bundle is a single ~1.2–1.3MB chunk**, not code-split. Not urgent, but `npm run build` will keep warning about it.
- `npm audit` currently reports **0 vulnerabilities** (both the `xlsx` and `brace-expansion` advisories were resolved — see §2 and the `overrides` entry in `package.json`).

## 9. Assumptions made

- One Supabase project serves all Vercel environments (Production/Preview/Development) — acceptable while testing solo, but means Preview deployments touch real production data. Revisit if this becomes a live multi-user app.
- Day-of-week numbering is consistently JS `Date.getDay()` (0=Sun...6=Sat) across attendance_days, bulk session recurrence, and anywhere else days-of-week appear.
- No test suite exists in this project — none was requested or built.

## 10. Suggested next steps

1. Confirm the Vercel deployment is live and `sportsplayuae.com` shows a valid DNS/SSL configuration in Vercel's Domains settings.
2. Send a fresh Invite Admin test end-to-end on the real domain (not localhost) to confirm the `redirectTo` fix works in production.
3. Thoroughly test `location_admin` login/scoping (partially verified earlier with a test account named "Mohith" scoped to one location) across every page, not just Dashboard/Schedules.
4. Decide whether to build email display for Manage Admins (needs a small Edge Function addition).
5. Clean up the leftover test data listed in §8 if desired.
6. Do a real-device mobile/tablet pass before considering that feature fully done.
