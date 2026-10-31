-- =====================================================================
-- Fitness Coaching App — Postgres schema (Supabase)
-- Version 2 · 2026-10-29
--
-- Conventions
--   * Every user is a row in auth.users (Supabase Auth) + public.profiles.
--   * Roles, scopes, sign-up questions, milestone fields and notification
--     types are DATA (lookup tables), not code — add new ones with INSERTs.
--   * Plans are versioned; logs point at the version they were made under.
--   * A plan with trainee_id IS NULL is a template.
--   * Weights in kg, energy in kcal, food values per 100 g.
-- =====================================================================

create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Enums: only for values the code logic genuinely depends on
-- ---------------------------------------------------------------------
create type gender_t            as enum ('male', 'female');
create type application_status  as enum ('pending', 'approved', 'rejected');
create type answer_type_t       as enum ('text', 'number', 'boolean', 'date', 'single_choice', 'multi_choice', 'time_list');
create type food_source_t       as enum ('usda', 'open_food_facts', 'custom');
create type field_kind_t        as enum ('number', 'image');
create type platform_t          as enum ('ios', 'android');

-- =====================================================================
-- 1. IDENTITY & ROLES
-- =====================================================================
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text not null,
  gender          gender_t not null,
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
  granted_by  uuid references profiles(id),
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
  reviewed_by  uuid references profiles(id),
  reviewed_at  timestamptz
);
create unique index one_pending_application
  on applications (user_id, role_id) where status = 'pending';

create table coach_certificates (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references profiles(id) on delete cascade,
  title       text not null,
  issuer      text,
  issued_on   date,
  file_path   text not null,                 -- storage: certificates/<coach_id>/...
  uploaded_at timestamptz not null default now()
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
  sort_order  int not null default 0
);

create table answers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  question_id uuid not null references questions(id),
  value       jsonb not null,                -- "abc" | 72.5 | true | ["a","b"] | ["09:00","14:00"]
  answered_at timestamptz not null default now(),
  unique (user_id, question_id)
);

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
  coach_id       uuid not null references profiles(id),
  trainee_id     uuid not null references profiles(id),
  scope_id       smallint not null references coaching_scopes(id),
  starts_on      date not null default current_date,
  ends_on        date,                       -- null = active
  assigned_by    uuid not null references profiles(id),
  created_at     timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);
create unique index one_active_coach_per_scope
  on coach_assignments (trainee_id, scope_id) where ends_on is null;
create index on coach_assignments (coach_id) where ends_on is null;

-- =====================================================================
-- 4. EXERCISE LIBRARY
-- =====================================================================
create table exercises (
  id               uuid primary key default gen_random_uuid(),
  name_en          text not null,
  name_ar          text,
  category         text,                     -- strength, cardio, stretching...
  primary_muscles  text[] not null default '{}',
  equipment        text,
  source           text not null default 'custom',  -- 'free-exercise-db' | 'custom'
  source_ref       text,
  created_by       uuid references profiles(id),
  created_at       timestamptz not null default now()
);
create unique index exercises_name_unique on exercises (lower(name_en));
create index exercises_name_trgm on exercises using gin (name_en gin_trgm_ops);

-- Saved spellings: "Flat bench" -> Bench Press
create table exercise_aliases (
  id          uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references exercises(id) on delete cascade,
  alias       text not null,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);
create unique index exercise_alias_unique on exercise_aliases (lower(alias));
create index exercise_alias_trgm on exercise_aliases using gin (alias gin_trgm_ops);

-- Used by the Excel import: exact/alias match first, then similar names.
create or replace function match_exercise(p_name text, p_limit int default 3)
returns table (exercise_id uuid, name_en text, score real, exact boolean)
language sql stable as $$
  with candidates as (
    select e.id, e.name_en, similarity(e.name_en, p_name) as score,
           lower(e.name_en) = lower(p_name) as exact
    from exercises e
    union all
    select a.exercise_id, e.name_en, similarity(a.alias, p_name),
           lower(a.alias) = lower(p_name)
    from exercise_aliases a join exercises e on e.id = a.exercise_id
  )
  select id, name_en, max(score), bool_or(exact)
  from candidates
  where exact or score > 0.3
  group by id, name_en
  order by bool_or(exact) desc, max(score) desc
  limit p_limit;
$$;

