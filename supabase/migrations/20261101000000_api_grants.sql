-- =====================================================================
-- API grants. Newer Supabase projects don't grant new tables to the API
-- roles automatically, so the app's signed-in role ("authenticated") had
-- no access at all. Grant it explicitly; row-level security (on for every
-- table) still decides which rows each user sees. "anon" gets nothing:
-- sign-up and log-in go through Supabase Auth, not these tables.
-- =====================================================================

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Access helpers used inside policies, views and triggers.
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

-- Objects created by later migrations get the same grants.
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;
alter default privileges in schema public grant execute on functions to authenticated;
alter default privileges in schema private grant execute on functions to authenticated;

-- Column-level limits from the initial schema, re-applied after the
-- table-wide grant above: users can't change their own gender, and
-- messages and notifications can only be marked read.
revoke update on profiles from authenticated;
grant update (full_name, date_of_birth, height_cm, phone, avatar_path, locale, timezone) on profiles to authenticated;
revoke update on messages from authenticated;
grant update (read_at) on messages to authenticated;
revoke update on notifications from authenticated;
grant update (read_at) on notifications to authenticated;
