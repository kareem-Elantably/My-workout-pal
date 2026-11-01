# Fitness App (Flutter)

One app for trainees, coaches and admins, backed by the Supabase project in
`../supabase`. Arabic (right-to-left) and English.

> "Fitness App" and `com.myworkoutpal.fitness_app` are placeholders until the
> final name is chosen. See "Renaming" below.

## Run it

```bash
flutter pub get          # also generates the translations
flutter run              # on a connected phone or emulator
flutter test
flutter analyze
```

The app connects to the Supabase project by default. To use a different
project:

```bash
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Only the **publishable** key belongs in the app; access is enforced by
row-level security. Never put the secret key or the database password here.

## What works so far

- Welcome screen with separate trainee and coach entry points, and a language switch.
- Sign-up (profile info, consents) and log-in.
  - If email confirmation is on, the app shows "check your email".
  - Weight and consents are kept in the sign-up metadata until onboarding is submitted.
- Sign-up questions loaded from the database, one section per step, saved per step so the user can resume.
  - Supports text, number (Arabic digits too), yes/no, date, single and multiple choice, and one time per meal.
- Coach certificates, uploaded to the private `certificates` bucket.
- Waiting for approval. It checks again when the app comes back to the foreground. After a rejection the user can apply again.
- Admin review:
  - pending applications and the applicant's answers
  - certificates, opened through short-lived links
  - assigning workout and nutrition coaches
  - approve or reject
- Homes:
  - trainee: today's suggested workout and the streak, or "plans are being prepared"
  - coach: trainees sorted by who needs attention
  - admin: applications
- Profile: language, role switcher for people with several roles, sign out.

## Layout

```
lib/
  core/       env, models, Riverpod providers, shared UI
  data/       repositories, the only code that talks to Supabase
  router/     go_router setup; redirect.dart decides where each user belongs
  features/   auth, onboarding, home, admin screens
  l10n/       app_en.arb, app_ar.arb (generated code goes to l10n/gen)
  theme/      dark blue + one accent colour, light and dark
test/         routing rules, question fields, app flows with mocked repositories
```

## Renaming

Change these, then run `flutter clean`:

- the display name: `appName` in both `.arb` files, `android:label` in
  `android/app/src/main/AndroidManifest.xml`, `CFBundleDisplayName` in
  `ios/Runner/Info.plist`
- the app ID: `applicationId` and `namespace` in `android/app/build.gradle.kts`
  (and the Kotlin package folder), and `PRODUCT_BUNDLE_IDENTIFIER` in
  `ios/Runner.xcodeproj/project.pbxproj`

Do this before setting up Firebase, which registers the app ID.
