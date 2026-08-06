import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/video_call.dart';
import '../network/api_client.dart';

class VideoCallService {
  final ApiClient _client;

  VideoCallService({ApiClient? client}) : _client = client ?? apiClient;

  Future<VideoCall> requestIntro({
    required String calleeId,
    required int durationMinutes,
    CallType callType = CallType.video,
  }) async {
    final resp = await _client.post(
      '${ApiConfig.videoCalls}/request',
      data: {
        'callee_id': calleeId,
        'duration_minutes': durationMinutes,
        'call_type': callType.apiValue,
      },
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<VideoCall> accept(String callId) async {
    final resp = await _client.post(
      '${ApiConfig.videoCalls}/$callId/accept',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<VideoCall> reject(String callId) async {
    final resp = await _client.post(
      '${ApiConfig.videoCalls}/$callId/reject',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<VideoCall> cancel(String callId) async {
    final resp = await _client.post(
      '${ApiConfig.videoCalls}/$callId/cancel',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<VideoCall> end(String callId) async {
    final resp = await _client.post(
      '${ApiConfig.videoCalls}/$callId/end',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<VideoCallToken> getToken(String callId) async {
    final resp = await _client.get(
      '${ApiConfig.videoCalls}/$callId/token',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCallToken.fromJson(_unwrapMap(resp));
  }

  Future<VideoCall> getById(String callId) async {
    final resp = await _client.get(
      '${ApiConfig.videoCalls}/$callId',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return VideoCall.fromJson(_unwrapMap(resp));
  }

  Future<PaginatedVideoCalls> getHistory({int page = 1, int limit = 20}) async {
    final resp = await _client.get(
      '${ApiConfig.videoCalls}/history',
      queryParameters: {'page': page, 'limit': limit},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedVideoCalls.fromJson(_unwrapMap(resp));
  }

  Map<String, dynamic> _unwrapMap(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException(_messageFrom(resp), status);
    }
    final data = resp.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map[ApiConfig.dataKey];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return map;
    }
    throw ApiException('Invalid response from server', status);
  }

  String _messageFrom(Response resp) {
    final body = resp.data;
    if (body is Map) {
      if (body[ApiConfig.messageKey] is String) {
        return body[ApiConfig.messageKey] as String;
      }
      final err = body[ApiConfig.errorKey];
      if (err is String) return err;
    }
    return resp.statusMessage ?? 'Request failed';
  }
}
