-- =====================================================================
-- Fitness Coaching App — Postgres schema (Supabase)
-- Version 3 · 2026-10-31
--
-- Conventions
--   * Every user is a row in auth.users (Supabase Auth) + public.profiles.
--     The profile is created by a trigger from the sign-up metadata.
--   * Roles, scopes, sign-up questions, milestone fields and notification
--     types are DATA (lookup tables), not code — add new ones with INSERTs.
--   * Plans are versioned; logs point at the version they were made under.
--     A version is frozen once anything is logged against it: edits go
--     into a new version (copy_workout_version / copy_nutrition_version).
--   * A plan with trainee_id IS NULL is a template.
--   * Weights in kg, energy in kcal, food values per 100 g,
--     durations in seconds, distances in metres.
--   * "Today" is always the user's local day (profiles.timezone), never UTC.
--   * RLS is on for EVERY table. Access helpers live in schema "private",
--     which the API does not expose. Callable RPCs live in "public".
--   * PowerSync sync rules do not apply RLS: every rule below that limits
--     reads (especially the female image rule) must be mirrored there.
-- =====================================================================

create extension if not exists pg_trgm;
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create schema if not exists private;

-- ---------------------------------------------------------------------
-- Enums: only for values the code logic genuinely depends on
-- ---------------------------------------------------------------------
create type gender_t            as enum ('male', 'female');
create type application_status  as enum ('pending', 'approved', 'rejected');
create type answer_type_t       as enum ('text', 'number', 'boolean', 'date', 'single_choice', 'multi_choice', 'time_list');
create type food_source_t       as enum ('usda', 'open_food_facts', 'custom');
create type field_kind_t        as enum ('number', 'image');
create type platform_t          as enum ('ios', 'android');
-- How an exercise is logged: weight x reps, reps only (bodyweight),
-- time only (plank, rope), or distance + time (treadmill, bike, rowing).
create type tracking_t          as enum ('weight_reps', 'reps', 'duration', 'distance_duration');
create type reminder_kind_t     as enum ('workout', 'meal', 'milestone', 'daily_data');

-- Arabic search normalisation: strip diacritics/tatweel, unify alef/ya/ta marbuta.
create or replace function private.normalize_ar(p text)
returns text language sql immutable parallel safe as $$
  select lower(translate(regexp_replace(coalesce(p, ''), '[ً-ْـ]', '', 'g'),
                         'أإآٱىة', 'اااايه'));
$$;

-- =====================================================================
-- 1. IDENTITY & ROLES
-- =====================================================================
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text not null,
  gender          gender_t not null,             -- only an admin can change it (see grants)
  date_of_birth   date,
  height_cm       numeric(5,1),
  phone           text,
  avatar_path     text,
  locale          text not null default 'ar' check (locale in ('ar', 'en')),
  timezone        text not null default 'Africa/Cairo',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table roles (
  id          smallserial primary key,
  key         text not null unique,          -- 'trainee', 'coach', 'admin', ...
  name_en     text not null,
  name_ar     text not null,
  created_at  timestamptz not null default now()
);

insert into roles (key, name_en, name_ar) values
  ('trainee', 'Trainee', 'متدرب'),
  ('coach',   'Coach',   'مدرب'),
  ('admin',   'Admin',   'مسؤول');

-- A user may hold many roles (e.g. admin + coach). Granted on approval.
create table user_roles (
  user_id     uuid not null references profiles(id) on delete cascade,
  role_id     smallint not null references roles(id),
  granted_by  uuid references profiles(id) on delete set null,
  granted_at  timestamptz not null default now(),
  primary key (user_id, role_id)
);

-- Every sign-up (trainee or coach) is an application. Reapplying = new row.
create table applications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  role_id      smallint not null references roles(id),
  status       application_status not null default 'pending',
  submitted_at timestamptz not null default now(),
  reviewed_by  uuid references profiles(id) on delete set null,
  reviewed_at  timestamptz,
  check (reviewed_by is null or reviewed_by <> user_id)
);
create unique index one_pending_application
  on applications (user_id, role_id) where status = 'pending';
create index on applications (status, submitted_at);

create table coach_certificates (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references profiles(id) on delete cascade,
  title       text not null,
  issuer      text,
  issued_on   date,
  file_path   text not null,                 -- storage: certificates/<coach_id>/...
  uploaded_at timestamptz not null default now()
);
create index on coach_certificates (coach_id);

-- Terms, privacy and health-data consent. A new version of a document
-- needs a new acceptance.
create table consents (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        text not null check (kind in ('terms', 'privacy', 'health_data')),
  version     text not null,
  accepted_at timestamptz not null default now(),
  unique (user_id, kind, version)
);

-- =====================================================================
-- 2. DYNAMIC SIGN-UP QUESTIONS
-- =====================================================================
-- Each section is one step of the sign-up form.
create table question_sections (
  id          smallserial primary key,
  key         text not null unique,
  title_en    text not null,
  title_ar    text not null,
  sort_order  int not null default 0
);

create table questions (
  id          uuid primary key default gen_random_uuid(),
  role_id     smallint not null references roles(id),   -- which sign-up form
  section_id  smallint references question_sections(id),
  key         text not null,
  text_en     text not null,
  text_ar     text not null,
  answer_type answer_type_t not null,
  hint_en     text,
  hint_ar     text,
  min_value   numeric,                       -- for number answers
  max_value   numeric,
  is_required boolean not null default false,
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  unique (role_id, key)
);

create table question_options (
  id          uuid primary key default gen_random_uuid(),
  question_id uuid not null references questions(id) on delete cascade,
  value       text not null,
  label_en    text not null,
  label_ar    text not null,
  sort_order  int not null default 0,
  unique (question_id, value)
);

create table answers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  question_id uuid not null references questions(id),
  value       jsonb not null,                -- "abc" | 72.5 | true | ["a","b"] | ["09:00","14:00"]
  answered_at timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, question_id)
);
create index on answers (question_id);

-- =====================================================================
-- 3. COACH ASSIGNMENTS (scoped, historical)
-- =====================================================================
create table coaching_scopes (
  id       smallserial primary key,
  key      text not null unique,             -- 'workout', 'nutrition'
  name_en  text not null,
  name_ar  text not null
);
insert into coaching_scopes (key, name_en, name_ar) values
  ('workout',   'Workout',   'التمارين'),
  ('nutrition', 'Nutrition', 'التغذية');

create table coach_assignments (
  id             uuid primary key default gen_random_uuid(),
  coach_id       uuid not null references profiles(id) on delete cascade,
  trainee_id     uuid not null references profiles(id) on delete cascade,
  scope_id       smallint not null references coaching_scopes(id),
  starts_on      date not null default current_date,
  ends_on        date,                       -- null = open-ended; inclusive
  assigned_by    uuid references profiles(id) on delete set null default auth.uid(),
  created_at     timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on),
  -- one coach per scope at any moment, past periods included
  exclude using gist (trainee_id with =, scope_id with =,
                      daterange(starts_on, ends_on, '[]') with &&)
);
create index on coach_assignments (coach_id);

-- =====================================================================
-- 4. EXERCISE LIBRARY
-- =====================================================================
create table exercises (
  id               uuid primary key default gen_random_uuid(),
  name_en          text not null,
  name_ar          text,
  category         text,                     -- strength, cardio, stretching...
  tracking         tracking_t not null default 'weight_reps',
  primary_muscles  text[] not null default '{}',
  equipment        text,
  source           text not null default 'custom',  -- 'free-exercise-db' | 'custom'
  source_ref       text,
  created_by       uuid references profiles(id) on delete set null default auth.uid(),
  created_at       timestamptz not null default now()
);
create unique index exercises_name_unique on exercises (lower(name_en));
create index exercises_name_trgm on exercises using gin (name_en gin_trgm_ops);

