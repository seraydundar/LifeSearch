import 'package:dio/dio.dart';

import '../../../item/domain/entities/item.dart';
import '../../domain/entities/collection_suggestion.dart';
import '../../domain/repositories/collection_suggestion_repository.dart';

class ApiCollectionSuggestionRepository implements CollectionSuggestionRepository {
  ApiCollectionSuggestionRepository(this._dio);

  final Dio? _dio;

  @override
  Future<List<CollectionSuggestion>> fetchSuggestions() async {
    final dio = _dio;
    if (dio == null) return const []; // no backend configured — a bonus feature, not required
    try {
      final response = await dio.post('/collections/suggest');
      final rows = response.data['suggestions'] as List;
      return rows.map((row) {
        final map = row as Map<String, dynamic>;
        final items = (map['items'] as List).map((itemRow) {
          final itemMap = itemRow as Map<String, dynamic>;
          return SuggestedItem(
            itemId: itemMap['item_id'] as String,
            title: itemMap['title'] as String?,
            itemType: ItemTypeX.fromDbValue(itemMap['item_type'] as String),
          );
        }).toList();
        return CollectionSuggestion(suggestedName: map['suggested_name'] as String, items: items);
      }).toList();
    } on DioException {
      // Quietly degrade rather than surface an error — Library works
      // fine without suggestions, so there's nothing actionable to show.
      return const [];
    }
  }
}
