# Schema changes: v2 → v3

The schema is the migration `supabase/migrations/20261031000000_initial_schema.sql`; the
Supabase GitHub integration applies it on merge to `main`. Run the tests with `db/test/run.sh`
(needs the Postgres 16 server binaries). It loads the migrations into a throwaway database with Supabase stand-ins and runs 98 checks.

## Security
- RLS is enabled on every table. A test fails if any table in `public` is missing it.
- Users can't grant themselves roles, approve their own applications or assign themselves as coach.
- `gender` can only be changed by an admin (`admin_set_gender`). The other profile columns stay editable by the user.
- Earnings and coach-load views run with the caller's permissions (`security_invoker`).
- Chat is text only (no attachments). You can only send as yourself, only the recipient can mark a message read, and nobody can edit or delete messages. Conversations are created when a coach is assigned.
- Access helpers moved to schema `private`, which the API doesn't expose. They read `auth.uid()` and no longer take a viewer parameter.
- Storage policies for the `milestone-images` (female image rule), `certificates` and `avatars` buckets.
- Coach permissions follow the active assignment and its scope, not who created the plan, so a replacement coach can edit the plan they inherit.
- Trainees must be approved before they can log workouts or meals. An admin can only approve a trainee after assigning at least one coach.

## Correctness
- "Today" is the user's local date (`profiles.timezone`) everywhere. The `current_date` CHECK constraints were removed.
- Profiles are created by a trigger on `auth.users` from the sign-up metadata. Gender is required.
- Added write paths for milestones, milestone values, and marking notifications read.
- `daily_status` and `trainee_cycle_state` were removed. Both are now calculated from the logs by `daily_status()` and `next_workout_day()`, so there is no stored copy to keep in sync.
- Plan versions:
  - one active plan per trainee
  - `version_no` is set automatically
  - a version is frozen once anything is logged against it; `copy_*_version` creates the next one
  - plans have `archived_on` (a date) instead of an `is_archived` flag
- Integrity:
  - a set belongs to its session's workout day
  - a meal option belongs to its meal
  - a session or meal log belongs to the trainee's own plan
  - day numbers fit inside the cycle length
  - coach assignments can't overlap (exclusion constraint)
  - a value matches its milestone field's type
- Foods used in a plan keep their nutrient values (only an admin can correct them).
- Account deletion: `delete_my_account()`, with consistent `on delete` rules. Subscriptions are kept with the trainee or coach set to null.
- `updated_at` is maintained by triggers (needed for PowerSync's latest-change-wins).
- Earnings: `coach_earnings(from, to)` splits each subscription into equal monthly shares (see B4).
- Indexes added for foreign keys, unread counts and the progress chart (`set_logs(trainee_id, exercise_id, session_date)`).
- System notifications store no text. The app renders `type_key + data` in the reader's language.

## Product decisions applied
| | Decision |
|---|---|
| B1 | Full flexibility. Any day of the plan can be logged on any date, and resting is always allowed. `next_workout_day()` only suggests. Resting on a training day pushes that day to tomorrow. A planned rest day is used up by any day without a workout, and training on it just skips it. |
| B2 | Meals marked `counts_for_streak = false` (snacks) aren't needed for the streak. With no nutrition plan, a training day counts and a rest day is neutral. |
| B3 | Going more than 14 rest days in a row resets the streak to 0, and it restarts on the next training day. Any day with streak meals not all done is a missed day; the first is forgiven and the second resets the streak. |
| B4 | Equal shares per month. A subscription is split into one share per subscription month, counted from the start date, and each share is earned on the day its month starts. 2,500 EGP from 1 Nov to 31 Jan gives 833.33 in Nov, 833.33 in Dec and 833.34 in Jan; the last share takes the rounding remainder. |
| B9 | One workout per day (kept). |
| B11 | At most one active coach per scope (kept). |
| B12 | Chat stays open after an assignment ends (kept). |
| B13 | The female image rule covers milestone images only; profile pictures are fine. Chat has no attachments at all, so `messages.image_path` and the `chat-images` bucket were removed. **Spec update:** the spec's chat section says "text and images". |
| B7 | One reminder per meal (`meal_slot`). Until the user sets one: the meal's `time_hint`, then the sign-up meal time, then off. Workout, milestone and daily-data reminders default to 18:00, 09:00 and 21:00 (`reminder_defaults`). `my_reminders()` returns the list to schedule on the device. |
| B8 | `exercises.tracking`: `weight_reps`, `reps`, `duration`, or `distance_duration`. Plans and set logs gained duration and distance. Cardio machines (treadmill, bike…) are exercises with `distance_duration`. |
| B10 | Coaches choose grams or a unit per item. Units are per food in `food_units` (1 loaf = 90 g), and grams is calculated. |
| B14 | Coaches can send custom notifications only to their own trainees. Admins can send to anyone. |
| B15 | No blocking. When the admin records a payment, the trainee gets a "payment received" notification (amount, dates, days). The `subscription_status` view shows days left. `notify_ending_subscriptions()` warns the trainee and all admins 7 days before the end, once, unless a later subscription exists. |
| B16 | `consents` table (terms, privacy, health data, by version) and `delete_my_account()`. |
| B17 | No Arabic exercise names, so matching stays English-only. Arabic food search is normalised (أ/إ/آ→ا, ة→ه, ى→ي, diacritics). |
| B18 | Coaches define repeating schedules and can add one-off milestones at any time, picking the fields and which are required. `generate_due_milestones()` creates due milestones hourly. Missed = due date passed and not submitted. Required fields are checked on submit. |
| B19 | `coach_dashboard()`: trainees sorted by missed days, then due milestones, then unread messages. Each row shows today's status, the streak and subscription days left. |

## Still open
- **Deployment:**
  - The migration enables pg_cron and creates the three private storage buckets itself.
  - The Edge Functions for push and file cleanup on account deletion are still to be written.
  - Check Arabic trigram search on the Supabase project's locale. The tests use `C.UTF-8`.
  - PowerSync sync rules must mirror the female image rule.
  - Offline uploads older than 7 days will be rejected; the app must handle that error.
