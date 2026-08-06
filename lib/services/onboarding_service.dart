import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/circle.dart';
import '../network/api_client.dart';

class OnboardingService {
  final ApiClient _client = apiClient;

  Future<Map<String, dynamic>> getStatus() async {
    final resp = await _client.get(
      '/onboarding/status',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
  }

  Future<List<Circle>> getSuggestedCircles() async {
    final status = await getStatus();
    final raw = status['suggested_circles'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Circle.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Completes community onboarding. Returns profile map + `points_awarded`.
  Future<Map<String, dynamic>> completeCommunity({
    required List<String> interestIds,
    required String city,
    required List<String> suggestedCircleIds,
    String? country,
    bool locationOptIn = false,
    String? conversationStyle,
    String? humorType,
    String? bio,
  }) async {
    final body = <String, dynamic>{
      'interests': interestIds,
      'city': city.trim(),
      'suggested_circle_ids': suggestedCircleIds,
      'location_opt_in': locationOptIn,
      if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
      if (conversationStyle != null && conversationStyle.isNotEmpty)
        'conversation_style': conversationStyle,
      if (humorType != null && humorType.isNotEmpty) 'humor_type': humorType,
      if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
    };

    final resp = await _client.post(
      '/onboarding/community',
      data: jsonEncode(body),
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return _unwrapMap(resp);
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
    if (body is Map<String, dynamic>) {
      if (body[ApiConfig.messageKey] is String) return body[ApiConfig.messageKey] as String;
      final err = body[ApiConfig.errorKey];
      if (err is String) return err;
      if (err is Map && err.values.isNotEmpty) return err.values.first.toString();
    }
    return resp.statusMessage ?? 'Request failed';
  }
}
