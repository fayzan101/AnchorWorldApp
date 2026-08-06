import 'dart:convert';

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../config/api_config.dart';

class FollowService {
  final ApiClient _client = apiClient;
  Future<Map<String, dynamic>> follow(String targetId) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final path = '/follows/$targetId';

    final resp = await _client.post(path, data: jsonEncode({}), options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Follow request failed';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    return {};
  }
  Future<List<Map<String, dynamic>>> getPending() async {
    final resp = await _client.get('/follows/pending');
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to load pending follows';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }

    final data = resp.data;
    if (data == 0 || data == '0') return <Map<String, dynamic>>[];
    if (data is Map<String, dynamic> && (data[ApiConfig.dataKey] == 0 || data[ApiConfig.dataKey] == '0')) return <Map<String, dynamic>>[];
    if (data is List) {
      return data.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }
    if (data is Map<String, dynamic> && data.containsKey(ApiConfig.dataKey)) {
      final d = data[ApiConfig.dataKey];
      if (d == 0 || d == '0') return <Map<String, dynamic>>[];

      if (d is List) {
        return d.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
      }

      if (d is Map<String, dynamic> && d.containsKey('requests') && d['requests'] is List) {
        final reqs = d['requests'] as List;
        return reqs.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
      }
    }
    if (data is Map<String, dynamic> && data.containsKey('requests') && data['requests'] is List) {
      final reqs = data['requests'] as List;
      return reqs.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }

    throw Exception('Invalid response from server');
  }

  Future<List<Map<String, dynamic>>> getSent() async {
    final resp = await _client.get(ApiConfig.followsSent);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to load sent requests';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }

    final data = resp.data;
    if (data is Map<String, dynamic> && data.containsKey(ApiConfig.dataKey)) {
      final d = data[ApiConfig.dataKey];
      if (d is Map<String, dynamic> && d['requests'] is List) {
        return (d['requests'] as List)
            .map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
      }
      if (d is List) {
        return d.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
      }
    }
    if (data is List) {
      return data.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final path = '/follows/$requestId/accept';

    final resp = await _client.put(path, data: jsonEncode({}), options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to accept follow request';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }

    final data = resp.data;
    if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
    return {};
  }
  Future<void> deleteRequest(String requestId) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final path = '/follows/$requestId';
    final resp = await _client.delete(path, options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 204) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to delete follow request';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }
    return;
  }

  /// Cancel an outgoing pending request to [targetUserId] (looks up sent list).
  Future<bool> cancelSentTo(String targetUserId) async {
    final sent = await getSent();
    for (final item in sent) {
      final id = (item['id'] ?? '').toString();
      String followingId = '';
      final following = item['following'];
      if (following is Map) {
        followingId = (following['id'] ?? '').toString();
      } else {
        followingId = (item['following_id'] ?? '').toString();
      }
      if (id.isNotEmpty && followingId == targetUserId) {
        await deleteRequest(id);
        return true;
      }
    }
    return false;
  }
  Future<List<Map<String, dynamic>>> getConnections() async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.get(ApiConfig.followsConnections, options: options);
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to load connections';
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        }
      }
      throw Exception(message);
    }

    final data = resp.data;
    List<dynamic>? items;
    if (data is Map<String, dynamic>) {
      final d = data[ApiConfig.dataKey];
      if (d is Map<String, dynamic> && d['connections'] is List) {
        items = d['connections'] as List;
      } else if (d is List) {
        items = d;
      } else if (data['connections'] is List) {
        items = data['connections'] as List;
      }
    } else if (data is List) {
      items = data;
    }

    if (items == null) return <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> out = [];
    for (final e in items) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        // Nested user object support
        if (m['user'] is Map) {
          final u = Map<String, dynamic>.from(m['user'] as Map);
          m.addAll(u);
          m['id'] = (u['id'] ?? m['id'] ?? '').toString();
        }
        String? image = (m['profile_picture'] ?? m['imageUrl'] ?? m['image_url'])?.toString();
        if (image != null && image.isNotEmpty && image.startsWith('/uploads/')) {
          try {
            final base = ApiConfig.baseUrl;
            final uri = Uri.parse(base);
            final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
            m['imageUrl'] = origin + image;
          } catch (_) {
            m['imageUrl'] = image;
          }
        } else if (image != null && image.isNotEmpty) {
          m['imageUrl'] = image;
        } else {
          m['imageUrl'] = '';
        }
        out.add(m);
      }
    }
    return out;
  }
}
final followService = FollowService();

