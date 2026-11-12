-- =====================================================================
-- Mobile number is required for everyone.
-- The app asks for it at sign-up and won't let it be cleared; this keeps
-- every other path (dashboard, API, future clients) to the same rule.
-- Every existing profile already has one.
-- Accounts created by hand in the Supabase dashboard need "phone" in the
-- user metadata, like "full_name" and "gender".
-- =====================================================================

alter table profiles
  alter column phone set not null,
  add constraint profiles_phone_present check (length(btrim(phone)) > 0);
