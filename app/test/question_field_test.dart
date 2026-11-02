import 'package:fitness_app/core/models.dart';
import 'package:fitness_app/features/auth/validators.dart';
import 'package:fitness_app/features/onboarding/question_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Question question(AnswerType type, {bool isRequired = true, num? min, num? max, List<QuestionOption> options = const []}) =>
    Question(
      id: 'q1',
      key: 'k',
      sectionId: 1,
      textEn: 'How many?',
      textAr: 'كام؟',
      type: type,
      isRequired: isRequired,
      min: min,
      max: max,
      options: options,
    );

/// A field in a form, with a button that validates it.
Widget harness(Question q, {Object? initial, ValueChanged<Object?>? onChanged, int? slots, Locale locale = const Locale('en')}) {
  final form = GlobalKey<FormState>();
  return localizedApp(
    Form(
      key: form,
      child: ListView(children: [
        QuestionField(question: q, value: initial, onChanged: onChanged ?? (_) {}, timeSlots: slots),
        TextButton(onPressed: () => form.currentState!.validate(), child: const Text('validate')),
      ]),
    ),
    locale: locale,
  );
}

void main() {
  group('parseNumber', () {
    test('reads Western and Arabic-Indic digits', () {
      expect(parseNumber('72.5'), 72.5);
      expect(parseNumber('٧٢٫٥'), 72.5);
      expect(parseNumber(' 7 '), 7);
      expect(parseNumber('abc'), isNull);
    });
  });

  testWidgets('a number answer is checked against the question range', (tester) async {
    Object? value;
    await tester.pumpWidget(harness(question(AnswerType.number, min: 1, max: 7), onChanged: (v) => value = v));

    await tester.tap(find.text('validate'));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '9');
    await tester.tap(find.text('validate'));
    await tester.pump();
    expect(find.text('Enter a number from 1 to 7'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '٣');
    await tester.tap(find.text('validate'));
    await tester.pump();
    expect(find.textContaining('Enter a number'), findsNothing);
    expect(value, 3);
  });

  testWidgets('a single choice shows the options in the UI language and stores the value', (tester) async {
    Object? value;
    final q = question(AnswerType.singleChoice, options: const [
      QuestionOption(value: 'low', labelEn: 'Low', labelAr: 'قليلة'),
      QuestionOption(value: 'high', labelEn: 'High', labelAr: 'عالية'),
    ]);
    await tester.pumpWidget(harness(q, onChanged: (v) => value = v, locale: const Locale('ar')));

    expect(find.text('كام؟'), findsOneWidget);
    await tester.tap(find.text('عالية'));
    await tester.pump();
    expect(value, 'high');
  });

  testWidgets('a time list asks for one time per meal', (tester) async {
    await tester.pumpWidget(harness(question(AnswerType.timeList), slots: 3, initial: const ['08:00']));

    expect(find.text('Meal 1'), findsOneWidget);
    expect(find.text('Meal 3'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('--:--'), findsNWidgets(2));

    await tester.tap(find.text('validate'));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget, reason: 'two meals have no time yet');
  });

  testWidgets('an optional question can stay empty', (tester) async {
    await tester.pumpWidget(harness(question(AnswerType.text, isRequired: false)));
    await tester.tap(find.text('validate'));
    await tester.pump();
    expect(find.text('Required'), findsNothing);
  });
}