-- =====================================================================
-- 5. WORKOUT PLANS (versioned, cycle-based)
-- =====================================================================
create table workout_plans (
  id              uuid primary key default gen_random_uuid(),
  owner_coach_id  uuid not null references profiles(id),
  trainee_id      uuid references profiles(id),   -- null = template
  name            text not null,
  copied_from_id  uuid references workout_plans(id),
  is_archived     boolean not null default false,
  created_at      timestamptz not null default now()
);
create index on workout_plans (trainee_id) where trainee_id is not null;

create table workout_plan_versions (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references workout_plans(id) on delete cascade,
  version_no      int not null,
  cycle_length    int not null check (cycle_length > 0), -- e.g. 7 (days incl. rest)
  effective_from  date not null default current_date,
  source_file     text,                                  -- uploaded Excel, if any
  created_by      uuid not null references profiles(id),
  created_at      timestamptz not null default now(),
  unique (plan_id, version_no)
);

-- Only training days are stored; missing day numbers in the cycle = rest.
create table workout_days (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references workout_plan_versions(id) on delete cascade,
  day_number  int not null,
  name        text not null,               -- 'Push Day'
  unique (version_id, day_number)
);

create table workout_day_exercises (
  id              uuid primary key default gen_random_uuid(),
  day_id          uuid not null references workout_days(id) on delete cascade,
  exercise_id     uuid not null references exercises(id),
  sort_order      int not null,
  sets            int not null check (sets > 0),
  reps_min        int not null,
  reps_max        int,                      -- null = fixed reps
  rest_seconds    int,
  tempo           text,
  superset_group  text,                     -- same letter = superset
  video_url_1     text,
  video_url_2     text,
  coach_notes     text
);

-- Where the trainee is in the cycle. Advances only when a session is logged.
create table trainee_cycle_state (
  trainee_id       uuid primary key references profiles(id) on delete cascade,
  plan_version_id  uuid not null references workout_plan_versions(id),
  next_day_number  int not null default 1,
  updated_at       timestamptz not null default now()
);

-- =====================================================================
-- 6. WORKOUT LOGS
-- =====================================================================
-- No session on a date = rest day.
create table workout_sessions (
  id               uuid primary key default gen_random_uuid(),
  trainee_id       uuid not null references profiles(id) on delete cascade,
  workout_day_id   uuid not null references workout_days(id),
  session_date     date not null,
  completed_at     timestamptz,
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (trainee_id, session_date),
  check (session_date <= current_date)
);

create table set_logs (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references workout_sessions(id) on delete cascade,
  day_exercise_id   uuid not null references workout_day_exercises(id),
  exercise_id       uuid not null references exercises(id),  -- denormalised for progress charts
  set_number        int not null,
  reps              int not null,
  weight_kg         numeric(6,2) not null default 0,
  created_at        timestamptz not null default now(),
  unique (session_id, day_exercise_id, set_number)
);
create index set_logs_progress on set_logs (exercise_id, created_at);

-- Last weight per set for pre-filling.
create or replace function last_weights(p_trainee uuid, p_exercise uuid)
returns table (set_number int, reps int, weight_kg numeric)
language sql stable as $$
  select sl.set_number, sl.reps, sl.weight_kg
  from set_logs sl
  join workout_sessions ws on ws.id = sl.session_id
  where ws.trainee_id = p_trainee and sl.exercise_id = p_exercise
    and ws.session_date = (
      select max(ws2.session_date) from workout_sessions ws2
      join set_logs sl2 on sl2.session_id = ws2.id
      where ws2.trainee_id = p_trainee and sl2.exercise_id = p_exercise)
  order by sl.set_number;
$$;

-- =====================================================================
-- 7. FOODS
-- =====================================================================
create table foods (
  id              uuid primary key default gen_random_uuid(),
  name_en         text not null,
  name_ar         text,
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
  created_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  unique (source, source_ref)
);
create index foods_name_trgm on foods using gin (name_en gin_trgm_ops);
create index foods_name_ar_trgm on foods using gin (name_ar gin_trgm_ops);
create index on foods (barcode) where barcode is not null;

