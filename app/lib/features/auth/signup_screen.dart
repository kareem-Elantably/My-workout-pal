import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/auth_repository.dart';
import '../../router/redirect.dart';
import 'validators.dart';

/// Basic info for either entry point. Trainees also give date of birth,
/// height and weight (the weight becomes their first milestone).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _phone = TextEditingController();
  String? _gender;
  DateTime? _dateOfBirth;
  bool _acceptTerms = false;
  bool _acceptHealthData = false;
  bool _busy = false;

  bool get _isTrainee => widget.role == AppRole.trainee;

  @override
  void dispose() {
    for (final controller in [_name, _email, _password, _height, _weight, _phone]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDateOfBirth(FormFieldState<DateTime> field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 10),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
      field.didChange(picked);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final form = SignUpForm(
      role: widget.role,
      email: _email.text,
      password: _password.text,
      fullName: _name.text.trim(),
      gender: _gender!,
      locale: ref.read(localeProvider).languageCode,
      dateOfBirth: _dateOfBirth,
      heightCm: parseNumber(_height.text),
      weightKg: parseNumber(_weight.text),
      phone: _phone.text.trim(),
      consents: ['terms', 'privacy', if (_isTrainee) 'health_data'],
    );
    try {
      final signedIn = await ref.read(authRepositoryProvider).signUp(form);
      // Signed in: the session listener moves on to the sign-up questions.
      if (!signedIn && mounted) {
        context.go(Uri(path: Routes.checkEmail, queryParameters: {'email': form.email}).toString());
      }
    } on AuthException catch (e) {
      if (mounted) e.statusCode == null ? showError(context, e) : showMessage(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dateFormat = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(title: Text(_isTrainee ? l10n.signupTraineeTitle : l10n.signupCoachTitle)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.fullName),
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.required : null,
              ),
              const SizedBox(height: 16),
              FormField<String>(
                validator: (_) => _gender == null ? l10n.required : null,
                builder: (field) => InputDecorator(
                  decoration: InputDecoration(labelText: l10n.gender, errorText: field.errorText),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'male', label: Text(l10n.male), icon: const Icon(Icons.male)),
                      ButtonSegment(value: 'female', label: Text(l10n.female), icon: const Icon(Icons.female)),
                    ],
                    selected: {?_gender},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (selection) {
                      setState(() => _gender = selection.firstOrNull);
                      field.didChange(_gender);
                    },
                  ),
                ),
              ),
              if (_isTrainee) ...[
                const SizedBox(height: 16),
                FormField<DateTime>(
                  validator: (_) => _dateOfBirth == null ? l10n.required : null,
                  builder: (field) => InkWell(
                    onTap: () => _pickDateOfBirth(field),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.dateOfBirth,
                        errorText: field.errorText,
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(_dateOfBirth == null ? l10n.pickDate : dateFormat.format(_dateOfBirth!)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _height,
                        decoration: InputDecoration(labelText: l10n.heightCm),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) => validateNumber(context, value, required: true, min: 100, max: 250),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _weight,
                        decoration: InputDecoration(labelText: l10n.weightKg),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) => validateNumber(context, value, required: true, min: 30, max: 300),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(labelText: l10n.phone),
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: l10n.email),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                validator: (value) => validateEmail(context, value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.password, helperText: l10n.passwordHint),
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => validatePassword(context, value),
              ),
              const SizedBox(height: 16),
              _ConsentCheckbox(
                label: l10n.acceptTerms,
                value: _acceptTerms,
                onChanged: (value) => setState(() => _acceptTerms = value),
              ),
              if (_isTrainee)
                _ConsentCheckbox(
                  label: l10n.acceptHealthData,
                  value: _acceptHealthData,
                  onChanged: (value) => setState(() => _acceptHealthData = value),
                ),
              const SizedBox(height: 24),
              BusyButton(label: l10n.createAccount, busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FormField<bool>(
        validator: (_) => value ? null : context.l10n.mustAccept,
        builder: (field) => CheckboxListTile(
          value: value,
          onChanged: (checked) {
            onChanged(checked ?? false);
            field.didChange(checked);
          },
          title: Text(label),
          subtitle: field.errorText == null
              ? null
              : Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      );
}
