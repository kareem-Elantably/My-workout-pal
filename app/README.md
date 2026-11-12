# Fitness App (Flutter)

One app for trainees, coaches and admins, backed by the Supabase project in
`../supabase`. Arabic (right-to-left) and English.

> "Fitness App" and `com.myworkoutpal.fitnessapp` are placeholders until the
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

**Email links** (confirm sign-up, reset password) open the app. Supabase only
sends users to allowed addresses, so add this under **Authentication -> URL
Configuration -> Redirect URLs**:

```
com.myworkoutpal.fitnessapp://auth-callback
```

Only the **publishable** key belongs in the app; access is enforced by
row-level security. Never put the secret key or the database password here.

## What's in the app

**Trainee** (tabs: Today, Plan, Progress, Chat, More)
- Today: the suggested workout day (or any other day, or rest), meals with
  the option eaten and a "did you change anything?" note, "all done", the
  streak, due check-ins. Arrows go back 7 days, the edit window.
- Workout logging: sets pre-filled from last time, +/- steppers (hold to
  repeat), one tap per set, rest timer, cardio by distance and time.
- Plan (read-only), progress charts (weight, best set per exercise),
  check-ins with photos (private; female image rule), realtime text chat,
  notifications inbox, reminders (on the phone, one per meal, defaults),
  meal converter, private notes, subscription days left, delete account.

**Coach** (tabs: Trainees, Chat, Library, Earnings, More)
- Trainees sorted by who needs attention; a trainee page with prev/next,
  chat, custom notification, overview and sign-up answers, plans, progress
  with compare and check-in schedules, logs, private notes.
- Workout and nutrition editors are the main way to build plans: start
  from scratch or a template, then add, edit, reorder, duplicate, replace
  or delete exercises, days and meals. Edits save straight away. Once the
  trainee has logged against the plan, the first edit makes a new version
  from today on its own, so past workouts keep what was really done.
  Templates: apply to a trainee, save as.
- Excel upload (a shortcut): template download, preview, error rows, names
  matched to the library ("did you mean...?" saves the spelling as an alias).
- Library: exercises (876 seeded), foods (76 seeded, units like "loaf"),
  barcode scan via Open Food Facts. Earnings by trainee for any range.
- A food that isn't in the library: "Add it" right in the food search
  (name pre-filled, values per 100 g, optional unit) or scan its barcode;
  it goes straight into the meal and stays in the library. Trainees are
  told to ask their coach.

**Admin** (tabs: Applications, People, Subscriptions, More)
- Review sign-ups (answers, certificates, assign coaches, approve/reject).
- People with roles and coach load; assign or end coaches; send a
  notification to anyone. Subscriptions: record or edit payments, ending
  soon / active / ended. Earnings by coach.

**Everyone**: Arabic/English, push notifications (Firebase), email links
that open the app (confirm sign-up, reset password).

Not yet: offline sync (PowerSync), animations (Rive/Lottie).

### Push notifications

Pushes are sent by the `send-push` Edge Function. It needs one secret:
**Supabase -> Edge Functions -> Secrets -> `FCM_SERVICE_ACCOUNT`** = the
whole JSON from **Firebase -> Project settings -> Service accounts ->
Generate new private key**. Firebase app IDs are in
`lib/core/firebase_options.dart`.

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
- the app ID (same on both platforms): `applicationId` and `namespace` in
  `android/app/build.gradle.kts` (and the Kotlin package folder), and
  `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`
- the email-link scheme, which follows the app ID: `Env.authCallback`, the
  intent filter in `AndroidManifest.xml`, `CFBundleURLSchemes` in
  `Info.plist`, and the redirect URL in Supabase (below)

Do this before setting up Firebase, which registers the app ID.
