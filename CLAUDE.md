# My Workout Pal

Fitness coaching app: Flutter app in `app/`, Supabase backend in `supabase/`
(schema as migrations; tests in `db/test/`). Product decisions are in
`db/CHANGES.md`; how to run the app is in `app/README.md`.

## UX rules (from the product owner, apply to every screen)

The app must feel simple and comfortable. Before finishing any screen, check:

- **There is always a way back.** Every screen that isn't a home screen has a
  back arrow, and it goes where the user expects (the previous step, not an
  unrelated screen). Never strand a user: if back can't apply (e.g. signed-in
  onboarding), offer a clear exit such as sign out.
- **Related screens link to each other.** Log in ↔ sign up, sign up → log in,
  "check your email" → log in, with back still working after following a link.
- **One primary action per screen, always in the same place**: a full-width
  button in a bar pinned to the bottom (`BottomActionBar`). Secondary actions
  are text buttons. Back/previous sits before Next, which mirrors correctly in
  Arabic (right-to-left).
- **Don't make it complicated.** Fewest fields and taps possible; don't show
  options the user doesn't need yet; a dead end or a flow that can't be
  completed (e.g. a link that doesn't open the app) is a bug.
- **Forms**: the keyboard's next/done moves between fields and submits; the
  right keyboard type for each field; password fields have a show/hide toggle;
  errors say what to do, next to the field.
- **Arabic first**: check every screen in Arabic (RTL) and English.

## Supabase notes

- Schema changes are new files in `supabase/migrations/` (never edit an
  applied one); the GitHub integration applies them on merge to `main`.
- New tables need explicit grants to `authenticated` (this project doesn't
  grant by default); RLS still filters rows. `db/test` runs with the same
  defaults, so a missing grant fails the tests.
- Edge Functions live in `supabase/functions/` and are deployed with the
  Supabase connector or CLI; `send-push` needs the `FCM_SERVICE_ACCOUNT`
  secret.

## Checks before pushing

- `cd app && flutter analyze && flutter test`
- `db/test/run.sh` when the schema changes
- CI builds an installable APK for every PR that touches `app/`