-- =====================================================================
-- 8. NUTRITION PLANS (versioned, meals -> options -> items)
-- =====================================================================
create table nutrition_plans (
  id              uuid primary key default gen_random_uuid(),
  owner_coach_id  uuid not null references profiles(id),
  trainee_id      uuid references profiles(id),  -- null = template
  name            text not null,
  show_macros     boolean not null default true,
  copied_from_id  uuid references nutrition_plans(id),
  is_archived     boolean not null default false,
  created_at      timestamptz not null default now()
);
create index on nutrition_plans (trainee_id) where trainee_id is not null;

create table nutrition_plan_versions (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references nutrition_plans(id) on delete cascade,
  version_no      int not null,
  effective_from  date not null default current_date,
  created_by      uuid not null references profiles(id),
  created_at      timestamptz not null default now(),
  unique (plan_id, version_no)
);

create table meals (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references nutrition_plan_versions(id) on delete cascade,
  name        text not null,                 -- 'Breakfast'
  time_hint   time,
  sort_order  int not null
);

create table meal_options (
  id          uuid primary key default gen_random_uuid(),
  meal_id     uuid not null references meals(id) on delete cascade,
  label       text not null,                 -- 'A', 'B', 'Chicken option'
  sort_order  int not null
);

create table meal_option_items (
  id          uuid primary key default gen_random_uuid(),
  option_id   uuid not null references meal_options(id) on delete cascade,
  food_id     uuid not null references foods(id),
  grams       numeric(7,1) not null check (grams > 0),
  note        text,
  sort_order  int not null default 0
);

create table meal_logs (
  id            uuid primary key default gen_random_uuid(),
  trainee_id    uuid not null references profiles(id) on delete cascade,
  meal_id       uuid not null references meals(id),
  option_id     uuid references meal_options(id),
  log_date      date not null,
  completed_at  timestamptz not null default now(),
  change_note   text,                        -- "Did you change anything in this meal?"
  unique (trainee_id, meal_id, log_date),
  check (log_date <= current_date)
);

-- =====================================================================
-- 9. MILESTONES (data-driven fields, scheduled)
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

create table milestone_schedules (
  id              uuid primary key default gen_random_uuid(),
  trainee_id      uuid not null references profiles(id) on delete cascade,
  name            text not null,             -- 'Daily weight', 'Bi-weekly check-in'
  every_n_days    int not null check (every_n_days > 0),
  starts_on       date not null default current_date,
  is_active       boolean not null default true,
  created_by      uuid not null references profiles(id),
  created_at      timestamptz not null default now()
);

create table milestone_schedule_fields (
  schedule_id  uuid not null references milestone_schedules(id) on delete cascade,
  field_id     smallint not null references milestone_fields(id),
  is_required  boolean not null default true,
  primary key (schedule_id, field_id)
);

create table milestones (
  id            uuid primary key default gen_random_uuid(),
  trainee_id    uuid not null references profiles(id) on delete cascade,
  schedule_id   uuid references milestone_schedules(id),
  due_date      date not null,
  submitted_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique (schedule_id, due_date)
);
create index on milestones (trainee_id, due_date desc);

create table milestone_values (
  id            uuid primary key default gen_random_uuid(),
  milestone_id  uuid not null references milestones(id) on delete cascade,
  field_id      smallint not null references milestone_fields(id),
  number_value  numeric(7,2),
  image_path    text,                        -- storage: milestone-images/<trainee_id>/...
  unique (milestone_id, field_id),
  check ((number_value is not null) <> (image_path is not null))
);

-- =====================================================================
-- 10. DAILY STATUS & STREAKS
-- =====================================================================
-- One row per trainee per day, maintained by triggers on sessions/meal logs.
create table daily_status (
  trainee_id     uuid not null references profiles(id) on delete cascade,
  day            date not null,
  trained        boolean not null default false,
  meals_total    int not null default 0,
  meals_done     int not null default 0,
  primary key (trainee_id, day)
);

-- Streak rules: a day counts if all meals are done (training optional = rest day).
-- More than 14 consecutive rest days breaks it. Each streak gets ONE grace
-- day: the first fully missed day is forgiven, the second breaks the streak.
create or replace function current_streak(p_trainee uuid)
returns int language plpgsql stable as $$
declare
  d date := current_date;
  streak int := 0;
  rest_run int := 0;
  grace_used boolean := false;
  r daily_status%rowtype;
