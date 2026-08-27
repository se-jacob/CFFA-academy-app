# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev       # start Vite dev server (http://localhost:5173)
npm run build     # production build to dist/ (also runs vite-plugin-pwa's service worker generation)
npm run preview   # serve the production build locally
npm run lint       # oxlint
```

There is no test suite in this project.

Edge Function (Supabase CLI, via `npx supabase` if not installed globally):
```bash
npx supabase login
npx supabase link --project-ref <project-ref>
npx supabase functions deploy invite-admin
```

## Environment

`.env.local` (gitignored) must define:
```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...   # the anon/publishable key — safe for frontend use
```
The service role key is never used in frontend code — it only exists as an auto-injected secret inside the `invite-admin` Edge Function (`supabase/functions/invite-admin/index.ts`).

## Architecture

This is a single-file React app (`src/App.jsx`, ~3400 lines) — a Supabase-backed admin panel for a sports academy (locations, players, coaches, attendance, fees, schedules). The file is organized into banner-delimited sections in this order: Constants → Utilities → Supabase data loading → Domain helpers → Shared UI → Shell (Sidebar/Topbar) → one section per page (Dashboard, Locations, Payment Plans, Batches, Students, Attendance, Coaches, Training Schedules, Fee Update, Reports, Manage Admins) → Login/PasswordSetup → App Root → Styles (a single template-literal CSS string rendered via `<style>{STYLES}</style>`).

**Data flow — no client-side role filtering, ever.** `loadAllData()` fetches every operational table (locations, payment_plans, batches, coaches, coach_locations, students, sessions, session_coaches, attendance, payments) in parallel and maps snake_case DB columns to the camelCase shape the components use. Row Level Security on the Supabase side already returns only the rows the logged-in admin (`super_admin` or `location_admin`) is allowed to see — the frontend never filters by role or location for security purposes. The only client-side filtering that exists is the location dropdown in the topbar, which is a UX convenience, not an access control.

The App root owns the single `data` object plus a `refetchData()` callback, both passed down to every page. There is no local reducer/optimistic-update pattern — every page's save/delete/update handler writes to Supabase directly, then calls `refetchData()` (or a page-local `refetch()` for Manage Admins, which loads `admin_profiles`/`admin_location_access` separately since those aren't part of the main data blob) to reload fresh state. Write handlers surface Postgres/RLS errors via a local `saveError` state shown inline, rather than failing silently.

**Auth.** Session and the logged-in admin's profile are separate pieces of state in the App root. `admin_profiles` and `admin_location_access` are fetched as two separate queries, not a single embedded `select` — there is no direct foreign key between them (both independently reference `auth.users`), so PostgREST can't join them in one call. `App` also detects Supabase invite/recovery links by checking `window.location.hash` for `type=invite`/`type=recovery` on mount, and routes to `PasswordSetupPage` before rendering the normal app shell.

**Manage Admins / inviting new admins.** Creating a brand-new admin (an `auth.users` row) requires the service role key and can only happen server-side, hence the `invite-admin` Edge Function: it verifies the caller is a `super_admin` using an anon-key client scoped to the caller's own JWT, then switches to a service-role client to call `inviteUserByEmail` and insert the `admin_profiles`/`admin_location_access` rows. Editing an existing admin's role/locations or revoking access (soft-delete via `status = 'Revoked'`) happens directly from the frontend since those don't need the service role key.

**Responsive layout.** Below 900px, the sidebar becomes a fixed-position slide-out drawer (`position: fixed` + `transform: translateX(...)` + a CSS transition) toggled by a hamburger button in the topbar, with a click-to-close backdrop. Above 900px it's the normal in-flow sidebar with its own collapse/expand toggle. Both behaviors are pure CSS inside the single `@media (max-width: 900px)` block in `STYLES` plus a `mobileNavOpen` state in the App root — there's no separate mobile component tree.

**PWA.** `vite-plugin-pwa` is configured in `vite.config.js` (manifest, icons, service worker). PWA behavior (install prompt, service worker registration) only activates in a production build/preview or a real deployment — it's intentionally disabled in `npm run dev`.

## Known gotchas

- **RLS policies must be defined for all four actions (select/insert/update/delete) per table, explicitly.** Several tables (`coaches`, `coach_locations`, `session_coaches`, `attendance`, `payments`) originally only had a `select` policy; `insert`/`update`/`delete` silently had none, which doesn't error on read (RLS-without-a-policy just returns zero rows) but throws `42501` on write. If a new table is added, all four policies need to be created explicitly — don't assume "it read fine" means writes will work.
- `admin_profiles` and `admin_location_access` need a "user reads their own row" `select` policy in addition to the "super admin manages everything" policy — otherwise a `location_admin` can authenticate but can't read their own profile/location access on login.
- Vite's dependency pre-bundle cache (`node_modules/.vite`) can go stale after installing or swapping a package, causing confusing runtime errors (e.g. two React copies, or an old package version loading despite `package.json` showing the new one). Clear it and restart the dev server when something doesn't add up after a dependency change.
- `xlsx` is installed from SheetJS's own CDN tarball (`https://cdn.sheetjs.com/...`), not the npm registry — the npm-published version has unresolved prototype-pollution/ReDoS advisories that SheetJS only patches via their own distribution channel.
