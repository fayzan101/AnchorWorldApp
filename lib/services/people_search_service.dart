import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../network/api_client.dart';

class PeopleSearchService {
  final ApiClient _client = apiClient;

  /// Search community members. Requires purpose=search on the API.
  Future<List<Map<String, dynamic>>> searchPeople({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final resp = await _client.get(
      ApiConfig.users,
      queryParameters: {
        'purpose': 'search',
        'search': q,
        'page': page,
        'limit': limit,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );

    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_message(resp), status);
    }

    final data = resp.data;
    if (data is Map && data[ApiConfig.dataKey] is Map) {
      final inner = Map<String, dynamic>.from(data[ApiConfig.dataKey] as Map);
      final items = inner['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    if (data is Map && data[ApiConfig.dataKey] is List) {
      return (data[ApiConfig.dataKey] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  String _message(Response resp) {
    final body = resp.data;
    if (body is Map && body[ApiConfig.messageKey] is String) {
      return body[ApiConfig.messageKey] as String;
    }
    return resp.statusMessage ?? 'Search failed';
  }
}

final peopleSearchService = PeopleSearchService();