begin
  loop
    select * into r from daily_status where trainee_id = p_trainee and day = d;
    if found and r.meals_total > 0 and r.meals_done = r.meals_total then
      if r.trained then rest_run := 0; else rest_run := rest_run + 1; end if;
      exit when rest_run > 14;
      streak := streak + 1;
    elsif d = current_date then
      null;                                   -- today not finished yet
    elsif not grace_used then
      grace_used := true;
    else
      exit;
    end if;
    d := d - 1;
    exit when d < current_date - 3650;
  end loop;
  return streak;
end $$;

-- =====================================================================
-- 11. NOTES (always private to author)
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
-- 12. CHAT
-- =====================================================================
create table conversations (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references profiles(id),
  trainee_id  uuid not null references profiles(id),
  created_at  timestamptz not null default now(),
  unique (coach_id, trainee_id)
);

create table messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references conversations(id) on delete cascade,
  sender_id        uuid not null references profiles(id),
  body             text,
  image_path       text,
  created_at       timestamptz not null default now(),
  read_at          timestamptz,
  check (body is not null or image_path is not null)
);
create index on messages (conversation_id, created_at desc);

-- =====================================================================
-- 13. NOTIFICATIONS & REMINDERS
-- =====================================================================
create table notification_types (
  key          text primary key,             -- 'approval', 'plan_ready', 'custom'...
  name_en      text not null,
  name_ar      text not null,
  default_push boolean not null default true
);
insert into notification_types (key, name_en, name_ar) values
  ('application_result', 'Application result', 'نتيجة الطلب'),
  ('plan_ready',         'Plan ready',         'الخطة جاهزة'),
  ('reminder',           'Reminder',           'تذكير'),
  ('no_data_today',      'Nothing logged',     'لم يتم التسجيل'),
  ('milestone_uploaded', 'Milestone uploaded', 'تم رفع إنجاز'),
  ('trainee_assigned',   'New trainee',        'متدرب جديد'),
  ('chat_message',       'New message',        'رسالة جديدة'),
  ('custom',             'Message from coach', 'رسالة من المدرب');

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references profiles(id) on delete cascade,
  type_key      text not null references notification_types(key),
  title         text not null,
  body          text,
  data          jsonb not null default '{}',  -- deep-link payload
  sent_by       uuid references profiles(id),
  created_at    timestamptz not null default now(),
  read_at       timestamptz
);
create index on notifications (recipient_id, created_at desc);

create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  token       text not null unique,
  platform    platform_t not null,
  last_seen   timestamptz not null default now()
);

create table reminder_settings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        text not null,                 -- 'workout', 'meals', 'milestone', 'daily_data'
  at_time     time not null,
  weekdays    smallint[] not null default '{0,1,2,3,4,5,6}',
  enabled     boolean not null default true,
  unique (user_id, kind)
);

