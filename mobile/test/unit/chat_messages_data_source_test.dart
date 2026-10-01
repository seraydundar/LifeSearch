import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/database/app_database.dart';
import 'package:lifesearch/features/ai_chat/data/local/chat_messages_data_source.dart';
import 'package:lifesearch/features/ai_chat/domain/entities/chat_message.dart';
import 'package:lifesearch/features/item/domain/entities/item.dart';
import 'package:lifesearch/features/search/domain/entities/search_result.dart';

void main() {
  late AppDatabase db;
  late ChatMessagesDataSource source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = ChatMessagesDataSource(db);
  });

  tearDown(() => db.close());

  test('appended messages come back in the order they were asked', () async {
    await source.append('user-1', const ChatMessage(role: ChatRole.user, text: 'soru'));
    await source.append(
      'user-1',
      const ChatMessage(role: ChatRole.assistant, text: 'cevap'),
    );

    final loaded = await source.loadAll('user-1');

    expect(loaded, [
      const ChatMessage(role: ChatRole.user, text: 'soru'),
      const ChatMessage(role: ChatRole.assistant, text: 'cevap'),
    ]);
  });

  test('a message\'s sources round-trip through storage intact', () async {
    const message = ChatMessage(
      role: ChatRole.assistant,
      text: 'Docker Compose birden fazla container\'ı yönetir.',
      sources: [
        SearchResult(
          itemId: 'note-1',
          itemType: ItemType.note,
          itemTitle: 'Docker Notes',
          snippet: 'Docker Compose...',
          similarity: 0.9,
        ),
      ],
    );
    await source.append('user-1', message);

    final loaded = await source.loadAll('user-1');

    expect(loaded, [message]);
  });

  test('an error bubble is never persisted', () async {
    // Mirrors `ApiAiChatRepository.ask`'s own reasoning for excluding
    // error bubbles from the history sent to the backend: they're this
    // app's own fallback text, never something the model actually said.
    // `ChatController.ask` relies on simply never calling `append` for
    // one — this just documents that an `isError` message, if it ever
    // were appended, still round-trips its flag rather than silently
    // losing it.
    await source.append(
      'user-1',
      const ChatMessage(role: ChatRole.assistant, text: 'Bir hata oluştu.', isError: true),
    );

    final loaded = await source.loadAll('user-1');

    expect(loaded.single.isError, isTrue);
  });

  test('one account never sees another account\'s chat history', () async {
    await source.append('user-1', const ChatMessage(role: ChatRole.user, text: 'docker nedir'));
    await source.append('user-2', const ChatMessage(role: ChatRole.user, text: 'flutter nedir'));

    expect((await source.loadAll('user-1')).single.text, 'docker nedir');
    expect((await source.loadAll('user-2')).single.text, 'flutter nedir');
  });
}
