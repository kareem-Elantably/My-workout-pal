import 'package:fitness_app/app.dart';
import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/data/auth_repository.dart';
import 'package:fitness_app/features/auth/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository auth;

  setUp(() => auth = MockAuthRepository());

  Future<void> pumpSignedOut(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionProvider.overrideWith(() => FakeSessionNotifier(const SignedOut())),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: const FitnessApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('log in and sign up link to each other, and back always returns to welcome', (tester) async {
    await pumpSignedOut(tester);

    await tapText(tester, 'I already have an account');
    expect(find.text('Log in'), findsWidgets);
    await tapText(tester, 'New here? Create an account');
    expect(find.text('I want a coach'), findsOneWidget);

    await tapText(tester, 'I want a coach');
    await tapText(tester, 'Already have an account? Log in');
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('I want a coach'), findsOneWidget);
  });

  testWidgets('forgot password opens its own screen with the email filled in, and sends the link', (tester) async {
    when(() => auth.sendPasswordReset(any())).thenAnswer((_) async {});
    await pumpSignedOut(tester);
    await tapText(tester, 'I already have an account');

    await tester.enterText(find.byType(TextFormField).first, 'sara@example.com');
    await tapText(tester, 'Forgot password?');
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'sara@example.com'), findsOneWidget);

    await tapText(tester, 'Send link');
    verify(() => auth.sendPasswordReset('sara@example.com')).called(1);
    expect(find.textContaining("we've sent it a link"), findsOneWidget);

    await tapText(tester, 'Back to log in');
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('sign-up requires a valid mobile number', (tester) async {
    await pumpSignedOut(tester);
    await tapText(tester, "I'm a coach");

    await tapText(tester, 'Create account');
    final phoneField = find.widgetWithText(TextFormField, 'Mobile number');
    expect(find.descendant(of: phoneField, matching: find.text('Required')), findsOneWidget);

    await tester.enterText(phoneField, '123');
    await tapText(tester, 'Create account');
    expect(find.textContaining('Enter a valid mobile number'), findsOneWidget);
  });

  testWidgets('the password can be shown', (tester) async {
    await pumpSignedOut(tester);
    await tapText(tester, 'I already have an account');
    EditableText password() => tester.widget<EditableText>(find.byType(EditableText).last);

    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
  });

  group('normalizePhone', () {
    test('accepts Egyptian mobiles typed locally, with spaces or Arabic digits', () {
      expect(normalizePhone('01012345678'), '+201012345678');
      expect(normalizePhone('010 1234 5678'), '+201012345678');
      expect(normalizePhone('٠١٠١٢٣٤٥٦٧٨'), '+201012345678');
    });

    test('accepts international numbers', () {
      expect(normalizePhone('+971501234567'), '+971501234567');
      expect(normalizePhone('00971501234567'), '+971501234567');
    });

    test('rejects anything else', () {
      expect(normalizePhone('123'), isNull);
      expect(normalizePhone('01312345678'), isNull, reason: 'not an Egyptian mobile prefix');
      expect(normalizePhone('abc'), isNull);
    });
  });
}
