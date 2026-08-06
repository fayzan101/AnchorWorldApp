import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../network/api_client.dart';

class BlockService {
  final ApiClient _client = apiClient;

  Future<void> blockUser(String userId) async {
    final resp = await _client.post(
      '${ApiConfig.users}/$userId/block',
      data: {},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_message(resp), status);
    }
  }

  Future<void> unblockUser(String userId) async {
    final resp = await _client.delete(
      '${ApiConfig.users}/$userId/block',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 204) {
      throw ApiException(_message(resp), status);
    }
  }

  Future<List<Map<String, dynamic>>> listBlocked({int page = 1, int limit = 50}) async {
    final resp = await _client.get(
      ApiConfig.usersBlocked,
      queryParameters: {'page': page, 'limit': limit},
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
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
      }
    }
    return [];
  }

  /// Report a user (PUT /users/:id with optional reason).
  Future<void> reportUser(String userId, {String? reason}) async {
    final resp = await _client.put(
      '${ApiConfig.users}/$userId',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_message(resp), status);
    }
  }

  String _message(Response resp) {
    final body = resp.data;
    if (body is Map && body[ApiConfig.messageKey] is String) {
      return body[ApiConfig.messageKey] as String;
    }
    return resp.statusMessage ?? 'Request failed';
  }
}

final blockService = BlockService();
