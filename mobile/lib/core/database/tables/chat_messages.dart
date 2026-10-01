import 'package:drift/drift.dart';

/// `@DataClassName('ChatMessageRow')` avoids colliding with the domain `ChatMessage` entity.
@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text()();

  /// `ChatRole.name` ('user' or 'assistant').
  TextColumn get role => text()();
  TextColumn get content => text()();

  /// JSON-encoded `List<SearchResult>`; see `ChatMessagesDataSource._encodeSources`/`_decodeSources`.
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isError => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
