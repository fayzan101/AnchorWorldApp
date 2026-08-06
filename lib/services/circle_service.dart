import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/circle.dart';
import '../models/post.dart';
import '../network/api_client.dart';

class CircleService {
  final ApiClient _client = apiClient;

  Future<List<Circle>> getCircles() async {
    final resp = await _client.get(
      ApiConfig.circles,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _parseList(resp);
  }

  Future<List<Circle>> getFeatured() async {
    final resp = await _client.get(
      '${ApiConfig.circles}/featured',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _parseList(resp);
  }

  Future<Circle> getCircle(String id) async {
    final resp = await _client.get(
      '${ApiConfig.circles}/$id',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return Circle.fromJson(_unwrapMap(resp));
  }

  Future<PaginatedPosts> getCirclePosts(String id, {int page = 1, int limit = 20}) async {
    final resp = await _client.get(
      '${ApiConfig.circles}/$id/posts',
      queryParameters: {'page': page, 'limit': limit},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedPosts.fromJson(_unwrapMap(resp));
  }

  /// Returns map with `circle`, `points_awarded`, `points_balance`.
  Future<Map<String, dynamic>> join(String id) async {
    final resp = await _client.post(
      '${ApiConfig.circles}/$id/join',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<void> leave(String id) async {
    final resp = await _client.delete(
      '${ApiConfig.circles}/$id/leave',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
  }

  List<Circle> _parseList(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    List raw = const [];
    if (data is Map && data[ApiConfig.dataKey] is List) {
      raw = data[ApiConfig.dataKey] as List;
    } else if (data is List) {
      raw = data;
    }
    return raw
        .whereType<Map>()
        .map((e) => Circle.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic> _unwrapMap(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      if (data[ApiConfig.dataKey] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data[ApiConfig.dataKey] as Map);
      }
      return Map<String, dynamic>.from(data);
    }
    throw ApiException('Invalid response from server', status);
  }

  String _messageFrom(Response resp) {
    final body = resp.data;
    if (body is Map) {
      if (body[ApiConfig.messageKey] is String) return body[ApiConfig.messageKey] as String;
      final err = body[ApiConfig.errorKey];
      if (err is String) return err;
    }
    return resp.statusMessage ?? 'Request failed';
  }
}
