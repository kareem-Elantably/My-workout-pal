import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';

class SignUpForm {
  const SignUpForm({
    required this.role,
    required this.email,
    required this.password,
    required this.fullName,
    required this.gender,
    required this.locale,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.phone,
    this.consents = const [],
  });

  final AppRole role;
  final String email;
  final String password;
  final String fullName;
  final String gender;
  final String locale;
  final DateTime? dateOfBirth;
  final num? heightCm;
  final num? weightKg;
  final String? phone;

  /// Consent kinds accepted on the form: terms, privacy, health_data.
  final List<String> consents;

  /// Read by the database's sign-up trigger (profile fields) and by
  /// onboarding (role, weight, consents) once the user is signed in.
  Map<String, dynamic> toMetadata() => {
        'full_name': fullName,
        'gender': gender,
        'locale': locale,
        'signup_role': role.name,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth!.toIso8601String().substring(0, 10),
        if (heightCm != null) 'height_cm': heightCm,
        if (weightKg != null) 'weight_kg': weightKg,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        'consents': consents,
      };
}

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  /// Returns true when the user is signed in straight away, false when the
  /// project requires email confirmation first.
  Future<bool> signUp(SignUpForm form) async {
    final response = await _client.auth.signUp(
      email: form.email.trim(),
      password: form.password,
      data: form.toMetadata(),
    );
    return response.session != null;
  }

  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() => _client.auth.signOut();
}
