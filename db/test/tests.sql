-- Behaviour tests for schema.sql. Run with db/test/run.sh.
-- Each check raises "FAIL: ..." and stops the run if it does not hold.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create schema t;
grant usage on schema t to anon, authenticated;

create table t.users (name text primary key, id uuid not null);
grant select on t.users to anon, authenticated;

create function t.id(p_name text) returns uuid language sql stable as $$
  select id from t.users where name = p_name
$$;

create function t.login(p_name text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(t.id(p_name)::text, ''), false);
$$;

create function t.check(p_ok boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'FAIL: %', p_msg;
  end if;
  raise notice 'ok - %', p_msg;
end $$;

-- true when the statement errors (RLS, constraint, trigger, privilege)
create function t.fails(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return true;
end $$;

create function t.today() returns date language sql stable as $$
  select (now() at time zone 'Africa/Cairo')::date
$$;

grant execute on all functions in schema t to anon, authenticated;

-- Setup helpers below run as the superuser (RLS bypassed).
create function t.make_user(p_name text, p_gender text, p_roles text[]) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into t.users values (p_name, v);
  insert into auth.users (id, raw_user_meta_data)
  values (v, jsonb_build_object('full_name', p_name, 'gender', p_gender));
  insert into user_roles (user_id, role_id) select v, id from roles where key = any (p_roles);
  return v;
end $$;

-- Workout plan: 4-day cycle, Day 1 Push, Day 2 Pull, Day 3 planned rest, Day 4 Legs.
-- Nutrition plan: Breakfast 08:00, Lunch (no time), Snack (not counted for streak).
create function t.make_plans(p_trainee text, p_nutrition boolean, p_from date) returns void language plpgsql as $$
declare
  wp uuid; wv uuid; d uuid; np uuid; nv uuid; m uuid;
begin
  insert into workout_plans (trainee_id, name) values (t.id(p_trainee), 'PPL') returning id into wp;
  insert into workout_plan_versions (plan_id, version_no, cycle_length, effective_from)
  values (wp, 0, 4, p_from) returning id into wv;
  insert into workout_days (version_id, day_number, name) values (wv, 1, 'Push') returning id into d;
  insert into workout_day_exercises (day_id, exercise_id, sort_order, sets, reps_min, reps_max)
  select d, id, 1, 3, 8, 10 from exercises where name_en = 'Bench Press';
  insert into workout_day_exercises (day_id, exercise_id, sort_order, sets, duration_seconds, distance_m)
  select d, id, 2, 1, 600, 2000 from exercises where name_en = 'Treadmill';
  insert into workout_days (version_id, day_number, name) values (wv, 2, 'Pull'), (wv, 4, 'Legs');
  if p_nutrition then
    insert into nutrition_plans (trainee_id, name) values (t.id(p_trainee), 'Cut') returning id into np;
    insert into nutrition_plan_versions (plan_id, version_no, effective_from) values (np, 0, p_from) returning id into nv;
    insert into meals (version_id, name, time_hint, sort_order) values (nv, 'Breakfast', '08:00', 1);
    insert into meals (version_id, name, sort_order) values (nv, 'Lunch', 2);
    insert into meals (version_id, name, sort_order, counts_for_streak) values (nv, 'Snack', 3, false);
    for m in select id from meals where version_id = nv loop
      insert into meal_options (meal_id, label, sort_order) values (m, 'A', 1);
    end loop;
  end if;
end $$;

-- One day of history: optionally a workout (Day 1) and the first p_meals meals.
create function t.log_day(p_trainee text, p_offset int, p_trained boolean, p_meals int) returns void language plpgsql as $$
declare day date := t.today() + p_offset;
begin
  if p_trained then
    insert into workout_sessions (trainee_id, workout_day_id, session_date)
    select t.id(p_trainee), d.id, day
    from workout_days d join workout_plan_versions v on v.id = d.version_id
    join workout_plans p on p.id = v.plan_id
    where p.trainee_id = t.id(p_trainee) and d.day_number = 1
    order by v.version_no desc limit 1;
  end if;
  insert into meal_logs (trainee_id, meal_id, log_date)
  select t.id(p_trainee), m.id, day
  from meals m join nutrition_plan_versions v on v.id = m.version_id
  join nutrition_plans p on p.id = v.plan_id
  where p.trainee_id = t.id(p_trainee)
  order by m.sort_order limit p_meals;
end $$;

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------
insert into exercises (name_en, tracking, created_by) values
  ('Bench Press', 'weight_reps', null), ('Treadmill', 'distance_duration', null), ('Plank', 'duration', null);

select t.make_user('admin',  'male',   '{admin}');
select t.make_user('coach1', 'male',   '{coach}');     -- F's workout coach
select t.make_user('coach2', 'female', '{coach}');     -- F's nutrition coach
select t.make_user('f',      'female', '{}');          -- approved during the tests
select t.make_user('m',      'male',   '{trainee}');   -- workout only
select t.make_user('x',      'male',   '{}');          -- no coach
select t.make_user('s1',     'male',   '{trainee}');   -- streak fixtures
select t.make_user('s2',     'female', '{trainee}');
select t.make_user('s3',     'female', '{trainee}');
select t.make_user('s4',     'female', '{trainee}');

insert into coach_assignments (coach_id, trainee_id, scope_id, starts_on)
select t.id('coach1'), t.id('f'), id, t.today() - 60 from coaching_scopes where key = 'workout';
insert into coach_assignments (coach_id, trainee_id, scope_id, starts_on)
select t.id('coach2'), t.id('f'), id, t.today() - 60 from coaching_scopes where key = 'nutrition';
insert into coach_assignments (coach_id, trainee_id, scope_id, starts_on)
select t.id('coach1'), t.id('m'), id, t.today() - 60 from coaching_scopes where key = 'workout';

select t.make_plans('f',  true,  t.today() - 30);
select t.make_plans('m',  false, t.today() - 30);
select t.make_plans('s1', false, t.today() - 60);
select t.make_plans('s2', true,  t.today() - 60);
select t.make_plans('s3', true,  t.today() - 60);
select t.make_plans('s4', true,  t.today() - 60);

insert into answers (user_id, question_id, value)
select t.id('f'), id, '["09:00", "14:00", "20:00"]' from questions where key = 'meal_times';

-- =====================================================================
-- 1. Security
-- =====================================================================
select t.check(not exists (select 1 from pg_tables where schemaname = 'public' and not rowsecurity),
               'every public table has RLS enabled');
select t.check((select gender from profiles where id = t.id('f')) = 'female',
               'sign-up trigger creates the profile from metadata');
select t.check(t.fails($$insert into auth.users values (gen_random_uuid(), '{"full_name": "No gender"}')$$),
               'sign-up without gender is rejected');

set role anon;
select t.check((select count(*) from profiles) = 0, 'anon sees no profiles');
reset role;

set role authenticated;
select t.login('m');
select t.check(t.fails($$insert into user_roles (user_id, role_id) select auth.uid(), id from roles where key = 'admin'$$),
               'a trainee cannot grant himself admin');
select t.check(t.fails($$update profiles set gender = 'female' where id = auth.uid()$$),
               'a user cannot change their own gender');
select t.check(not t.fails($$update profiles set full_name = 'M renamed' where id = auth.uid()$$),
               'a user can still edit their name');
select t.check(t.fails($$insert into coach_assignments (coach_id, trainee_id, scope_id) values (auth.uid(), t.id('f'), 1)$$),
               'a non-admin cannot create coach assignments');
select t.check((select count(*) from profiles where id = t.id('f')) = 0, 'a trainee cannot read another trainee''s profile');
select t.check((select count(*) from coach_load) = 0, 'coach_load is admin-only (security_invoker)');

select t.login('coach1');
select t.check(t.fails($$insert into coach_assignments (coach_id, trainee_id, scope_id) values (auth.uid(), t.id('x'), 1)$$),
               'a coach cannot assign himself to a trainee');
select t.check(t.fails($$update profiles set gender = 'female' where id = auth.uid()$$),
               'a coach cannot change his gender to pass the image rule');

-- Chat
select t.login('f');
select t.check(t.fails($$insert into messages (conversation_id, sender_id, body)
                         select id, t.id('coach1'), 'spoofed' from conversations where coach_id = t.id('coach1')$$),
               'a participant cannot send as the other person');
select t.check(not t.fails($$insert into messages (conversation_id, sender_id, body)
                             select id, auth.uid(), 'hi coach' from conversations where coach_id = t.id('coach1')$$),
               'a participant can send as themselves (conversation created on assignment)');
select t.check(t.fails($$insert into messages (conversation_id, sender_id, body)
                         select id, auth.uid(), '   ' from conversations where coach_id = t.id('coach1')$$),
               'chat is text only: an empty message is rejected');
select t.check(not exists (select 1 from information_schema.columns
                           where table_name = 'messages' and column_name = 'image_path'),
               'chat has no attachment column (B13)');
select t.check(t.fails($$insert into conversations (coach_id, trainee_id) values (t.id('x'), auth.uid())$$),
               'users cannot open conversations themselves');
select t.login('coach1');
select t.check(t.fails($$update messages set body = 'edited' where sender_id = t.id('f')$$),
               'nobody can edit a message body');
update messages set read_at = now() where sender_id = t.id('f');
select t.check((select count(*) from messages where read_at is not null) = 1, 'the recipient can mark a message read');
delete from messages;
select t.check((select count(*) from messages) = 1, 'messages cannot be deleted');
reset role;

-- =====================================================================
-- 2. Approval (B6) and coach scope (B5)
-- =====================================================================
set role authenticated;
select t.login('x');
insert into applications (user_id, role_id) select auth.uid(), id from roles where key = 'trainee';
select t.login('f');
insert into applications (user_id, role_id) select auth.uid(), id from roles where key = 'trainee';
select t.fails($$update applications set status = 'approved'$$);
select t.check(not exists (select 1 from applications where status = 'approved'),
               'an applicant cannot approve themselves');
select t.check(t.fails($$insert into workout_sessions (trainee_id, workout_day_id, session_date)
                         select auth.uid(), id, t.today() from workout_days limit 1$$),
               'a pending trainee cannot log workouts');

select t.login('admin');
select t.check(t.fails($$update applications set status = 'approved' where user_id = t.id('x')$$),
               'a trainee with no coach cannot be approved');
update applications set status = 'approved' where user_id = t.id('f');
select t.check(exists (select 1 from user_roles ur join roles r on r.id = ur.role_id
                       where ur.user_id = t.id('f') and r.key = 'trainee'),
               'approving grants the trainee role');
insert into applications (user_id, role_id) select auth.uid(), id from roles where key = 'coach';
select t.check(t.fails($$update applications set status = 'approved' where user_id = auth.uid()$$),
               'an admin cannot approve their own application');

select t.login('f');
select t.check(exists (select 1 from notifications where type_key = 'application_result'),
               'the applicant is notified of the decision');
select t.check(exists (select 1 from notifications where type_key = 'plan_ready' and title is null),
               'plan_ready notifications are stored without text (rendered in the reader''s language)');

select t.login('coach2');   -- nutrition coach
select t.check((select count(*) from workout_days d join workout_plan_versions v on v.id = d.version_id
                join workout_plans p on p.id = v.plan_id where p.trainee_id = t.id('f')) = 3,
               'a nutrition coach can read the trainee''s workout plan');
select t.fails($$update workout_days set name = 'Hacked' where name = 'Push'$$);
select t.check(not exists (select 1 from workout_days where name = 'Hacked'),
               'a nutrition coach cannot edit the workout plan');
select t.login('coach1');   -- workout coach
update workout_days set name = 'Push A'
where name = 'Push' and version_id in (
  select v.id from workout_plan_versions v join workout_plans p on p.id = v.plan_id where p.trainee_id = t.id('f'));
select t.check(exists (select 1 from workout_days where name = 'Push A'),
               'the workout coach can edit the workout plan');
select t.check(t.fails($$insert into meals (version_id, name, sort_order)
                         select v.id, 'Extra', 9 from nutrition_plan_versions v join nutrition_plans p on p.id = v.plan_id
                         where p.trainee_id = t.id('f')$$),
               'the workout coach cannot edit the nutrition plan');
reset role;

-- =====================================================================
-- 3. Workout cycle (B1), logging, edit window, versions
-- =====================================================================
set role authenticated;
select t.login('f');
select t.check((select day_number from next_workout_day()) = 1, 'nothing logged yet: suggests Day 1');

insert into workout_sessions (trainee_id, workout_day_id, session_date)
select auth.uid(), d.id, t.today() - 1 from workout_days d join workout_plan_versions v on v.id = d.version_id
join workout_plans p on p.id = v.plan_id where p.trainee_id = auth.uid() and d.day_number = 2;
select t.check((select is_planned_rest and day_number = 3 from next_workout_day()),
               'Day 2 yesterday: today is the planned rest day 3');

update workout_sessions set session_date = t.today() - 2 where trainee_id = auth.uid();
select t.check((select day_number from next_workout_day()) = 4,
               'Day 2 two days ago: yesterday used up the planned rest, today is Day 4');

insert into workout_sessions (trainee_id, workout_day_id, session_date)
select auth.uid(), d.id, t.today() - 4 from workout_days d join workout_plan_versions v on v.id = d.version_id
join workout_plans p on p.id = v.plan_id where p.trainee_id = auth.uid() and d.day_number = 1;
update workout_sessions set session_date = t.today() - 1
where trainee_id = auth.uid() and session_date = t.today() - 2;
select t.check((select is_planned_rest from next_workout_day()),
               'resting is always allowed; the suggestion just waits');

insert into workout_sessions (trainee_id, workout_day_id, session_date)
select auth.uid(), d.id, t.today() from workout_days d join workout_plan_versions v on v.id = d.version_id
join workout_plans p on p.id = v.plan_id where p.trainee_id = auth.uid() and d.day_number = 4;
select t.check((select logged_today and day_number = 4 from next_workout_day()),
               'training on a planned rest day is allowed: any day of the plan can be logged');

insert into set_logs (session_id, day_exercise_id, exercise_id, set_number, reps, weight_kg)
select s.id, e.id, e.exercise_id, 1, 10, 60
from workout_sessions s join workout_days d on d.version_id = (select version_id from workout_days where id = s.workout_day_id)
join workout_day_exercises e on e.day_id = d.id
where s.trainee_id = auth.uid() and s.session_date = t.today() - 4 and d.day_number = 1
  and e.exercise_id = (select id from exercises where name_en = 'Bench Press');
select t.check(t.fails($$insert into set_logs (session_id, day_exercise_id, exercise_id, set_number, reps)
                         select s.id, e.id, e.exercise_id, 1, 10 from workout_sessions s, workout_day_exercises e
                         where s.session_date = t.today() and e.exercise_id = (select id from exercises where name_en = 'Treadmill')$$),
               'a set must belong to the session''s workout day');
select t.check(t.fails($$insert into set_logs (session_id, day_exercise_id, exercise_id, set_number)
                         select s.id, e.id, e.exercise_id, 2 from workout_sessions s
                         join workout_day_exercises e on e.day_id = s.workout_day_id
                         where s.session_date = t.today() - 4 limit 1$$),
               'a set needs reps, a duration or a distance');
insert into set_logs (session_id, day_exercise_id, exercise_id, set_number, duration_seconds, distance_m)
select s.id, e.id, e.exercise_id, 1, 1500, 3200
from workout_sessions s join workout_day_exercises e on e.day_id = s.workout_day_id
where s.trainee_id = auth.uid() and s.session_date = t.today() - 4
  and e.exercise_id = (select id from exercises where name_en = 'Treadmill');
select t.check((select duration_seconds = 1500 and distance_m = 3200 from last_weights(auth.uid(),
                  (select id from exercises where name_en = 'Treadmill'))),
               'cardio logs time and distance (B8), and last_weights pre-fills them');
select t.check((select weight_kg = 60 from last_weights(auth.uid(), (select id from exercises where name_en = 'Bench Press'))),
               'last_weights pre-fills the bench press weight');
select t.check((select session_date = t.today() - 4 and trainee_id = auth.uid() from set_logs limit 1),
               'set_logs copy trainee and date from the session');

select t.check(t.fails($$insert into workout_sessions (trainee_id, workout_day_id, session_date)
                         select auth.uid(), id, t.today() - 8 from workout_days limit 1$$),
               'logs older than 7 local days are locked');
select t.check(private.local_today(auth.uid()) = t.today(), 'today is the trainee''s local (Cairo) date, not UTC');
select t.check(t.fails($$update profiles set timezone = 'Mars/Olympus' where id = auth.uid()$$),
               'an unknown timezone is rejected');

select t.login('coach1');
select t.check(t.fails($$update workout_day_exercises set sets = 5 where day_id in (
                         select d.id from workout_days d join workout_plan_versions v on v.id = d.version_id
                         join workout_plans p on p.id = v.plan_id where p.trainee_id = t.id('f'))$$),
               'a version with logs is frozen');
select t.check(copy_workout_version(
                 (select v.id from workout_plan_versions v join workout_plans p on p.id = v.plan_id where p.trainee_id = t.id('f')),
                 (select id from workout_plans where trainee_id = t.id('f')), t.today()) is not null,
               'copy_workout_version makes a new editable version');
select t.check(not t.fails($$update workout_day_exercises set sets = 5 where day_id in (
                             select d.id from workout_days d join workout_plan_versions v on v.id = d.version_id
                             join workout_plans p on p.id = v.plan_id where p.trainee_id = t.id('f') and v.version_no = 2)$$),
               'the new version can be edited');
select t.check((select version_no from workout_plan_versions where id = (select version_id from next_workout_day(t.id('f')))) = 1,
               'today''s session keeps pointing at the version it was logged under');
select t.check(t.fails($$insert into workout_plans (trainee_id, name) values (t.id('f'), 'Second plan')$$),
               'a trainee has at most one active workout plan');
select t.check(t.fails($$insert into workout_days (version_id, day_number, name)
                         select v.id, 9, 'Day 9' from workout_plan_versions v join workout_plans p on p.id = v.plan_id
                         where p.trainee_id = t.id('f') and v.version_no = 2$$),
               'day numbers must fit the cycle length');
reset role;

-- =====================================================================
-- 4. Streak (rules in current_streak)
-- =====================================================================
select t.login('admin');
select t.log_day('s1', -o, true, 0) from generate_series(0, 9) o;
select t.check(current_streak(t.id('s1')) = 10, 'workout-only trainee: 10 training days = streak 10 (was 0 in v2)');

select t.log_day('s2', -21, true, 2);
select t.log_day('s2', -o, false, 2) from generate_series(0, 20) o;
select t.check(current_streak(t.id('s2')) = 0, '20 rest days after training: streak is broken (v2 returned 14)');

select t.log_day('s3', -o, true, case when o in (5, 2) then 1 else 2 end) from generate_series(0, 9) o;
select t.check(current_streak(t.id('s3')) = 2, 'first missed day forgiven, second resets: 4 + 2 -> reset -> 2');

select t.log_day('s4', -o, true, 2) from generate_series(1, 3) o;
select t.check(current_streak(t.id('s4')) = 3, 'today not done yet does not break the streak');
select t.log_day('s4', 0, false, 3);
select t.check(current_streak(t.id('s4')) = 4, 'the optional snack is not needed; today counts once meals are done');

-- =====================================================================
-- 5. Milestones (B18) and the female image rule
-- =====================================================================
set role authenticated;
select t.login('f');
select t.check(not t.fails($$insert into milestones (trainee_id, due_date, title) values (auth.uid(), t.today(), 'Sign-up weight')$$),
               'a trainee can save the sign-up weight as a milestone (v2 had no insert policy)');
insert into milestone_values (milestone_id, field_id, number_value)
select m.id, f.id, 74.0 from milestones m, milestone_fields f where m.title = 'Sign-up weight' and f.key = 'weight';
update milestones set submitted_at = now() where title = 'Sign-up weight';

select t.login('coach1');
insert into milestones (trainee_id, due_date, title) values (t.id('f'), t.today(), 'Mid-cut check');
insert into milestone_request_fields (milestone_id, field_id)
select m.id, f.id from milestones m, milestone_fields f where m.title = 'Mid-cut check' and f.key in ('weight', 'photo_front');
insert into milestone_schedules (trainee_id, name, every_n_days, starts_on)
values (t.id('f'), 'Bi-weekly', 14, t.today() - 14);
insert into milestone_schedule_fields (schedule_id, field_id)
select s.id, f.id from milestone_schedules s, milestone_fields f where f.key = 'weight';
reset role;

select t.check(private.generate_due_milestones() = 1, 'the scheduler creates the milestone due today');
select t.check(private.generate_due_milestones() = 0, 'and does not create it twice');

set role authenticated;
select t.login('f');
insert into milestone_values (milestone_id, field_id, number_value)
select m.id, f.id, 72.4 from milestones m, milestone_fields f where m.title = 'Mid-cut check' and f.key = 'weight';
select t.check(t.fails($$update milestones set submitted_at = now() where title = 'Mid-cut check'$$),
               'submitting with a required field missing is rejected');
select t.check(t.fails($$insert into milestone_values (milestone_id, field_id, number_value)
                         select m.id, f.id, 1 from milestones m, milestone_fields f
                         where m.title = 'Mid-cut check' and f.key = 'photo_front'$$),
               'an image field needs an image, not a number');
insert into milestone_values (milestone_id, field_id, image_path)
select m.id, f.id, auth.uid() || '/front.jpg' from milestones m, milestone_fields f
where m.title = 'Mid-cut check' and f.key = 'photo_front';
update milestones set submitted_at = now() where title = 'Mid-cut check';

select t.login('coach1');   -- male
select t.check(exists (select 1 from notifications where type_key = 'milestone_uploaded'),
               'the coach is notified when a milestone is submitted');
select t.check((select count(*) from milestone_values where image_path is not null) = 0
               and (select count(*) from milestone_values where number_value is not null) = 2,
               'a male coach sees the female trainee''s weight but not her photos');
select t.login('coach2');   -- female
select t.check((select count(*) from milestone_values where image_path is not null) = 1,
               'a female coach sees the photos');
reset role;

insert into storage.objects (bucket_id, name) values ('milestone-images', t.id('f') || '/front.jpg');
set role authenticated;
select t.login('coach1');
select t.check((select count(*) from storage.objects) = 0, 'storage: a male coach cannot open her photo file');
select t.login('coach2');
select t.check((select count(*) from storage.objects) = 1, 'storage: a female coach can');
select t.login('admin');    -- male admin
select t.check((select count(*) from storage.objects) = 0, 'storage: a male admin cannot');
reset role;

-- =====================================================================
-- 6. Notifications (B14), reminders (B7), foods (B10), search
-- =====================================================================
set role authenticated;
select t.login('coach1');
select t.check(not t.fails($$insert into notifications (recipient_id, type_key, title, sent_by)
                             values (t.id('f'), 'custom', 'Great week!', auth.uid())$$),
               'a coach can notify their own trainee');
select t.check(t.fails($$insert into notifications (recipient_id, type_key, title, sent_by)
                         values (t.id('x'), 'custom', 'Join me', auth.uid())$$),
               'a coach cannot notify someone else''s trainee');
select t.login('admin');
select t.check(not t.fails($$insert into notifications (recipient_id, type_key, title, sent_by)
                             values (t.id('x'), 'custom', 'Welcome', auth.uid())$$),
               'an admin can notify anyone');

select t.login('f');
select t.check((select at_time from my_reminders() where kind = 'workout') = '18:00', 'workout reminder defaults to 18:00');
select t.check((select at_time from my_reminders() where kind = 'meal' and meal_slot = 1) = '08:00',
               'meal 1 defaults to the plan''s time hint');
select t.check((select at_time from my_reminders() where kind = 'meal' and meal_slot = 2) = '14:00',
               'meal 2 has no time hint, so it uses the sign-up answer');
insert into reminder_settings (user_id, kind, meal_slot, at_time) values (auth.uid(), 'meal', 1, '07:30');
select t.check((select at_time = '07:30' and not is_default from my_reminders() where kind = 'meal' and meal_slot = 1),
               'a reminder set per meal overrides the default');
select t.check((select count(*) from my_reminders() where kind = 'meal') = 3, 'one reminder per meal');

select t.login('coach2');
insert into foods (name_en, name_ar, source, kcal, protein_g, carbs_g, fat_g)
values ('Baladi bread', 'عيش بلدي', 'custom', 250, 9, 50, 1.5),
       ('Rice', 'أرز', 'custom', 130, 2.7, 28, 0.3);
insert into food_units (food_id, name_en, name_ar, grams)
select id, 'loaf', 'رغيف', 90 from foods where name_en = 'Baladi bread';
insert into meal_option_items (option_id, food_id, quantity, unit_id, grams)
select o.id, f.id, 2, u.id, 1
from meal_options o join meals m on m.id = o.meal_id join nutrition_plan_versions v on v.id = m.version_id
join nutrition_plans p on p.id = v.plan_id, foods f join food_units u on u.food_id = f.id
where p.trainee_id = t.id('f') and m.name = 'Lunch' and f.name_en = 'Baladi bread';
select t.check((select grams from meal_option_items) = 180, '2 loaves are stored as 180 g (B10)');
insert into meal_option_items (option_id, food_id, quantity, grams)
select o.id, f.id, 150, 1
from meal_options o join meals m on m.id = o.meal_id join nutrition_plan_versions v on v.id = m.version_id
join nutrition_plans p on p.id = v.plan_id, foods f
where p.trainee_id = t.id('f') and m.name = 'Lunch' and f.name_en = 'Rice';
select t.check((select grams from meal_option_items where quantity = 150) = 150, 'a plain quantity is grams');
select t.check(t.fails($$update foods set kcal = 300 where name_en = 'Rice'$$),
               'a food used in a plan keeps its values');
select t.check((select name_en from search_foods('ارز') limit 1) = 'Rice', 'Arabic search ignores hamza (ارز finds أرز)');
select t.check((select name_en from search_foods('عيش') limit 1) = 'Baladi bread', 'Arabic search finds عيش بلدي');
select t.check((select name_en from match_exercise('bench pres') limit 1) = 'Bench Press', 'match_exercise: "bench pres" -> Bench Press');
reset role;

-- =====================================================================
-- 7. Subscriptions and earnings (B4, B15)
-- =====================================================================
set role authenticated;
select t.login('admin');
insert into subscriptions (trainee_id, coach_id, amount_egp, starts_on, ends_on)
values (t.id('f'), t.id('coach1'), 2500, '2026-11-01', '2027-01-31');
insert into subscriptions (trainee_id, coach_id, amount_egp, starts_on, ends_on)
values (t.id('m'), t.id('coach1'), 1000, t.today() - 84, t.today() + 5);
select t.check((select sum(amount_egp) from coach_earnings('2026-11-01', '2026-11-30') where trainee_id = t.id('f')) = 833.33,
               'November share of 2,500 EGP over 3 months = 833.33 (B4: per month)');
select t.check((select sum(amount_egp) from coach_earnings('2027-01-01', '2027-01-31') where trainee_id = t.id('f')) = 833.34,
               'the last month takes the rounding remainder');
select t.check((select sum(amount_egp) from coach_earnings('2026-11-01', '2027-01-31') where trainee_id = t.id('f')) = 2500.00,
               'the full period adds up to exactly 2,500.00');

select t.login('m');
select t.check((select days_left = 6 and status = 'ending_soon' from subscription_status), 'the trainee sees 6 days left');
select t.check((select count(*) from coach_earnings('2000-01-01', '2100-01-01')) = 1,
               'a trainee sees only their own subscription');
select t.check(exists (select 1 from notifications where type_key = 'subscription_recorded'
                       and (data->>'amount_egp')::numeric = 1000),
               'the trainee is told the payment was recorded');
select t.login('coach2');
select t.check((select count(*) from coach_earnings('2000-01-01', '2100-01-01')) = 0,
               'a coach does not see other coaches'' earnings');
reset role;

select t.check(private.notify_ending_subscriptions(7) = 1, 'one subscription is ending within 7 days');
select t.check(private.notify_ending_subscriptions(7) = 0, 'the heads-up is sent once');
select t.check((select count(*) from notifications where type_key = 'subscription_ending') = 2,
               'the heads-up goes to the trainee and the admin');

-- =====================================================================
-- 8. Coach dashboard (B19), consent and account deletion (B16)
-- =====================================================================
set role authenticated;
select t.login('coach1');
select t.check((select count(*) from coach_dashboard()) = 2, 'coach dashboard lists the coach''s active trainees');
select t.check((select trained_today and milestones_due = 1 from coach_dashboard() where trainee_id = t.id('f')),
               'dashboard shows trained today and the due bi-weekly milestone');

select t.login('m');
insert into consents (user_id, kind, version) values (auth.uid(), 'health_data', '2026-10');
select t.check(t.fails($$insert into consents (user_id, kind, version) values (t.id('f'), 'terms', '1')$$),
               'consent can only be given for yourself');
select delete_my_account();
reset role;

select t.check(not exists (select 1 from profiles where id = t.id('m')), 'account deletion removes the profile');
select t.check(not exists (select 1 from workout_sessions where trainee_id = t.id('m'))
               and not exists (select 1 from workout_plans where trainee_id = t.id('m')),
               'and the trainee''s plans and logs');
select t.check(exists (select 1 from subscriptions where trainee_id is null and amount_egp = 1000),
               'the subscription stays for the earnings history');

set role authenticated;
select t.login('coach1');
select delete_my_account();
reset role;
select t.check((select count(*) from workout_plans where trainee_id = t.id('f')) = 1,
               'deleting a coach keeps their trainees'' plans');

\echo 'ALL TESTS PASSED'
