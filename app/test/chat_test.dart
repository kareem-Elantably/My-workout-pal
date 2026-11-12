import 'package:fitness_app/core/providers.dart';
import 'package:fitness_app/data/social_repository.dart';
import 'package:fitness_app/features/shared/chat_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late Mocks mocks;

  setUpAll(registerFallbacks);
  setUp(() => mocks = Mocks());

  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1, 20);
  final messages = [
    ChatMessage(id: 'm1', senderId: 'coach-1', body: 'How was leg day?', createdAt: yesterday),
    ChatMessage(id: 'm2', senderId: 'user-1', body: 'Hard but done', createdAt: yesterday.add(const Duration(minutes: 5))),
    ChatMessage(id: 'm3', senderId: 'user-1', body: 'Good morning coach', createdAt: DateTime(now.year, now.month, now.day, 0, 1)),
  ];

  testWidgets('chat: oldest at the top, my last message at the bottom, a marker per day', (tester) async {
    when(() => mocks.social.messages('c1')).thenAnswer((_) => Stream.value(messages));
    when(() => mocks.social.markRead(any())).thenAnswer((_) async {});
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionProvider.overrideWith(() => FakeSessionNotifier(SignedIn(sessionData()))),
        ...mocks.overrides,
      ],
      child: localizedApp(Consumer(
        builder: (context, ref, _) =>
            ref.watch(sessionProvider).hasValue ? const ChatScreen(conversationId: 'c1', title: 'Coach') : const SizedBox.shrink(),
      )),
    ));
    await tester.pumpAndSettle();

    double y(String text) => tester.getCenter(find.text(text)).dy;
    expect(y('Yesterday'), lessThan(y('How was leg day?')));
    expect(y('How was leg day?'), lessThan(y('Hard but done')));
    expect(y('Hard but done'), lessThan(y('Today')));
    expect(y('Today'), lessThan(y('Good morning coach')));
    // Mine on the right (English), theirs on the left.
    final width = tester.getSize(find.byType(ChatScreen)).width;
    expect(tester.getCenter(find.text('Good morning coach')).dx, greaterThan(width / 2));
    expect(tester.getCenter(find.text('How was leg day?')).dx, lessThan(width / 2));
  });

  test('chat rows put a day before each day\'s first message', () {
    final rows = chatRows(messages);
    expect(rows.whereType<DateTime>(), hasLength(2));
    expect(rows.first, isA<DateTime>());
    expect((rows.last as ChatMessage).id, 'm3');
  });
}