-- =====================================================================
-- 14. SUBSCRIPTIONS & COACH EARNINGS (tracking only, no payments)
-- =====================================================================
-- Entered by the admin. All amounts in EGP. Each subscription is credited
-- in full to the coach the admin picks.
create table subscriptions (
  id           uuid primary key default gen_random_uuid(),
  trainee_id   uuid not null references profiles(id),
  coach_id     uuid not null references profiles(id),
  amount_egp   numeric(10,2) not null check (amount_egp >= 0),
  starts_on    date not null,
  ends_on      date not null,
  recorded_by  uuid not null references profiles(id),
  note         text,
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index on subscriptions (coach_id, starts_on);

-- Daily earnings: each subscription is spread evenly over its days, so a coach
-- can see what they earned in any date range (e.g. this month).
create or replace view coach_daily_earnings as
select s.coach_id,
       s.trainee_id,
       s.id as subscription_id,
       d::date as day,
       round(s.amount_egp / (s.ends_on - s.starts_on + 1), 4) as amount_egp
from subscriptions s
cross join lateral generate_series(s.starts_on, s.ends_on, interval '1 day') d;

-- Admin dashboard: active trainees per coach
create or replace view coach_load as
select p.id as coach_id, p.full_name,
       count(distinct ca.trainee_id) filter (where ca.ends_on is null) as active_trainees
from profiles p
join user_roles ur on ur.user_id = p.id
join roles r on r.id = ur.role_id and r.key = 'coach'
left join coach_assignments ca on ca.coach_id = p.id
group by p.id, p.full_name;

-- =====================================================================
-- 15. ACCESS HELPERS (used by RLS and storage policies)
-- =====================================================================
create or replace function has_role(p_user uuid, p_role text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles ur join roles r on r.id = ur.role_id
                 where ur.user_id = p_user and r.key = p_role);
$$;

-- Active assignments only. An active coach sees the trainee's FULL history
-- (all rows, including those logged before the assignment started).
create or replace function is_coach_of(p_coach uuid, p_trainee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from coach_assignments
                 where coach_id = p_coach and trainee_id = p_trainee and ends_on is null);
$$;

create or replace function can_view_trainee(p_viewer uuid, p_trainee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_viewer = p_trainee or has_role(p_viewer, 'admin') or is_coach_of(p_viewer, p_trainee);
$$;

-- Female image rule: a female trainee's images are visible only to female viewers.
create or replace function can_view_trainee_images(p_viewer uuid, p_trainee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select can_view_trainee(p_viewer, p_trainee)
     and (
       p_viewer = p_trainee
       or (select gender from profiles where id = p_trainee) = 'male'
       or (select gender from profiles where id = p_viewer) = 'female'
     );
$$;

create or replace function within_edit_window(p_day date)
returns boolean language sql stable as $$
  select p_day between current_date - 7 and current_date;
$$;

-- =====================================================================
-- 16. ROW-LEVEL SECURITY (core policies; extend per table)
-- =====================================================================
alter table profiles          enable row level security;
alter table workout_sessions  enable row level security;
alter table set_logs          enable row level security;
alter table meal_logs         enable row level security;
alter table milestones        enable row level security;
alter table milestone_values  enable row level security;
alter table notes             enable row level security;
alter table messages          enable row level security;
alter table notifications     enable row level security;
alter table subscriptions     enable row level security;
alter table answers           enable row level security;

create policy profiles_read on profiles for select
  using (can_view_trainee(auth.uid(), id) or is_coach_of(id, auth.uid()));
create policy profiles_update_self on profiles for update
  using (id = auth.uid());

create policy sessions_read on workout_sessions for select
  using (can_view_trainee(auth.uid(), trainee_id));
create policy sessions_write on workout_sessions for all
  using (trainee_id = auth.uid() and within_edit_window(session_date))
  with check (trainee_id = auth.uid() and within_edit_window(session_date));

create policy set_logs_read on set_logs for select
  using (exists (select 1 from workout_sessions ws where ws.id = session_id
                 and can_view_trainee(auth.uid(), ws.trainee_id)));
create policy set_logs_write on set_logs for all
  using (exists (select 1 from workout_sessions ws where ws.id = session_id
                 and ws.trainee_id = auth.uid() and within_edit_window(ws.session_date)));

create policy meal_logs_read on meal_logs for select
  using (can_view_trainee(auth.uid(), trainee_id));
create policy meal_logs_write on meal_logs for all
  using (trainee_id = auth.uid() and within_edit_window(log_date))
  with check (trainee_id = auth.uid() and within_edit_window(log_date));

create policy milestones_read on milestones for select
  using (can_view_trainee(auth.uid(), trainee_id));

-- Numbers visible to anyone with access; image rows only under the image rule.
create policy milestone_values_read on milestone_values for select
  using (exists (select 1 from milestones m where m.id = milestone_id and (
           (image_path is null and can_view_trainee(auth.uid(), m.trainee_id))
        or (image_path is not null and can_view_trainee_images(auth.uid(), m.trainee_id)))));

create policy notes_owner on notes for all
  using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy messages_participants on messages for all
  using (exists (select 1 from conversations c where c.id = conversation_id
                 and auth.uid() in (c.coach_id, c.trainee_id)));

create policy notifications_own on notifications for select
  using (recipient_id = auth.uid());

create policy subscriptions_admin on subscriptions for all
  using (has_role(auth.uid(), 'admin'));
create policy subscriptions_coach_read on subscriptions for select
  using (coach_id = auth.uid());

create policy answers_read on answers for select
  using (can_view_trainee(auth.uid(), user_id));
create policy answers_write_own on answers for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Storage: private bucket 'milestone-images', path '<trainee_id>/<file>'
-- create policy "milestone images read" on storage.objects for select
--   using (bucket_id = 'milestone-images'
--          and can_view_trainee_images(auth.uid(), (storage.foldername(name))[1]::uuid));

-- =====================================================================
-- 17. SEED: TRAINEE SIGN-UP QUESTIONS
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
