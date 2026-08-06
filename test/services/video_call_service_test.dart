import 'package:anchor_heart/config/api_config.dart';
import 'package:anchor_heart/models/video_call.dart';
import 'package:anchor_heart/network/api_client.dart';
import 'package:anchor_heart/services/video_call_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.onPost, this.onGet});

  final Future<Response> Function(
    String path, {
    dynamic data,
    Options? options,
  })? onPost;

  final Future<Response> Function(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  })? onGet;

  @override
  Future<Response> post(String path, {dynamic data, Options? options}) {
    return onPost!(path, data: data, options: options);
  }

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return onGet!(path, queryParameters: queryParameters, options: options);
  }
}

Response _ok(Map<String, dynamic> data, {int status = 200}) {
  return Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: status,
    data: {'data': data},
  );
}

Map<String, dynamic> _callJson({
  String id = 'call-1',
  String status = 'pending',
  int pointsSpent = 0,
  String callType = 'video',
}) {
  return {
    'id': id,
    'caller_id': 'caller-1',
    'callee_id': 'callee-1',
    'status': status,
    'call_type': callType,
    'duration_minutes': 5,
    'points_spent': pointsSpent,
    'channel_name': id,
  };
}

void main() {
  group('VideoCallService', () {
    test('requestIntro posts callee, duration, and call_type', () async {
      Map<String, dynamic>? sent;
      String? path;

      final service = VideoCallService(
        client: _FakeApiClient(
          onPost: (p, {data, options}) async {
            path = p;
            sent = Map<String, dynamic>.from(data as Map);
            return _ok(_callJson(pointsSpent: 0, callType: 'voice'));
          },
        ),
      );

      final call = await service.requestIntro(
        calleeId: 'callee-1',
        durationMinutes: 5,
        callType: CallType.voice,
      );

      expect(path, '${ApiConfig.videoCalls}/request');
      expect(sent, {
        'callee_id': 'callee-1',
        'duration_minutes': 5,
        'call_type': 'voice',
      });
      expect(call.id, 'call-1');
      expect(call.pointsSpent, 0);
      expect(call.callType, CallType.voice);
      expect(call.status, VideoCallStatus.pending);
    });

    test('accept / reject / cancel / end hit correct endpoints', () async {
      final paths = <String>[];
      final service = VideoCallService(
        client: _FakeApiClient(
          onPost: (p, {data, options}) async {
            paths.add(p);
            final status = p.endsWith('/accept')
                ? 'active'
                : p.endsWith('/reject')
                    ? 'rejected'
                    : p.endsWith('/cancel')
                        ? 'cancelled'
                        : 'completed';
            return _ok(_callJson(status: status));
          },
        ),
      );

      expect((await service.accept('call-1')).status, VideoCallStatus.active);
      expect((await service.reject('call-1')).status, VideoCallStatus.rejected);
      expect(
        (await service.cancel('call-1')).status,
        VideoCallStatus.cancelled,
      );
      expect(
        (await service.end('call-1')).status,
        VideoCallStatus.completed,
      );

      expect(paths, [
        '${ApiConfig.videoCalls}/call-1/accept',
        '${ApiConfig.videoCalls}/call-1/reject',
        '${ApiConfig.videoCalls}/call-1/cancel',
        '${ApiConfig.videoCalls}/call-1/end',
      ]);
    });

    test('getToken returns Agora credentials', () async {
      String? path;
      final service = VideoCallService(
        client: _FakeApiClient(
          onGet: (p, {queryParameters, options}) async {
            path = p;
            return _ok({
              'call_id': 'call-1',
              'channel_name': 'call-1',
              'token': 'agora-token',
              'uid': 42,
              'app_id': 'app-id',
              'expires_at': 999999,
            });
          },
        ),
      );

      final token = await service.getToken('call-1');

      expect(path, '${ApiConfig.videoCalls}/call-1/token');
      expect(token.token, 'agora-token');
      expect(token.uid, 42);
      expect(token.appId, 'app-id');
    });

    test('getHistory passes pagination query', () async {
      Map<String, dynamic>? query;
      final service = VideoCallService(
        client: _FakeApiClient(
          onGet: (p, {queryParameters, options}) async {
            query = queryParameters;
            return _ok({
              'items': [_callJson(status: 'completed')],
              'pagination': {'page': 2, 'total_pages': 3},
            });
          },
        ),
      );

      final history = await service.getHistory(page: 2, limit: 10);

      expect(query, {'page': 2, 'limit': 10});
      expect(history.items, hasLength(1));
      expect(history.page, 2);
      expect(history.totalPages, 3);
    });

    test('throws ApiException on non-success status', () async {
      final service = VideoCallService(
        client: _FakeApiClient(
          onPost: (p, {data, options}) async {
            return Response(
              requestOptions: RequestOptions(path: p),
              statusCode: 403,
              data: {'message': 'Premium required'},
            );
          },
        ),
      );

      expect(
        () => service.requestIntro(calleeId: 'x', durationMinutes: 5),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Premium required',
          ).having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });
}
