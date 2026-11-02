/// Build-time configuration. Override with --dart-define, e.g.
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co
///
/// The publishable key is meant to ship inside the app; access is enforced
/// by row-level security in the database. Never put a secret key here.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ycmtyekrqwegyajhpuda.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_EBLOA9S-ufH1KZ6iXvW80A_pTcGjHB-',
  );

  /// Where email links (confirm sign-up, reset password) send the user: this
  /// opens the app. Must be listed under Supabase -> Authentication -> URL
  /// Configuration -> Redirect URLs, and match the Android intent filter and
  /// the iOS URL type. Change with the app ID.
  static const authCallback = 'com.myworkoutpal.fitnessapp://auth-callback';

  /// Version of the terms / privacy / health-data texts the user accepts.
  static const consentVersion = '2026-11';
}