-- Saved spellings: "Flat bench" -> Bench Press
create table exercise_aliases (
  id          uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references exercises(id) on delete cascade,
  alias       text not null,
  created_by  uuid references profiles(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);
create unique index exercise_alias_unique on exercise_aliases (lower(alias));
create index exercise_alias_trgm on exercise_aliases using gin (alias gin_trgm_ops);
create index on exercise_aliases (exercise_id);

-- Used by the Excel import: exact/alias match first, then similar names
-- (pg_trgm "%" operator, default threshold 0.3, uses the GIN indexes).
create or replace function match_exercise(p_name text, p_limit int default 3)
returns table (exercise_id uuid, name_en text, score real, exact boolean)
language sql stable as $$
  with q as (select regexp_replace(trim(p_name), '\s+', ' ', 'g') as name),
  candidates as (
    select e.id, e.name_en, similarity(e.name_en, q.name) as score,
           lower(e.name_en) = lower(q.name) as exact
    from exercises e, q
    where e.name_en % q.name or lower(e.name_en) = lower(q.name)
    union all
    select a.exercise_id, e.name_en, similarity(a.alias, q.name),
           lower(a.alias) = lower(q.name)
    from exercise_aliases a join exercises e on e.id = a.exercise_id, q
    where a.alias % q.name or lower(a.alias) = lower(q.name)
  )
  select id, name_en, max(score), bool_or(exact)
  from candidates
  group by id, name_en
  order by bool_or(exact) desc, max(score) desc
  limit p_limit;
$$;

-- =====================================================================
-- 5. WORKOUT PLANS (versioned, cycle-based)
-- =====================================================================
create table workout_plans (
  id              uuid primary key default gen_random_uuid(),
  owner_coach_id  uuid references profiles(id) on delete set null default auth.uid(),
  trainee_id      uuid references profiles(id) on delete cascade,   -- null = template
  name            text not null,
  copied_from_id  uuid references workout_plans(id) on delete set null,
  archived_on     date,                       -- null = active; plan stops applying on this day
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index one_active_workout_plan
  on workout_plans (trainee_id) where trainee_id is not null and archived_on is null;
create index on workout_plans (owner_coach_id) where trainee_id is null;

-- The version in force on a day is the one with the latest effective_from
-- on or before that day (version_no breaks ties).
create table workout_plan_versions (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references workout_plans(id) on delete cascade,
  version_no      int not null,                          -- set by trigger
  cycle_length    int not null check (cycle_length > 0), -- e.g. 7 (days incl. rest)
  effective_from  date not null default current_date,
  source_file     text,                                  -- uploaded Excel, if any
  created_by      uuid references profiles(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  unique (plan_id, version_no)
);
create index on workout_plan_versions (plan_id, effective_from desc, version_no desc);

-- Only training days are stored; missing day numbers in the cycle = planned rest.
create table workout_days (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references workout_plan_versions(id) on delete cascade,
  day_number  int not null check (day_number > 0),       -- <= cycle_length (trigger)
  name        text not null,               -- 'Push Day'
  unique (version_id, day_number)
);

create table workout_day_exercises (
  id                uuid primary key default gen_random_uuid(),
  day_id            uuid not null references workout_days(id) on delete cascade,
  exercise_id       uuid not null references exercises(id),
  sort_order        int not null,
  sets              int not null check (sets > 0),
  reps_min          int check (reps_min > 0),
  reps_max          int,                      -- null = fixed reps
  duration_seconds  int check (duration_seconds > 0),     -- target for timed / cardio work
  distance_m        numeric(8,1) check (distance_m > 0),
  rest_seconds      int check (rest_seconds >= 0),
  tempo             text,
  superset_group    text,                     -- same letter = superset
  video_url_1       text,
  video_url_2       text,
  coach_notes       text,
  unique (id, exercise_id),                   -- target of set_logs composite FK
  check (reps_max is null or reps_max >= reps_min),
  check (reps_min is not null or duration_seconds is not null or distance_m is not null)
);
create index on workout_day_exercises (day_id, sort_order);

-- =====================================================================
-- 6. WORKOUT LOGS
-- =====================================================================
-- No session on a date = rest day. The trainee may log ANY day of their
-- plan on any date; next_workout_day() only suggests one.
create table workout_sessions (
  id               uuid primary key default gen_random_uuid(),
  trainee_id       uuid not null references profiles(id) on delete cascade,
  workout_day_id   uuid not null references workout_days(id),
  session_date     date not null,             -- local date; edit window enforced by RLS
  completed_at     timestamptz,
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (trainee_id, session_date)
);
create index on workout_sessions (workout_day_id);

create table set_logs (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references workout_sessions(id) on delete cascade,
  day_exercise_id   uuid not null,
  exercise_id       uuid not null references exercises(id),
  trainee_id        uuid not null references profiles(id) on delete cascade,  -- copied from session (trigger)
  session_date      date not null,                                            -- copied from session (trigger)
  set_number        int not null check (set_number > 0),
  reps              int check (reps >= 0),
  weight_kg         numeric(6,2) check (weight_kg >= 0),
  duration_seconds  int check (duration_seconds >= 0),
  distance_m        numeric(8,1) check (distance_m >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (session_id, day_exercise_id, set_number),
  foreign key (day_exercise_id, exercise_id) references workout_day_exercises (id, exercise_id),
  check (reps is not null or duration_seconds is not null or distance_m is not null)
);
create index set_logs_progress on set_logs (trainee_id, exercise_id, session_date);
create index on set_logs (day_exercise_id);

-- Last values per set for pre-filling: the latest time this trainee did
-- this exercise (one plan slot only, so a repeated exercise isn't merged).
create or replace function last_weights(p_trainee uuid, p_exercise uuid)
returns table (set_number int, reps int, weight_kg numeric, duration_seconds int, distance_m numeric)
language sql stable as $$
  with last as (
    select session_id, day_exercise_id from set_logs
    where trainee_id = p_trainee and exercise_id = p_exercise
    order by session_date desc, created_at desc
    limit 1)
  select sl.set_number, sl.reps, sl.weight_kg, sl.duration_seconds, sl.distance_m
  from set_logs sl join last using (session_id, day_exercise_id)
  order by sl.set_number;
$$;

-- =====================================================================
-- 7. FOODS
-- =====================================================================
create table foods (
  id              uuid primary key default gen_random_uuid(),
  name_en         text not null,
  name_ar         text,
  name_search     text generated always as (private.normalize_ar(name_en || ' ' || coalesce(name_ar, ''))) stored,
  source          food_source_t not null,
  source_ref      text,                      -- USDA fdcId / OFF barcode
  barcode         text,
  kcal            numeric(7,2) not null,     -- all per 100 g
  protein_g       numeric(6,2) not null default 0,
  carbs_g         numeric(6,2) not null default 0,
  fat_g           numeric(6,2) not null default 0,
  fiber_g         numeric(6,2),
  state           text check (state in ('raw', 'cooked')),
  cooked_yield    numeric(4,3) check (cooked_yield > 0), -- cooked weight / raw weight; null = no toggle
  created_by      uuid references profiles(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (source, source_ref)
);
create index foods_search_trgm on foods using gin (name_search gin_trgm_ops);
create index on foods (barcode) where barcode is not null;

-- Countable units for a food: 1 loaf of baladi bread = 90 g, 1 egg = 50 g.
create table food_units (
  id          uuid primary key default gen_random_uuid(),
  food_id     uuid not null references foods(id) on delete cascade,
  name_en     text not null,                 -- 'loaf', 'piece', 'scoop'
  name_ar     text not null,                 -- 'رغيف', 'قطعة', 'سكوب'
  grams       numeric(7,1) not null check (grams > 0),
  created_by  uuid references profiles(id) on delete set null default auth.uid(),
  unique (food_id, name_en),
  unique (id, food_id)                       -- target of meal_option_items composite FK
);

create or replace function search_foods(p_query text, p_limit int default 20)
returns setof foods language sql stable as $$
  select * from foods
  where name_search % private.normalize_ar(p_query)
     or name_search like '%' || private.normalize_ar(p_query) || '%'
  order by similarity(name_search, private.normalize_ar(p_query)) desc
  limit p_limit;
$$;

-- =====================================================================
-- 8. NUTRITION PLANS (versioned, meals -> options -> items)
-- =====================================================================
create table nutrition_plans (
  id              uuid primary key default gen_random_uuid(),
  owner_coach_id  uuid references profiles(id) on delete set null default auth.uid(),
  trainee_id      uuid references profiles(id) on delete cascade,  -- null = template
  name            text not null,
  show_macros     boolean not null default true,
  copied_from_id  uuid references nutrition_plans(id) on delete set null,
  archived_on     date,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index one_active_nutrition_plan
  on nutrition_plans (trainee_id) where trainee_id is not null and archived_on is null;
create index on nutrition_plans (owner_coach_id) where trainee_id is null;

create table nutrition_plan_versions (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references nutrition_plans(id) on delete cascade,
  version_no      int not null,
  effective_from  date not null default current_date,
  created_by      uuid references profiles(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  unique (plan_id, version_no)
);
create index on nutrition_plan_versions (plan_id, effective_from desc, version_no desc);

create table meals (
  id                 uuid primary key default gen_random_uuid(),
  version_id         uuid not null references nutrition_plan_versions(id) on delete cascade,
  name               text not null,           -- 'Breakfast'
  time_hint          time,                    -- also the default reminder time
  sort_order         int not null,
  counts_for_streak  boolean not null default true,  -- false for optional snacks
  unique (version_id, sort_order)
);

create table meal_options (
  id          uuid primary key default gen_random_uuid(),
  meal_id     uuid not null references meals(id) on delete cascade,
  label       text not null,                 -- 'A', 'B', 'Chicken option'
  sort_order  int not null,
  unique (id, meal_id)                       -- target of meal_logs composite FK
);
create index on meal_options (meal_id);

-- Quantity is in grams (unit_id null) or in a food unit; grams is derived.
create table meal_option_items (
  id          uuid primary key default gen_random_uuid(),
  option_id   uuid not null references meal_options(id) on delete cascade,
  food_id     uuid not null references foods(id),
  quantity    numeric(7,2) not null check (quantity > 0),
  unit_id     uuid,
  grams       numeric(7,1) not null check (grams > 0),   -- set by trigger
  note        text,
  sort_order  int not null default 0,
  foreign key (unit_id, food_id) references food_units (id, food_id)
);
create index on meal_option_items (option_id);
create index on meal_option_items (food_id);

create table meal_logs (
  id            uuid primary key default gen_random_uuid(),
  trainee_id    uuid not null references profiles(id) on delete cascade,
  meal_id       uuid not null references meals(id),
  option_id     uuid,
  log_date      date not null,
  completed_at  timestamptz not null default now(),
  change_note   text,                        -- "Did you change anything in this meal?"
  updated_at    timestamptz not null default now(),
  unique (trainee_id, meal_id, log_date),
  foreign key (option_id, meal_id) references meal_options (id, meal_id)
);
create index on meal_logs (trainee_id, log_date);
create index on meal_logs (meal_id);

-- =====================================================================
-- 9. MILESTONES (data-driven fields; scheduled or added any time)
-- =====================================================================
create table milestone_fields (
  id          smallserial primary key,
  key         text not null unique,
  label_en    text not null,
  label_ar    text not null,
  kind        field_kind_t not null,
  sort_order  int not null default 0
);
insert into milestone_fields (key, label_en, label_ar, kind, sort_order) values
  ('weight',       'Weight (kg)',  'الوزن (كجم)',   'number', 1),
  ('photo_front',  'Front photo',  'صورة أمامية',   'image',  2),
  ('photo_side',   'Side photo',   'صورة جانبية',   'image',  3),
  ('photo_back',   'Back photo',   'صورة خلفية',    'image',  4),
  ('inbody',       'InBody photo', 'صورة InBody',   'image',  5);

-- Coach-defined repeating check-ins. generate_due_milestones() (pg_cron)
-- creates the milestone rows when they fall due.
create table milestone_schedules (
  id              uuid primary key default gen_random_uuid(),
  trainee_id      uuid not null references profiles(id) on delete cascade,
  name            text not null,             -- 'Daily weight', 'Bi-weekly check-in'
  every_n_days    int not null check (every_n_days > 0),
  starts_on       date not null default current_date,
  is_active       boolean not null default true,
  created_by      uuid references profiles(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now()
);
create index on milestone_schedules (trainee_id);

create table milestone_schedule_fields (
  schedule_id  uuid not null references milestone_schedules(id) on delete cascade,
  field_id     smallint not null references milestone_fields(id),
  is_required  boolean not null default true,
  primary key (schedule_id, field_id)
);

-- One check-in. schedule_id null = added by a coach (or the sign-up weight).
-- Missed = due_date has passed and submitted_at is null.
create table milestones (
  id            uuid primary key default gen_random_uuid(),
  trainee_id    uuid not null references profiles(id) on delete cascade,
  schedule_id   uuid references milestone_schedules(id) on delete set null,
  title         text,                        -- for one-off check-ins
  due_date      date not null,
  requested_by  uuid references profiles(id) on delete set null default auth.uid(),
  submitted_at  timestamptz,                 -- set by the trainee once all values are in
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (schedule_id, due_date)
);
create index on milestones (trainee_id, due_date desc);

-- Fields asked for in this milestone (copied from the schedule, or picked
-- by the coach for a one-off). Required ones are checked on submit.
create table milestone_request_fields (
  milestone_id  uuid not null references milestones(id) on delete cascade,
  field_id      smallint not null references milestone_fields(id),
  is_required   boolean not null default true,
  primary key (milestone_id, field_id)
);

create table milestone_values (
  id            uuid primary key default gen_random_uuid(),
  milestone_id  uuid not null references milestones(id) on delete cascade,
  field_id      smallint not null references milestone_fields(id),
  number_value  numeric(7,2),
  image_path    text,                        -- storage: milestone-images/<trainee_id>/...
  updated_at    timestamptz not null default now(),
  unique (milestone_id, field_id),
  check ((number_value is not null) <> (image_path is not null))
);

-- =====================================================================
-- 10. NOTES (always private to author)
-- =====================================================================
create table notes (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references profiles(id) on delete cascade,
  about_user_id uuid references profiles(id) on delete cascade,  -- null = general
  body          text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on notes (author_id, about_user_id);

-- =====================================================================
-- 11. CHAT (one conversation per coach–trainee pair, created on assignment)
-- =====================================================================
create table conversations (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references profiles(id) on delete cascade,
  trainee_id  uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (coach_id, trainee_id)
);
create index on conversations (trainee_id);

create table messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references conversations(id) on delete cascade,
  sender_id        uuid not null references profiles(id) on delete cascade,
  body             text not null check (length(trim(body)) > 0),   -- text only, no attachments
  created_at       timestamptz not null default now(),
  read_at          timestamptz
);
create index on messages (conversation_id, created_at desc);
create index messages_unread on messages (conversation_id) where read_at is null;

-- =====================================================================
-- 12. NOTIFICATIONS & REMINDERS
-- =====================================================================
create table notification_types (
  key          text primary key,
  name_en      text not null,
  name_ar      text not null,
  default_push boolean not null default true
);
insert into notification_types (key, name_en, name_ar) values
  ('application_result',    'Application result',  'نتيجة الطلب'),
  ('plan_ready',            'Plan ready',          'الخطة جاهزة'),
  ('reminder',              'Reminder',            'تذكير'),
  ('no_data_today',         'Nothing logged',      'لم يتم التسجيل'),
  ('milestone_due',         'Check-in due',        'موعد المتابعة'),
  ('milestone_uploaded',    'Milestone uploaded',  'تم رفع إنجاز'),
  ('trainee_assigned',      'New trainee',         'متدرب جديد'),
  ('chat_message',          'New message',         'رسالة جديدة'),
  ('subscription_recorded', 'Payment received',    'تم استلام الدفع'),
  ('subscription_ending',   'Subscription ending', 'الاشتراك قارب على الانتهاء'),
  ('custom',                'Message from coach',  'رسالة من المدرب');

-- System notifications store no text: the app renders type_key + data in
-- the reader's current language. Only 'custom' carries a title/body.
-- Pushes are sent by an Edge Function (database webhook on insert).
create table notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references profiles(id) on delete cascade,
  type_key      text not null references notification_types(key),
  title         text,
  body          text,
  data          jsonb not null default '{}',  -- render params + deep link
  sent_by       uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  check (type_key <> 'custom' or title is not null)
);
create index on notifications (recipient_id, created_at desc);
create index notifications_unread on notifications (recipient_id) where read_at is null;

create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  token       text not null unique,
  platform    platform_t not null,
  last_seen   timestamptz not null default now()
);
create index on device_tokens (user_id);

-- App-wide default reminder times, used until the user sets their own.
-- Meal defaults come from the meal's time_hint, else the sign-up answer.
create table reminder_defaults (
  kind     reminder_kind_t primary key,
  at_time  time not null
);
insert into reminder_defaults (kind, at_time) values
  ('workout', '18:00'), ('milestone', '09:00'), ('daily_data', '21:00');

-- The user's own reminder times. Meals have one row per meal; meal_slot is
-- the meal's position in the day (1 = first meal), so it survives new plan versions.
create table reminder_settings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        reminder_kind_t not null,
  meal_slot   int check (meal_slot > 0),
  at_time     time not null,
  weekdays    smallint[] not null default '{0,1,2,3,4,5,6}' check (weekdays <@ '{0,1,2,3,4,5,6}'),
  enabled     boolean not null default true,
  updated_at  timestamptz not null default now(),
  check ((kind = 'meal') = (meal_slot is not null))
);
create unique index reminder_settings_unique
  on reminder_settings (user_id, kind, coalesce(meal_slot, 0));

-- =====================================================================
-- 13. SUBSCRIPTIONS & COACH EARNINGS (tracking only, no payments, no blocking)
-- =====================================================================
-- Entered by the admin. All amounts in EGP. Each subscription is credited
-- in full to the coach the admin picks. Rows are kept when a user deletes
-- their account (trainee/coach set to null) so earnings history stays.
create table subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  trainee_id          uuid references profiles(id) on delete set null,
  coach_id            uuid references profiles(id) on delete set null,
  amount_egp          numeric(10,2) not null check (amount_egp >= 0),
  starts_on           date not null,
  ends_on             date not null,
  recorded_by         uuid references profiles(id) on delete set null default auth.uid(),
  note                text,
  ending_notified_at  timestamptz,           -- heads-up sent (reset when ends_on changes)
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (ends_on >= starts_on)
);
create index on subscriptions (coach_id, starts_on);
create index on subscriptions (trainee_id, ends_on);
create index on subscriptions (ends_on);

-- =====================================================================
-- 14. ACCESS HELPERS (schema private, used by RLS, triggers and RPCs)
-- =====================================================================
create or replace function private.local_today(p_user uuid default auth.uid())
returns date language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce((select timezone from profiles where id = p_user), 'Africa/Cairo'))::date;
$$;

create or replace function private.has_role(p_role text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles ur join roles r on r.id = ur.role_id
                 where ur.user_id = auth.uid() and r.key = p_role);
$$;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select private.has_role('admin');
$$;

-- Assignment active today. p_scope null = any scope. An active coach sees
-- the trainee's FULL history (rows logged before the assignment too).
create or replace function private.is_coach_of(p_trainee uuid, p_scope text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from coach_assignments ca join coaching_scopes s on s.id = ca.scope_id
    where ca.coach_id = auth.uid() and ca.trainee_id = p_trainee
      and (p_scope is null or s.key = p_scope)
      and private.local_today(p_trainee) between ca.starts_on and coalesce(ca.ends_on, 'infinity'::date));
$$;

create or replace function private.can_view_trainee(p_trainee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() = p_trainee or private.is_admin() or private.is_coach_of(p_trainee);
$$;

-- Female image rule: a female trainee's images are visible only to female viewers.
create or replace function private.can_view_trainee_images(p_trainee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select private.can_view_trainee(p_trainee)
     and (
       auth.uid() = p_trainee
       or (select gender from profiles where id = p_trainee) = 'male'
       or (select gender from profiles where id = auth.uid()) = 'female'
     );
$$;

create or replace function private.within_edit_window(p_trainee uuid, p_day date)
returns boolean language sql stable security definer set search_path = public as $$
  select p_day between private.local_today(p_trainee) - 7 and private.local_today(p_trainee);
$$;

-- Plan access. Read: anyone who can view the trainee (or the template owner).
-- Write: admin, the template's owner, or a coach assigned to the trainee
-- in the plan's scope — not whoever created the plan, so a replacement
-- coach can edit the plan they inherit.
create or replace function private.workout_plan_access(p_plan uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from workout_plans p where p.id = p_plan and (
         private.is_admin()
      or (p.trainee_id is null and p.owner_coach_id = auth.uid() and private.has_role('coach'))
      or (p.trainee_id is not null and private.is_coach_of(p.trainee_id, 'workout'))
      or (not p_write and p.trainee_id is not null and private.can_view_trainee(p.trainee_id))));
$$;

create or replace function private.workout_version_access(p_version uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select private.workout_plan_access((select plan_id from workout_plan_versions where id = p_version), p_write);
$$;

create or replace function private.workout_day_access(p_day uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select private.workout_version_access((select version_id from workout_days where id = p_day), p_write);
$$;

create or replace function private.nutrition_plan_access(p_plan uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from nutrition_plans p where p.id = p_plan and (
         private.is_admin()
      or (p.trainee_id is null and p.owner_coach_id = auth.uid() and private.has_role('coach'))
      or (p.trainee_id is not null and private.is_coach_of(p.trainee_id, 'nutrition'))
      or (not p_write and p.trainee_id is not null and private.can_view_trainee(p.trainee_id))));
$$;

create or replace function private.nutrition_version_access(p_version uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select private.nutrition_plan_access((select plan_id from nutrition_plan_versions where id = p_version), p_write);
$$;

create or replace function private.meal_access(p_meal uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select private.nutrition_version_access((select version_id from meals where id = p_meal), p_write);
$$;

create or replace function private.meal_option_access(p_option uuid, p_write boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select private.meal_access((select meal_id from meal_options where id = p_option), p_write);
$$;

-- Version in force for a trainee on a given day.
create or replace function private.workout_version_on(p_trainee uuid, p_day date)
returns uuid language sql stable security definer set search_path = public as $$
  select v.id from workout_plan_versions v join workout_plans p on p.id = v.plan_id
  where p.trainee_id = p_trainee and v.effective_from <= p_day
    and (p.archived_on is null or p_day < p.archived_on)
  order by v.effective_from desc, v.version_no desc
  limit 1;
$$;

create or replace function private.nutrition_version_on(p_trainee uuid, p_day date)
returns uuid language sql stable security definer set search_path = public as $$
  select v.id from nutrition_plan_versions v join nutrition_plans p on p.id = v.plan_id
  where p.trainee_id = p_trainee and v.effective_from <= p_day
    and (p.archived_on is null or p_day < p.archived_on)
  order by v.effective_from desc, v.version_no desc
  limit 1;
$$;

create or replace function private.try_uuid(p text)
returns uuid language plpgsql immutable as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

-- Insert a system notification (bypasses the coach/admin-only insert policy).
create or replace function private.notify(p_recipient uuid, p_type text, p_data jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into notifications (recipient_id, type_key, data) values (p_recipient, p_type, p_data);
$$;

-- =====================================================================
-- 15. TRIGGERS: integrity, versioning, notifications
-- =====================================================================
create or replace function private.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'answers', 'workout_plans', 'workout_sessions', 'set_logs',
                           'foods', 'nutrition_plans', 'meal_logs', 'milestones', 'milestone_values',
                           'notes', 'reminder_settings', 'subscriptions'] loop
    execute format('create trigger touch_updated_at before update on %I
                    for each row execute function private.touch_updated_at()', t);
  end loop;
end $$;

-- Profile row from sign-up metadata: full_name, gender, date_of_birth,
-- height_cm, phone, locale, timezone. Gender is required.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}');
begin
  insert into profiles (id, full_name, gender, date_of_birth, height_cm, phone, locale, timezone)
  values (new.id,
          coalesce(m->>'full_name', ''),
          (m->>'gender')::gender_t,
          (m->>'date_of_birth')::date,
          (m->>'height_cm')::numeric,
          m->>'phone',
          coalesce(m->>'locale', 'ar'),
          coalesce(m->>'timezone', 'Africa/Cairo'));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

create or replace function private.check_timezone()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'unknown timezone: %', new.timezone;
  end if;
  return new;
end $$;

create trigger check_timezone before insert or update of timezone on profiles
  for each row execute function private.check_timezone();

-- Approving: an admin, not the applicant; a trainee needs a coach first.
-- The role is granted and the applicant notified in the same step.
create or replace function private.on_application_review()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.user_id = auth.uid() then
    raise exception 'you cannot review your own application';
  end if;
  if new.status = 'approved'
     and (select key from roles where id = new.role_id) = 'trainee'
     and not exists (select 1 from coach_assignments
                     where trainee_id = new.user_id and (ends_on is null or ends_on >= current_date)) then
    raise exception 'assign at least one coach before approving a trainee';
  end if;
  new.reviewed_by := auth.uid();
  new.reviewed_at := now();
  if new.status = 'approved' then
    insert into user_roles (user_id, role_id, granted_by)
    values (new.user_id, new.role_id, auth.uid()) on conflict do nothing;
  end if;
  perform private.notify(new.user_id, 'application_result',
    jsonb_build_object('status', new.status, 'role', (select key from roles where id = new.role_id)));
  return new;
end $$;

create trigger on_application_review before update of status on applications
  for each row execute function private.on_application_review();

-- New assignment: open the chat and tell the coach.
create or replace function private.on_coach_assigned()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into conversations (coach_id, trainee_id) values (new.coach_id, new.trainee_id)
  on conflict do nothing;
  perform private.notify(new.coach_id, 'trainee_assigned',
    jsonb_build_object('trainee_id', new.trainee_id, 'scope_id', new.scope_id));
  return new;
end $$;

create trigger on_coach_assigned after insert on coach_assignments
  for each row execute function private.on_coach_assigned();

-- version_no = next number for the plan (serialised per plan).
create or replace function private.next_version_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext(tg_table_name || new.plan_id::text));
  execute format('select coalesce(max(version_no), 0) + 1 from %I where plan_id = $1', tg_table_name)
    into new.version_no using new.plan_id;
  return new;
end $$;

create trigger next_version_no before insert on workout_plan_versions
  for each row execute function private.next_version_no();
create trigger next_version_no before insert on nutrition_plan_versions
  for each row execute function private.next_version_no();

create or replace function private.on_plan_version()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_trainee uuid;
begin
  execute format('select trainee_id from %I where id = $1',
                 case tg_table_name when 'workout_plan_versions' then 'workout_plans' else 'nutrition_plans' end)
    into v_trainee using new.plan_id;
  if v_trainee is not null then
    perform private.notify(v_trainee, 'plan_ready', jsonb_build_object(
      'kind', case tg_table_name when 'workout_plan_versions' then 'workout' else 'nutrition' end,
      'plan_id', new.plan_id, 'version_id', new.id, 'effective_from', new.effective_from));
  end if;
  return new;
end $$;

create trigger plan_ready after insert on workout_plan_versions
  for each row execute function private.on_plan_version();
create trigger plan_ready after insert on nutrition_plan_versions
  for each row execute function private.on_plan_version();

-- Frozen versions: once anything is logged against a version, its content
-- can't change. Deletes cascading from a parent row (account deletion)
-- pass through; the parent's own checks and FKs cover those.
create or replace function private.workout_version_frozen(p_version uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from workout_sessions s join workout_days d on d.id = s.workout_day_id
                 where d.version_id = p_version);
$$;

create or replace function private.nutrition_version_frozen(p_version uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from meal_logs l join meals m on m.id = l.meal_id
                 where m.version_id = p_version);
$$;

create or replace function private.guard_frozen_version()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r record;
  v uuid[];
  frozen boolean;
begin
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;
  -- the versions touched: the row's own, and on update also the old one
  -- (moving a row out of a frozen version counts too)
  foreach r in array case tg_op when 'INSERT' then array[new] when 'DELETE' then array[old]
                                else array[new, old] end loop
    if tg_table_name in ('workout_plan_versions', 'nutrition_plan_versions') then
      v := v || r.id;
    elsif tg_table_name in ('workout_days', 'meals') then
      v := v || r.version_id;
    elsif tg_table_name = 'workout_day_exercises' then
      v := v || (select version_id from workout_days where id = r.day_id);
    elsif tg_table_name = 'meal_options' then
      v := v || (select version_id from meals where id = r.meal_id);
    else
      v := v || (select m.version_id from meal_options o join meals m on m.id = o.meal_id where o.id = r.option_id);
    end if;
  end loop;

  if tg_table_name in ('workout_plan_versions', 'workout_days', 'workout_day_exercises') then
    select bool_or(private.workout_version_frozen(x)) into frozen from unnest(v) x;
  else
    select bool_or(private.nutrition_version_frozen(x)) into frozen from unnest(v) x;
  end if;
  if frozen then
    raise exception 'this plan version already has logs; create a new version instead'
      using errcode = 'P0001', hint = 'copy_workout_version / copy_nutrition_version';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['workout_days', 'workout_day_exercises', 'meals', 'meal_options', 'meal_option_items'] loop
    execute format('create trigger guard_frozen before insert or update or delete on %I
                    for each row execute function private.guard_frozen_version()', t);
  end loop;
  foreach t in array array['workout_plan_versions', 'nutrition_plan_versions'] loop
    execute format('create trigger guard_frozen before update or delete on %I
                    for each row execute function private.guard_frozen_version()', t);
  end loop;
end $$;

-- Day numbers must fit inside the cycle.
create or replace function private.check_cycle_days()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'workout_days' then
    if new.day_number > (select cycle_length from workout_plan_versions where id = new.version_id) then
      raise exception 'day % is outside the cycle length', new.day_number;
    end if;
  elsif exists (select 1 from workout_days where version_id = new.id and day_number > new.cycle_length) then
    raise exception 'cycle_length % is shorter than an existing day', new.cycle_length;
  end if;
  return new;
end $$;

create trigger check_cycle_days before insert or update on workout_days
  for each row execute function private.check_cycle_days();
create trigger check_cycle_days before update of cycle_length on workout_plan_versions
  for each row execute function private.check_cycle_days();

-- A session must be for a day of the trainee's own plan.
create or replace function private.check_workout_session()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from workout_days d
                 join workout_plan_versions v on v.id = d.version_id
                 join workout_plans p on p.id = v.plan_id
                 where d.id = new.workout_day_id and p.trainee_id = new.trainee_id) then
    raise exception 'this workout day is not in the trainee''s plan';
  end if;
  if tg_op = 'UPDATE' and new.session_date <> old.session_date then
    update set_logs set session_date = new.session_date where session_id = new.id;
  end if;
  return new;
end $$;

create trigger check_workout_session before insert or update on workout_sessions
  for each row execute function private.check_workout_session();

-- Set logs: copy trainee/date from the session; the exercise must belong
-- to the session's workout day.
create or replace function private.fill_set_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select trainee_id, session_date, workout_day_id into s from workout_sessions where id = new.session_id;
  new.trainee_id := s.trainee_id;
  new.session_date := s.session_date;
  if not exists (select 1 from workout_day_exercises where id = new.day_exercise_id and day_id = s.workout_day_id) then
    raise exception 'this exercise is not part of the session''s workout day';
  end if;
  return new;
end $$;

create trigger fill_set_log before insert or update on set_logs
  for each row execute function private.fill_set_log();

-- A meal log must be for a meal of the trainee's own plan.
create or replace function private.check_meal_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from meals m
                 join nutrition_plan_versions v on v.id = m.version_id
                 join nutrition_plans p on p.id = v.plan_id
                 where m.id = new.meal_id and p.trainee_id = new.trainee_id) then
    raise exception 'this meal is not in the trainee''s plan';
  end if;
  return new;
end $$;

create trigger check_meal_log before insert or update on meal_logs
  for each row execute function private.check_meal_log();

-- grams = quantity (grams) or quantity x unit weight.
create or replace function private.fill_item_grams()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.grams := case when new.unit_id is null then new.quantity
                    else new.quantity * (select grams from food_units where id = new.unit_id) end;
  return new;
end $$;

create trigger fill_item_grams before insert or update on meal_option_items
  for each row execute function private.fill_item_grams();

-- Foods used in a plan keep their nutrient values (only an admin may
-- correct them); otherwise past plans would silently change.
create or replace function private.guard_food_values()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.kcal, new.protein_g, new.carbs_g, new.fat_g, new.fiber_g, new.cooked_yield)
       is distinct from (old.kcal, old.protein_g, old.carbs_g, old.fat_g, old.fiber_g, old.cooked_yield)
     and exists (select 1 from meal_option_items where food_id = new.id)
     and not private.is_admin() then
    raise exception 'this food is used in plans; create a new food instead of changing its values';
  end if;
  return new;
end $$;

create trigger guard_food_values before update on foods
  for each row execute function private.guard_food_values();

-- Value type must match the field kind.
create or replace function private.check_milestone_value()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select kind from milestone_fields where id = new.field_id) = 'number' then
    if new.number_value is null then raise exception 'this field needs a number'; end if;
  elsif new.image_path is null then
    raise exception 'this field needs an image';
  end if;
  return new;
end $$;

create trigger check_milestone_value before insert or update on milestone_values
  for each row execute function private.check_milestone_value();

-- Submitting: required fields must be filled; the trainee's coaches are told.
create or replace function private.on_milestone_submit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.submitted_at is null or old.submitted_at is not null then
    return new;
  end if;
  if exists (select 1 from milestone_request_fields f
             where f.milestone_id = new.id and f.is_required
               and not exists (select 1 from milestone_values v
                               where v.milestone_id = new.id and v.field_id = f.field_id)) then
    raise exception 'required milestone fields are missing';
  end if;
  perform private.notify(ca.coach_id, 'milestone_uploaded',
                         jsonb_build_object('milestone_id', new.id, 'trainee_id', new.trainee_id))
  from (select distinct coach_id from coach_assignments
        where trainee_id = new.trainee_id
          and private.local_today(new.trainee_id) between starts_on and coalesce(ends_on, 'infinity'::date)) ca;
  return new;
end $$;

create trigger on_milestone_submit before update of submitted_at on milestones
  for each row execute function private.on_milestone_submit();

-- Subscriptions: tell the trainee a payment was recorded; re-arm the
-- heads-up when the end date moves.
create or replace function private.on_subscription()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.trainee_id is not null then
      perform private.notify(new.trainee_id, 'subscription_recorded', jsonb_build_object(
        'subscription_id', new.id, 'amount_egp', new.amount_egp,
        'starts_on', new.starts_on, 'ends_on', new.ends_on,
        'days', new.ends_on - new.starts_on + 1));
    end if;
  elsif new.ends_on is distinct from old.ends_on then
    new.ending_notified_at := null;
  end if;
  return new;
end $$;

create trigger on_subscription_insert after insert on subscriptions
  for each row execute function private.on_subscription();
create trigger on_subscription_update before update of ends_on on subscriptions
  for each row execute function private.on_subscription();

-- =====================================================================
-- 16. SCHEDULED JOBS (pg_cron, hourly because users' local days differ)
-- =====================================================================
-- Creates the latest due milestone of every active schedule (no backfill
-- of older missed ones) and notifies the trainee.
create or replace function private.generate_due_milestones()
returns int language plpgsql security definer set search_path = public as $$
declare
  s record;
  due date;
  mid uuid;
  n int := 0;
begin
  for s in select ms.*, private.local_today(ms.trainee_id) as today
           from milestone_schedules ms where ms.is_active loop
    continue when s.today < s.starts_on;
    due := s.starts_on + ((s.today - s.starts_on) / s.every_n_days) * s.every_n_days;
    mid := null;
    insert into milestones (trainee_id, schedule_id, due_date, requested_by)
    values (s.trainee_id, s.id, due, s.created_by)
    on conflict (schedule_id, due_date) do nothing
    returning id into mid;
    if mid is not null then
      insert into milestone_request_fields (milestone_id, field_id, is_required)
      select mid, field_id, is_required from milestone_schedule_fields where schedule_id = s.id;
      perform private.notify(s.trainee_id, 'milestone_due', jsonb_build_object('milestone_id', mid));
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- Heads-up to the trainee and every admin when a subscription is about to
-- end and no later one has been recorded.
create or replace function private.notify_ending_subscriptions(p_days int default 7)
returns int language plpgsql security definer set search_path = public as $$
declare
  s record;
  n int := 0;
begin
  for s in select sub.*, sub.ends_on - private.local_today(sub.trainee_id) + 1 as days_left, p.full_name
           from subscriptions sub join profiles p on p.id = sub.trainee_id
           where sub.ending_notified_at is null
             and sub.ends_on - private.local_today(sub.trainee_id) between 0 and p_days
             and not exists (select 1 from subscriptions later
                             where later.trainee_id = sub.trainee_id and later.ends_on > sub.ends_on) loop
    perform private.notify(s.trainee_id, 'subscription_ending', jsonb_build_object(
      'subscription_id', s.id, 'ends_on', s.ends_on, 'days_left', s.days_left));
    perform private.notify(ur.user_id, 'subscription_ending', jsonb_build_object(
      'subscription_id', s.id, 'ends_on', s.ends_on, 'days_left', s.days_left,
      'trainee_id', s.trainee_id, 'trainee_name', s.full_name))
    from user_roles ur join roles r on r.id = ur.role_id where r.key = 'admin';
    update subscriptions set ending_notified_at = now() where id = s.id;
    n := n + 1;
  end loop;
  return n;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('generate-due-milestones', '7 * * * *', 'select private.generate_due_milestones()');
    perform cron.schedule('subscriptions-ending',    '13 * * * *', 'select private.notify_ending_subscriptions(7)');
  end if;
end $$;

-- =====================================================================
-- 17. RPCs (public, run as the caller so RLS applies)
-- =====================================================================
-- What to train today. The trainee can always log any other day of the
-- plan instead, or rest; this only suggests.
--   * The cycle moves on only when a workout is logged, so resting on a
--     training day shifts it to tomorrow.
--   * A planned rest day (missing day number) is used up by any calendar
--     day without a workout; training on it simply skips it.
create or replace function next_workout_day(p_trainee uuid default auth.uid())
returns table (version_id uuid, day_number int, workout_day_id uuid, day_name text,
               is_planned_rest boolean, logged_today boolean)
language plpgsql stable as $$
declare
  today date := private.local_today(p_trainee);
  v uuid;
  v_plan uuid;
  len int;
  last_n int;
  last_d date;
  idle int;
  consumed int := 0;
  n int;
  d record;
begin
  v := private.workout_version_on(p_trainee, today);
  if v is null or not private.can_view_trainee(p_trainee) then
    return;
  end if;
  select plan_id, cycle_length into v_plan, len from workout_plan_versions where id = v;

  return query
    select wd.version_id, wd.day_number, wd.id, wd.name, false, true
    from workout_sessions s join workout_days wd on wd.id = s.workout_day_id
    where s.trainee_id = p_trainee and s.session_date = today;
  if found then
    return;
  end if;

  select wd.day_number, s.session_date into last_n, last_d
  from workout_sessions s
  join workout_days wd on wd.id = s.workout_day_id
  join workout_plan_versions pv on pv.id = wd.version_id
  where s.trainee_id = p_trainee and pv.plan_id = v_plan and s.session_date < today
  order by s.session_date desc
  limit 1;

  if last_n is null then             -- nothing logged yet: start of the plan
    last_n := 0;
    select min(effective_from) - 1 into last_d from workout_plan_versions where plan_id = v_plan;
  end if;
  idle := greatest(today - last_d - 1, 0);
  n := last_n;

  for i in 1..len loop
    n := n % len + 1;
    select * into d from workout_days where workout_days.version_id = v and workout_days.day_number = n;
    if found then
      return query select v, n, d.id, d.name, false, false;
      return;
    elsif consumed < idle then
      consumed := consumed + 1;
    else
      return query select v, n, null::uuid, null::text, true, false;
      return;
    end if;
  end loop;
end $$;

-- Per-day status, computed from the logs (no stored copy to keep in sync).
-- meals_total counts the streak meals of the nutrition version in force that day.
create or replace function daily_status(p_trainee uuid, p_from date, p_to date)
returns table (day date, trained boolean, meals_total int, meals_done int)
language sql stable as $$
  with days as (
    select d::date as day, private.nutrition_version_on(p_trainee, d::date) as version_id
    from generate_series(p_from, p_to, interval '1 day') d)
  select days.day,
         exists (select 1 from workout_sessions s
                 where s.trainee_id = p_trainee and s.session_date = days.day),
         (select count(*) from meals m
          where m.version_id = days.version_id and m.counts_for_streak)::int,
         (select count(*) from meal_logs l join meals m on m.id = l.meal_id
          where l.trainee_id = p_trainee and l.log_date = days.day
            and m.version_id = days.version_id and m.counts_for_streak)::int
  from days
  where private.can_view_trainee(p_trainee)
  order by days.day;
$$;

-- Streak rules (walked forward from the first log):
--   * A training day counts if all streak meals are done.
--   * A rest day counts if all streak meals are done. With no nutrition
--     plan a rest day is neutral: it neither counts nor breaks.
--   * More than 14 rest days in a row breaks the streak; it restarts on
--     the next training day.
--   * A day with streak meals not all done is a missed day. Each streak
--     forgives one; the second resets the streak to 0.
--   * Today never breaks the streak; it counts once it qualifies.
create or replace function current_streak(p_trainee uuid default auth.uid())
returns int language plpgsql stable as $$
declare
  today date := private.local_today(p_trainee);
  first_day date;
  streak int := 0;
  rest_run int := 0;
  grace_used boolean := false;
  r record;
begin
  select least((select min(session_date) from workout_sessions where trainee_id = p_trainee),
               (select min(log_date) from meal_logs where trainee_id = p_trainee))
    into first_day;
  if first_day is null then
    return 0;
  end if;

  for r in select * from daily_status(p_trainee, first_day, today) loop
    if r.meals_done < r.meals_total then           -- missed day
      exit when r.day = today;
      if grace_used then
        streak := 0; rest_run := 0; grace_used := false;
      else
        grace_used := true;
      end if;
    elsif r.trained then
      rest_run := 0;
      streak := streak + 1;
    else                                           -- rest day
      exit when r.day = today and r.meals_total = 0;
      rest_run := rest_run + 1;
      if rest_run > 14 then
        streak := 0; grace_used := false;
      elsif r.meals_total > 0 then
        streak := streak + 1;
      end if;
    end if;
  end loop;
  return streak;
end $$;

-- Coach home: active trainees, most in need of attention first.
create or replace function coach_dashboard()
returns table (trainee_id uuid, full_name text, scopes text[],
               trained_today boolean, meals_done_today int, meals_total_today int,
               missed_days_7 int, days_since_workout int, milestones_due int,
               unread_messages int, streak int, subscription_days_left int)
language sql stable as $$
  with mine as (
    select ca.trainee_id, array_agg(s.key order by s.key) as scopes,
           private.local_today(ca.trainee_id) as today
    from coach_assignments ca join coaching_scopes s on s.id = ca.scope_id
    where ca.coach_id = auth.uid()
      and private.local_today(ca.trainee_id) between ca.starts_on and coalesce(ca.ends_on, 'infinity'::date)
    group by ca.trainee_id)
  select m.trainee_id, p.full_name, m.scopes,
         t.trained, t.meals_done, t.meals_total,
         (select count(*) from daily_status(m.trainee_id, m.today - 7, m.today - 1) w
          where w.meals_done < w.meals_total)::int as missed_days_7,
         m.today - (select max(session_date) from workout_sessions ws where ws.trainee_id = m.trainee_id),
         (select count(*) from milestones ml
          where ml.trainee_id = m.trainee_id and ml.submitted_at is null and ml.due_date <= m.today)::int as milestones_due,
         (select count(*) from messages msg join conversations c on c.id = msg.conversation_id
          where c.coach_id = auth.uid() and c.trainee_id = m.trainee_id
            and msg.sender_id <> auth.uid() and msg.read_at is null)::int as unread_messages,
         current_streak(m.trainee_id),
         (select max(ss.ends_on) - m.today + 1 from subscriptions ss
          where ss.trainee_id = m.trainee_id and ss.ends_on >= m.today)
  from mine m
  join profiles p on p.id = m.trainee_id
  cross join lateral daily_status(m.trainee_id, m.today, m.today) t
  order by missed_days_7 desc, milestones_due desc, unread_messages desc, p.full_name;
$$;

-- Earnings in a date range. A subscription is split into equal monthly
-- shares, one per subscription month counted from starts_on (1 Nov–31 Jan
-- = shares on 1 Nov, 1 Dec, 1 Jan). A share is earned on the day its month
-- starts. The last share takes the rounding remainder, so the shares add
-- up to the exact amount (833.33 + 833.33 + 833.34 = 2,500).
create or replace function coach_earnings(p_from date, p_to date, p_coach uuid default null)
returns table (coach_id uuid, trainee_id uuid, subscription_id uuid, amount_egp numeric)
language sql stable as $$
  select s.coach_id, s.trainee_id, s.id,
         sum(case when k = m.n - 1 then s.amount_egp - round(s.amount_egp / m.n, 2) * (m.n - 1)
                  else round(s.amount_egp / m.n, 2) end)
  from subscriptions s
  cross join lateral (select (extract(year from age(s.ends_on, s.starts_on)) * 12
                              + extract(month from age(s.ends_on, s.starts_on)))::int + 1 as n) m
  cross join lateral generate_series(0, m.n - 1) k
  where (s.starts_on + make_interval(months => k))::date between p_from and p_to
    and (p_coach is null or s.coach_id = p_coach)
  group by s.coach_id, s.trainee_id, s.id;
$$;

-- Admin dashboard: active trainees per coach
create or replace view coach_load with (security_invoker = true) as
select p.id as coach_id, p.full_name,
       count(distinct ca.trainee_id) filter (
         where current_date between ca.starts_on and coalesce(ca.ends_on, 'infinity'::date)) as active_trainees
from profiles p
join user_roles ur on ur.user_id = p.id
join roles r on r.id = ur.role_id and r.key = 'coach'
left join coach_assignments ca on ca.coach_id = p.id
group by p.id, p.full_name;

-- Subscription state for the trainee ("90 days left"), the coach and the admin.
create or replace view subscription_status with (security_invoker = true) as
select s.id, s.trainee_id, s.coach_id, s.amount_egp, s.starts_on, s.ends_on,
       s.ends_on - s.starts_on + 1 as days_total,
       greatest(0, s.ends_on - greatest(private.local_today(s.trainee_id), s.starts_on) + 1) as days_left,
       case
         when private.local_today(s.trainee_id) < s.starts_on then 'upcoming'
         when private.local_today(s.trainee_id) > s.ends_on then 'ended'
         when s.ends_on - private.local_today(s.trainee_id) < 7 then 'ending_soon'
         else 'active'
       end as status
from subscriptions s;

-- Reminder times to schedule on the device: the user's own settings, else
-- the defaults (meal time_hint, else the sign-up meal time, else off).
create or replace function my_reminders()
returns table (kind reminder_kind_t, meal_slot int, label text, at_time time,
               weekdays smallint[], enabled boolean, is_default boolean)
language sql stable as $$
  with cur_meals as (
    select row_number() over (order by m.sort_order)::int as slot, m.name, m.time_hint
    from meals m
    where m.version_id = private.nutrition_version_on(auth.uid(), private.local_today(auth.uid()))),
  signup_times as (
    select x.ord::int as slot, (x.t #>> '{}')::time as at_time
    from answers a
    join questions q on q.id = a.question_id and q.key = 'meal_times'
    cross join lateral jsonb_array_elements(a.value) with ordinality as x(t, ord)
    where a.user_id = auth.uid() and jsonb_typeof(a.value) = 'array'),
  wanted as (
    select d.kind, null::int as slot, null::text as label, d.at_time from reminder_defaults d
    union all
    select 'meal', cm.slot, cm.name, coalesce(cm.time_hint, st.at_time)
    from cur_meals cm left join signup_times st on st.slot = cm.slot)
  select w.kind, w.slot, w.label,
         coalesce(s.at_time, w.at_time),
         coalesce(s.weekdays, '{0,1,2,3,4,5,6}'),
         coalesce(s.enabled, w.at_time is not null),
         s.id is null
  from wanted w
  left join reminder_settings s
    on s.user_id = auth.uid() and s.kind = w.kind and s.meal_slot is not distinct from w.slot
  order by w.kind, w.slot;
$$;

-- New version of a plan, or apply a template / save as template: copies a
-- version with all its days or meals into p_to_plan.
create or replace function copy_workout_version(p_from uuid, p_to_plan uuid, p_effective_from date default null)
returns uuid language plpgsql as $$
declare
  v_new uuid;
  d record;
  d_new uuid;
begin
  insert into workout_plan_versions (plan_id, version_no, cycle_length, effective_from, source_file)
  select p_to_plan, 0, cycle_length, coalesce(p_effective_from, private.local_today()), source_file
  from workout_plan_versions where id = p_from
  returning id into v_new;
  if v_new is null then
    raise exception 'version not found';
  end if;
  for d in select * from workout_days where version_id = p_from loop
    insert into workout_days (version_id, day_number, name) values (v_new, d.day_number, d.name)
    returning id into d_new;
    insert into workout_day_exercises (day_id, exercise_id, sort_order, sets, reps_min, reps_max,
                                       duration_seconds, distance_m, rest_seconds, tempo, superset_group,
                                       video_url_1, video_url_2, coach_notes)
    select d_new, exercise_id, sort_order, sets, reps_min, reps_max, duration_seconds, distance_m,
           rest_seconds, tempo, superset_group, video_url_1, video_url_2, coach_notes
    from workout_day_exercises where day_id = d.id;
  end loop;
  return v_new;
end $$;

create or replace function copy_nutrition_version(p_from uuid, p_to_plan uuid, p_effective_from date default null)
returns uuid language plpgsql as $$
declare
  v_new uuid;
  m record;
  m_new uuid;
  o record;
  o_new uuid;
begin
  insert into nutrition_plan_versions (plan_id, version_no, effective_from)
  select p_to_plan, 0, coalesce(p_effective_from, private.local_today())
  from nutrition_plan_versions where id = p_from
  returning id into v_new;
  if v_new is null then
    raise exception 'version not found';
  end if;
  for m in select * from meals where version_id = p_from loop
    insert into meals (version_id, name, time_hint, sort_order, counts_for_streak)
    values (v_new, m.name, m.time_hint, m.sort_order, m.counts_for_streak)
    returning id into m_new;
    for o in select * from meal_options where meal_id = m.id loop
      insert into meal_options (meal_id, label, sort_order) values (m_new, o.label, o.sort_order)
      returning id into o_new;
      insert into meal_option_items (option_id, food_id, quantity, unit_id, grams, note, sort_order)
      select o_new, food_id, quantity, unit_id, grams, note, sort_order
      from meal_option_items where option_id = o.id;
    end loop;
  end loop;
  return v_new;
end $$;

-- Push token for this device; moves it if another account used it before.
create or replace function register_device_token(p_token text, p_platform platform_t)
returns void language sql security definer set search_path = public as $$
  insert into device_tokens (user_id, token, platform)
  select auth.uid(), p_token, p_platform where auth.uid() is not null
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, last_seen = now();
$$;

-- Account deletion (App Store / Play requirement). Personal data cascades;
-- subscriptions stay with trainee/coach set to null. Storage files are
-- removed by the delete-account Edge Function, which calls this last.
create or replace function delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

create or replace function admin_set_gender(p_user uuid, p_gender gender_t)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.is_admin() then
    raise exception 'admin only';
  end if;
  update profiles set gender = p_gender where id = p_user;
end $$;

revoke execute on function register_device_token(text, platform_t), delete_my_account(),
                           admin_set_gender(uuid, gender_t) from public, anon;

-- =====================================================================
-- 18. ROW-LEVEL SECURITY — every table in public
-- =====================================================================
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

grant usage on schema private to authenticated;

-- Lookup tables: everyone signed in reads, admins write.
do $$
declare t text;
begin
  foreach t in array array['roles', 'coaching_scopes', 'question_sections', 'questions', 'question_options',
                           'milestone_fields', 'notification_types', 'reminder_defaults'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_read', t);
    execute format('create policy %I on %I for all to authenticated
                    using ((select private.is_admin())) with check ((select private.is_admin()))', t || '_admin', t);
  end loop;
end $$;

-- Columns a user may change on their own profile (gender is not one of them).
revoke update on profiles from anon, authenticated;
grant update (full_name, date_of_birth, height_cm, phone, avatar_path, locale, timezone) on profiles to authenticated;

-- Profiles: self, admins, the trainee's active coaches, and both sides of
-- any chat (so past coaches/trainees still show a name in old chats).
create policy profiles_read on profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()) or private.is_coach_of(id)
         or exists (select 1 from conversations c
                    where (c.coach_id = profiles.id and c.trainee_id = (select auth.uid()))
                       or (c.trainee_id = profiles.id and c.coach_id = (select auth.uid()))));
create policy profiles_update_self on profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy user_roles_read on user_roles for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy user_roles_admin on user_roles for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy applications_read on applications for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy applications_submit on applications for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending' and reviewed_by is null);
create policy applications_review on applications for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy certificates_read on coach_certificates for select to authenticated
  using (coach_id = (select auth.uid()) or (select private.is_admin()));
create policy certificates_own on coach_certificates for all to authenticated
  using (coach_id = (select auth.uid())) with check (coach_id = (select auth.uid()));

create policy consents_read on consents for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy consents_accept on consents for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Health answers: the trainee, their active coaches and admins.
create policy answers_read on answers for select to authenticated
  using (private.can_view_trainee(user_id));
create policy answers_write_own on answers for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy assignments_read on coach_assignments for select to authenticated
  using (coach_id = (select auth.uid()) or trainee_id = (select auth.uid()) or (select private.is_admin()));
create policy assignments_admin on coach_assignments for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Exercise library and foods: shared; coaches add, the creator or an admin edits.
create policy exercises_read on exercises for select to authenticated using (true);
create policy exercises_add on exercises for insert to authenticated
  with check (((select private.has_role('coach')) and created_by = (select auth.uid())) or (select private.is_admin()));
create policy exercises_edit on exercises for update to authenticated
  using (created_by = (select auth.uid()) or (select private.is_admin()));
create policy exercises_delete on exercises for delete to authenticated
  using (created_by = (select auth.uid()) or (select private.is_admin()));

create policy aliases_read on exercise_aliases for select to authenticated using (true);
create policy aliases_add on exercise_aliases for insert to authenticated
  with check (((select private.has_role('coach')) and created_by = (select auth.uid())) or (select private.is_admin()));
create policy aliases_delete on exercise_aliases for delete to authenticated
  using (created_by = (select auth.uid()) or (select private.is_admin()));

create policy foods_read on foods for select to authenticated using (true);
create policy foods_add on foods for insert to authenticated
  with check (((select private.has_role('coach')) and source = 'custom' and created_by = (select auth.uid()))
              or (select private.is_admin()));
create policy foods_edit on foods for update to authenticated
  using ((source = 'custom' and created_by = (select auth.uid())) or (select private.is_admin()));
create policy foods_delete on foods for delete to authenticated
  using ((source = 'custom' and created_by = (select auth.uid())) or (select private.is_admin()));

create policy food_units_read on food_units for select to authenticated using (true);
create policy food_units_write on food_units for all to authenticated
  using ((select private.has_role('coach')) or (select private.is_admin()))
  with check ((select private.has_role('coach')) or (select private.is_admin()));

-- Plans: scope-aware (see private.*_access).
create policy workout_plans_read on workout_plans for select to authenticated
  using (private.workout_plan_access(id, false));
create policy workout_plans_add on workout_plans for insert to authenticated
  with check ((select private.is_admin())
              or (trainee_id is null and owner_coach_id = (select auth.uid()) and (select private.has_role('coach')))
              or (trainee_id is not null and private.is_coach_of(trainee_id, 'workout')));
create policy workout_plans_edit on workout_plans for update to authenticated
  using (private.workout_plan_access(id, true)) with check (private.workout_plan_access(id, true));
create policy workout_plans_delete on workout_plans for delete to authenticated
  using (private.workout_plan_access(id, true));

create policy workout_versions_read on workout_plan_versions for select to authenticated
  using (private.workout_plan_access(plan_id, false));
create policy workout_versions_write on workout_plan_versions for all to authenticated
  using (private.workout_plan_access(plan_id, true)) with check (private.workout_plan_access(plan_id, true));

create policy workout_days_read on workout_days for select to authenticated
  using (private.workout_version_access(version_id, false));
create policy workout_days_write on workout_days for all to authenticated
  using (private.workout_version_access(version_id, true)) with check (private.workout_version_access(version_id, true));

create policy workout_day_exercises_read on workout_day_exercises for select to authenticated
  using (private.workout_day_access(day_id, false));
create policy workout_day_exercises_write on workout_day_exercises for all to authenticated
  using (private.workout_day_access(day_id, true)) with check (private.workout_day_access(day_id, true));

create policy nutrition_plans_read on nutrition_plans for select to authenticated
  using (private.nutrition_plan_access(id, false));
create policy nutrition_plans_add on nutrition_plans for insert to authenticated
  with check ((select private.is_admin())
              or (trainee_id is null and owner_coach_id = (select auth.uid()) and (select private.has_role('coach')))
              or (trainee_id is not null and private.is_coach_of(trainee_id, 'nutrition')));
create policy nutrition_plans_edit on nutrition_plans for update to authenticated
  using (private.nutrition_plan_access(id, true)) with check (private.nutrition_plan_access(id, true));
create policy nutrition_plans_delete on nutrition_plans for delete to authenticated
  using (private.nutrition_plan_access(id, true));

create policy nutrition_versions_read on nutrition_plan_versions for select to authenticated
  using (private.nutrition_plan_access(plan_id, false));
create policy nutrition_versions_write on nutrition_plan_versions for all to authenticated
  using (private.nutrition_plan_access(plan_id, true)) with check (private.nutrition_plan_access(plan_id, true));

create policy meals_read on meals for select to authenticated
  using (private.nutrition_version_access(version_id, false));
create policy meals_write on meals for all to authenticated
  using (private.nutrition_version_access(version_id, true)) with check (private.nutrition_version_access(version_id, true));

create policy meal_options_read on meal_options for select to authenticated
  using (private.meal_access(meal_id, false));
create policy meal_options_write on meal_options for all to authenticated
  using (private.meal_access(meal_id, true)) with check (private.meal_access(meal_id, true));

create policy meal_option_items_read on meal_option_items for select to authenticated
  using (private.meal_option_access(option_id, false));
create policy meal_option_items_write on meal_option_items for all to authenticated
  using (private.meal_option_access(option_id, true)) with check (private.meal_option_access(option_id, true));

-- Logs: written by approved trainees for the last 7 local days; read by
-- anyone who can view the trainee.
create policy sessions_read on workout_sessions for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy sessions_write on workout_sessions for all to authenticated
  using (trainee_id = (select auth.uid()) and private.within_edit_window(trainee_id, session_date))
  with check (trainee_id = (select auth.uid()) and (select private.has_role('trainee'))
              and private.within_edit_window(trainee_id, session_date));

create policy set_logs_read on set_logs for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy set_logs_write on set_logs for all to authenticated
  using (exists (select 1 from workout_sessions ws where ws.id = session_id
                 and ws.trainee_id = (select auth.uid()) and private.within_edit_window(ws.trainee_id, ws.session_date)))
  with check (exists (select 1 from workout_sessions ws where ws.id = session_id
                      and ws.trainee_id = (select auth.uid()) and private.within_edit_window(ws.trainee_id, ws.session_date)));

create policy meal_logs_read on meal_logs for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy meal_logs_write on meal_logs for all to authenticated
  using (trainee_id = (select auth.uid()) and private.within_edit_window(trainee_id, log_date))
  with check (trainee_id = (select auth.uid()) and (select private.has_role('trainee'))
              and private.within_edit_window(trainee_id, log_date));

-- Milestones: coaches (any scope) and admins schedule and add them; the
-- trainee adds their own (the sign-up weight) and submits values.
create policy milestone_schedules_read on milestone_schedules for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy milestone_schedules_write on milestone_schedules for all to authenticated
  using (private.is_coach_of(trainee_id) or (select private.is_admin()))
  with check (private.is_coach_of(trainee_id) or (select private.is_admin()));

create policy milestone_schedule_fields_read on milestone_schedule_fields for select to authenticated
  using (exists (select 1 from milestone_schedules s where s.id = schedule_id));
create policy milestone_schedule_fields_write on milestone_schedule_fields for all to authenticated
  using (exists (select 1 from milestone_schedules s where s.id = schedule_id
                 and (private.is_coach_of(s.trainee_id) or (select private.is_admin()))))
  with check (exists (select 1 from milestone_schedules s where s.id = schedule_id
                      and (private.is_coach_of(s.trainee_id) or (select private.is_admin()))));

create policy milestones_read on milestones for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy milestones_add on milestones for insert to authenticated
  with check (trainee_id = (select auth.uid()) or private.is_coach_of(trainee_id) or (select private.is_admin()));
create policy milestones_edit on milestones for update to authenticated
  using (trainee_id = (select auth.uid()) or private.is_coach_of(trainee_id) or (select private.is_admin()))
  with check (trainee_id = (select auth.uid()) or private.is_coach_of(trainee_id) or (select private.is_admin()));
create policy milestones_delete on milestones for delete to authenticated
  using (submitted_at is null and (private.is_coach_of(trainee_id) or (select private.is_admin())));

create policy milestone_request_fields_read on milestone_request_fields for select to authenticated
  using (exists (select 1 from milestones m where m.id = milestone_id));
create policy milestone_request_fields_write on milestone_request_fields for all to authenticated
  using (exists (select 1 from milestones m where m.id = milestone_id
                 and (private.is_coach_of(m.trainee_id) or (select private.is_admin()))))
  with check (exists (select 1 from milestones m where m.id = milestone_id
                      and (private.is_coach_of(m.trainee_id) or (select private.is_admin()))));

-- Numbers visible to anyone with access; image rows only under the image rule.
create policy milestone_values_read on milestone_values for select to authenticated
  using (exists (select 1 from milestones m where m.id = milestone_id and (
           (image_path is null and private.can_view_trainee(m.trainee_id))
        or (image_path is not null and private.can_view_trainee_images(m.trainee_id)))));
create policy milestone_values_write on milestone_values for all to authenticated
  using (exists (select 1 from milestones m where m.id = milestone_id and m.trainee_id = (select auth.uid())))
  with check (exists (select 1 from milestones m where m.id = milestone_id and m.trainee_id = (select auth.uid())));

create policy notes_owner on notes for all to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));

-- Chat: participants read; you can only send as yourself; only the
-- recipient marks read (column grant); nobody edits or deletes.
create policy conversations_read on conversations for select to authenticated
  using ((select auth.uid()) in (coach_id, trainee_id));

revoke update on messages from anon, authenticated;
grant update (read_at) on messages to authenticated;

create policy messages_read on messages for select to authenticated
  using (exists (select 1 from conversations c where c.id = conversation_id
                 and (select auth.uid()) in (c.coach_id, c.trainee_id)));
create policy messages_send on messages for insert to authenticated
  with check (sender_id = (select auth.uid())
              and exists (select 1 from conversations c where c.id = conversation_id
                          and (select auth.uid()) in (c.coach_id, c.trainee_id)));
create policy messages_mark_read on messages for update to authenticated
  using (sender_id <> (select auth.uid())
         and exists (select 1 from conversations c where c.id = conversation_id
                     and (select auth.uid()) in (c.coach_id, c.trainee_id)));

-- Notifications: read and mark-read your own. Custom ones: admins to
-- anyone, coaches only to their own trainees.
revoke update on notifications from anon, authenticated;
grant update (read_at) on notifications to authenticated;

create policy notifications_own on notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
create policy notifications_mark_read on notifications for update to authenticated
  using (recipient_id = (select auth.uid()));
create policy notifications_send on notifications for insert to authenticated
  with check (type_key = 'custom' and sent_by = (select auth.uid())
              and ((select private.is_admin()) or private.is_coach_of(recipient_id)));

create policy device_tokens_own on device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy reminder_settings_own on reminder_settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Subscriptions: admins manage; the coach and the trainee read their own.
create policy subscriptions_admin on subscriptions for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy subscriptions_read_own on subscriptions for select to authenticated
  using (coach_id = (select auth.uid()) or trainee_id = (select auth.uid()));

-- =====================================================================
-- 19. STORAGE (private buckets; the app shows short-lived signed URLs)
-- =====================================================================
-- milestone-images/<trainee_id>/<file>   female image rule
-- certificates/<coach_id>/<file>         the coach and admins
-- avatars/<user_id>/<file>               anyone who can see the profile
create policy "milestone images read" on storage.objects for select to authenticated
  using (bucket_id = 'milestone-images'
         and private.can_view_trainee_images(private.try_uuid((storage.foldername(name))[1])));
create policy "milestone images upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'milestone-images'
              and private.try_uuid((storage.foldername(name))[1]) = (select auth.uid()));

create policy "certificates read" on storage.objects for select to authenticated
  using (bucket_id = 'certificates'
         and (private.try_uuid((storage.foldername(name))[1]) = (select auth.uid()) or (select private.is_admin())));
create policy "certificates upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'certificates'
              and private.try_uuid((storage.foldername(name))[1]) = (select auth.uid()));

create policy "avatars read" on storage.objects for select to authenticated
  using (bucket_id = 'avatars'
         and exists (select 1 from profiles p where p.id = private.try_uuid((storage.foldername(name))[1])));
create policy "avatars upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars'
              and private.try_uuid((storage.foldername(name))[1]) = (select auth.uid()));

-- Realtime: chat and the notification inbox arrive live.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table messages, notifications;
  end if;
end $$;

-- =====================================================================
-- 20. SEED: TRAINEE SIGN-UP QUESTIONS
-- Height, gender and date of birth are profile fields (basic info step).
-- Weight is entered in the basic info step and saved as the first milestone.
-- Edit is_required / sort_order freely; add questions with INSERTs.
-- =====================================================================
insert into question_sections (key, title_en, title_ar, sort_order) values
  ('goals',     'Your goals',          'أهدافك',            1),
  ('training',  'Training background', 'خلفيتك في التمرين', 2),
  ('lifestyle', 'Daily life',          'حياتك اليومية',     3),
  ('nutrition', 'Eating habits',       'عاداتك في الأكل',   4),
  ('health',    'Health history',      'تاريخك الصحي',      5);

with r as (select id from roles where key = 'trainee'),
     sec as (select id, key from question_sections),
     q(section, key, text_en, text_ar, answer_type, is_required, sort_order, min_value, max_value, hint_en, hint_ar) as (values
  ('goals','goal','What is your goal?','ما هو هدفك؟','single_choice',true,1,null,null,null,null),
  ('goals','why_now','Why did you decide to work out now?','ليه قررت تبدأ تتمرن دلوقتي؟','text',true,2,null,null,null,null),
  ('goals','motivation','What motivates you to keep training?','إيه اللي بيحفزك تكمل تمرين؟','text',false,3,null,null,null,null),
  ('goals','why_stopped','Why did you stop working out before?','ليه وقفت تمرين قبل كده؟','text',false,4,null,null,'Skip if you never stopped','تخطى السؤال لو عمرك ما وقفت'),
  ('training','years_training','How many years have you been training?','بقالك كام سنة بتتمرن؟','number',true,1,0,60,'Enter 0 if you are new','اكتب 0 لو أنت مبتدئ'),
  ('training','last_trained','When did you last train?','آخر مرة اتمرنت كانت امتى؟','single_choice',true,2,null,null,null,null),
  ('training','sessions_per_week','How many times would you exercise per week?','هتتمرن كام مرة في الأسبوع؟','number',true,3,1,7,null,null),
  ('training','pushups','How many push-ups can you do?','تقدر تعمل كام ضغط؟','number',false,4,0,500,null,null),
  ('training','pullups','How many pull-ups can you do?','تقدر تعمل كام عقلة؟','number',false,5,0,200,null,null),
  ('training','injuries','Do you have any injuries?','عندك أي إصابات؟','text',true,6,null,null,'Write "None" if you have none','اكتب "لا يوجد" لو مفيش'),
  ('training','exercises_to_avoid','Any exercises to avoid?','في تمارين لازم تتجنبها؟','text',false,7,null,null,null,null),
  ('lifestyle','occupation','What do you do for a living?','بتشتغل إيه؟','text',true,1,null,null,null,null),
  ('lifestyle','activity_level','How active is your daily routine?','نشاطك اليومي عامل إزاي؟','single_choice',true,2,null,null,null,null),
  ('nutrition','meals_per_day','How many meals do you prefer per day?','تحب تاكل كام وجبة في اليوم؟','number',true,1,1,8,null,null),
  ('nutrition','meal_times','What time do you prefer to eat each meal?','تحب تاكل كل وجبة الساعة كام؟','time_list',true,2,null,null,'One time per meal','وقت لكل وجبة'),
  ('nutrition','snacks_per_day','How many snacks do you prefer per day?','تحب تاكل كام سناك في اليوم؟','number',true,3,0,6,null,null),
  ('nutrition','favorite_foods','What is your favorite food for each meal?','إيه أكلك المفضل في كل وجبة؟','text',false,4,null,null,null,null),
  ('nutrition','junk_food_per_week','How many times do you eat junk food per week?','بتاكل أكل جاهز كام مرة في الأسبوع؟','number',true,5,0,21,null,null),
  ('nutrition','allergies','Are you allergic to any food?','عندك حساسية من أي أكل؟','text',true,6,null,null,'Write "None" if you have none','اكتب "لا يوجد" لو مفيش'),
  ('nutrition','protein_budget','How much can you spend on protein?','قدرتك على الصرف على البروتين؟','single_choice',true,7,null,null,'Helps your coach pick affordable foods','بيساعد مدربك يختار أكل مناسب لميزانيتك'),
  ('health','medications','What medications are you taking?','بتاخد أدوية إيه؟','text',false,1,null,null,null,null),
  ('health','surgeries','Have you had any surgery before?','عملت أي عمليات قبل كده؟','text',false,2,null,null,null,null),
  ('health','family_obesity','Is there morbid obesity in your family?','في سمنة مفرطة في العيلة؟','boolean',false,3,null,null,null,null),
  ('health','overweight_as_child','Were you overweight when you were young?','كنت وزنك زيادة وأنت صغير؟','boolean',false,4,null,null,null,null)
)
insert into questions (role_id, section_id, key, text_en, text_ar, answer_type, is_required, sort_order, min_value, max_value, hint_en, hint_ar)
select r.id, sec.id, q.key, q.text_en, q.text_ar, q.answer_type::answer_type_t, q.is_required, q.sort_order, q.min_value::numeric, q.max_value::numeric, q.hint_en, q.hint_ar
from q cross join r join sec on sec.key = q.section;

insert into question_options (question_id, value, label_en, label_ar, sort_order)
select q.id, o.value, o.label_en, o.label_ar, o.sort_order
from questions q join (values
  ('goal','lose_fat','Lose fat','خسارة دهون',1),
  ('goal','build_muscle','Build muscle','بناء عضل',2),
  ('goal','recomp','Lose fat and build muscle','خسارة دهون وبناء عضل',3),
  ('goal','fitness','Improve fitness and health','تحسين اللياقة والصحة',4),
  ('last_trained','now','I train currently','بتمرن حاليًا',1),
  ('last_trained','lt_1m','Less than a month ago','من أقل من شهر',2),
  ('last_trained','1_6m','1 to 6 months ago','من شهر لـ 6 شهور',3),
  ('last_trained','6_12m','6 to 12 months ago','من 6 لـ 12 شهر',4),
  ('last_trained','gt_1y','More than a year ago','من أكتر من سنة',5),
  ('last_trained','never','Never','عمري ما اتمرنت',6),
  ('activity_level','sedentary','Mostly sitting (desk job)','قاعد أغلب الوقت (شغل مكتب)',1),
  ('activity_level','light','Lightly active','نشاط خفيف',2),
  ('activity_level','active','Active (on my feet a lot)','نشيط (واقف وماشي كتير)',3),
  ('activity_level','very_active','Very active (physical job)','نشيط جدًا (شغل بدني)',4),
  ('protein_budget','low','Low','قليلة',1),
  ('protein_budget','medium','Medium','متوسطة',2),
  ('protein_budget','high','High','عالية',3)
) o(qkey, value, label_en, label_ar, sort_order) on o.qkey = q.key;
