import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../item/domain/entities/item.dart';
import '../../../search/domain/entities/search_result.dart';
import '../../domain/entities/chat_message.dart';

/// Backs the Ask AI conversation's persistence (Faz 36, docs/roadmap.md).
/// Scoped by `userId` — same reasoning as `RecentSearchesDataSource`.
class ChatMessagesDataSource {
  ChatMessagesDataSource(this._db);

  final AppDatabase _db;

  Future<List<ChatMessage>> loadAll(String userId) async {
    final query = _db.select(_db.chatMessages)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    final rows = await query.get();
    return rows.map(_toChatMessage).toList();
  }

  /// Error bubbles are never passed in — same reasoning
  /// `ApiAiChatRepository.ask` already uses to exclude them from the
  /// `history` sent to the backend: they're this app's own fallback
  /// text, not something the model ever said.
  Future<void> append(String userId, ChatMessage message) {
    return _db.into(_db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            userId: userId,
            role: message.role.name,
            content: message.text,
            sourcesJson: Value(_encodeSources(message.sources)),
            isError: Value(message.isError),
          ),
        );
  }

  ChatMessage _toChatMessage(ChatMessageRow row) {
    return ChatMessage(
      role: row.role == ChatRole.assistant.name ? ChatRole.assistant : ChatRole.user,
      text: row.content,
      sources: _decodeSources(row.sourcesJson),
      isError: row.isError,
    );
  }

  String _encodeSources(List<SearchResult> sources) {
    return jsonEncode([
      for (final source in sources)
        {
          'item_id': source.itemId,
          'item_type': source.itemType.dbValue,
          'item_title': source.itemTitle,
          'snippet': source.snippet,
          'similarity': source.similarity,
        },
    ]);
  }

  List<SearchResult> _decodeSources(String sourcesJson) {
    final decoded = jsonDecode(sourcesJson) as List;
    return decoded.map((row) {
      final map = row as Map<String, dynamic>;
      return SearchResult(
        itemId: map['item_id'] as String,
        itemType: ItemTypeX.fromDbValue(map['item_type'] as String),
        itemTitle: map['item_title'] as String?,
        snippet: map['snippet'] as String,
        similarity: (map['similarity'] as num).toDouble(),
      );
    }).toList();
  }
}
