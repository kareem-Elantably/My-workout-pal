-- =====================================================================
-- Water: how much the trainee drank each day, against a daily goal.
-- One row per trainee per day holding the day's total (the app adds a
-- glass at a time). Same rules as meal logs: the trainee writes their
-- own days within the 7-day edit window; their coaches and admins read.
-- =====================================================================

create table water_logs (
  trainee_id  uuid not null references profiles(id) on delete cascade,
  log_date    date not null,
  ml          int not null check (ml between 0 and 20000),
  updated_at  timestamptz not null default now(),
  primary key (trainee_id, log_date)
);

create trigger touch_updated_at before update on water_logs
  for each row execute function private.touch_updated_at();

alter table water_logs enable row level security;

create policy water_logs_read on water_logs for select to authenticated
  using (private.can_view_trainee(trainee_id));
create policy water_logs_write on water_logs for all to authenticated
  using (trainee_id = (select auth.uid()) and private.within_edit_window(trainee_id, log_date))
  with check (trainee_id = (select auth.uid()) and (select private.has_role('trainee'))
              and private.within_edit_window(trainee_id, log_date));

grant select, insert, update, delete on water_logs to authenticated;

-- The daily goal, which the trainee can change (2.5 L until they do).
alter table profiles
  add column water_goal_ml int not null default 2500 check (water_goal_ml between 500 and 10000);
grant update (water_goal_ml) on profiles to authenticated;
