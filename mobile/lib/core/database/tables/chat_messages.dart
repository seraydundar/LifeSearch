import 'package:drift/drift.dart';

/// Persists the Ask AI conversation (Faz 36, docs/roadmap.md) — it used
/// to live only in `ChatController`'s in-memory Riverpod state, so an app
/// restart (or the OS simply killing the backgrounded process) silently
/// lost the whole thread. Scoped by `userId` for the same reason
/// `RecentSearches.userId` is: a shared device's accounts must never see
/// each other's chat.
///
/// `@DataClassName` avoids drift's default singularized row-class name
/// (`ChatMessage`), which would collide with the domain entity of the
/// same name in `chat_message.dart`.
@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text()();

  /// `ChatRole.name` ('user' or 'assistant') — mirrors the `ItemType`
  /// enum-name-as-db-value convention already used by `LocalItems`.
  TextColumn get role => text()();
  TextColumn get content => text()();

  /// JSON-encoded `List<SearchResult>` — see
  /// `ChatMessagesDataSource._encodeSources`/`_decodeSources`.
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isError => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
