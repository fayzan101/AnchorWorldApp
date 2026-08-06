import 'package:anchor_heart/models/video_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoCallStatus', () {
    test('parses known statuses', () {
      expect(VideoCallStatus.fromString('pending'), VideoCallStatus.pending);
      expect(VideoCallStatus.fromString('ACTIVE'), VideoCallStatus.active);
      expect(VideoCallStatus.fromString('rejected'), VideoCallStatus.rejected);
      expect(VideoCallStatus.fromString('cancelled'), VideoCallStatus.cancelled);
      expect(VideoCallStatus.fromString('canceled'), VideoCallStatus.cancelled);
      expect(VideoCallStatus.fromString('completed'), VideoCallStatus.completed);
      expect(VideoCallStatus.fromString('missed'), VideoCallStatus.missed);
    });

    test('falls back to unknown', () {
      expect(VideoCallStatus.fromString(null), VideoCallStatus.unknown);
      expect(VideoCallStatus.fromString(''), VideoCallStatus.unknown);
      expect(VideoCallStatus.fromString('ringing'), VideoCallStatus.unknown);
    });

    test('apiValue round-trips known statuses', () {
      for (final status in VideoCallStatus.values) {
        if (status == VideoCallStatus.unknown) continue;
        expect(VideoCallStatus.fromString(status.apiValue), status);
      }
    });
  });

  group('VideoCallParticipant', () {
    test('parses id, name, and profile picture', () {
      final p = VideoCallParticipant.fromJson({
        'id': 'u1',
        'full_name': 'Ada Lovelace',
        'profile_picture': 'https://cdn/a.jpg',
      });
      expect(p.id, 'u1');
      expect(p.fullName, 'Ada Lovelace');
      expect(p.profilePicture, 'https://cdn/a.jpg');
    });

    test('uses name fallback and defaults', () {
      final p = VideoCallParticipant.fromJson({'id': 42, 'name': 'Grace'});
      expect(p.id, '42');
      expect(p.fullName, 'Grace');
      expect(p.profilePicture, isNull);
    });
  });

  group('VideoCall.fromJson', () {
    test('parses snake_case payload with participants', () {
      final call = VideoCall.fromJson({
        'id': 'call-1',
        'caller_id': 'c1',
        'callee_id': 'c2',
        'status': 'pending',
        'duration_minutes': 5,
        'points_spent': 0,
        'channel_name': 'call-1',
        'created_at': '2026-07-19T10:00:00.000Z',
        'caller': {'id': 'c1', 'full_name': 'Caller'},
        'callee': {'id': 'c2', 'full_name': 'Callee'},
      });

      expect(call.id, 'call-1');
      expect(call.callerId, 'c1');
      expect(call.calleeId, 'c2');
      expect(call.status, VideoCallStatus.pending);
      expect(call.durationMinutes, 5);
      expect(call.pointsSpent, 0);
      expect(call.channelName, 'call-1');
      expect(call.createdAt, isNotNull);
      expect(call.caller?.fullName, 'Caller');
      expect(call.callee?.fullName, 'Callee');
    });

    test('parses camelCase aliases and string numbers', () {
      final call = VideoCall.fromJson({
        'id': 'call-2',
        'callerId': 'a',
        'calleeId': 'b',
        'status': 'active',
        'duration_minutes': '10',
        'points_spent': '0',
        'channelName': 'ch-2',
        'startedAt': '2026-07-19T10:01:00.000Z',
      });

      expect(call.callerId, 'a');
      expect(call.calleeId, 'b');
      expect(call.status, VideoCallStatus.active);
      expect(call.durationMinutes, 10);
      expect(call.pointsSpent, 0);
      expect(call.channelName, 'ch-2');
      expect(call.startedAt, isNotNull);
    });

    test('Premium intros cost zero points', () {
      expect(VideoCall.costFor(5), 0);
      expect(VideoCall.costFor(10), 0);
      final call = VideoCall.fromJson({
        'id': 'x',
        'caller_id': 'a',
        'callee_id': 'b',
        'status': 'pending',
        'duration_minutes': 5,
        'points_spent': 0,
      });
      expect(call.costForDuration, 0);
    });
    test('parses call_type voice', () {
      final call = VideoCall.fromJson({
        'id': 'c',
        'caller_id': 'a',
        'callee_id': 'b',
        'status': 'pending',
        'call_type': 'voice',
        'duration_minutes': 5,
        'points_spent': 0,
      });
      expect(call.callType, CallType.voice);
      expect(call.isVoice, isTrue);
    });
  });

  group('VideoCallToken.fromJson', () {
    test('parses Agora token payload', () {
      final token = VideoCallToken.fromJson({
        'call_id': 'call-1',
        'channel_name': 'call-1',
        'token': 'agora-token',
        'uid': 42,
        'app_id': 'app-id',
        'expires_at': 999999,
      });

      expect(token.callId, 'call-1');
      expect(token.channelName, 'call-1');
      expect(token.token, 'agora-token');
      expect(token.uid, 42);
      expect(token.appId, 'app-id');
      expect(token.expiresAt, 999999);
    });

    test('parses camelCase and string uid', () {
      final token = VideoCallToken.fromJson({
        'callId': 'c',
        'channelName': 'ch',
        'token': 't',
        'uid': '7',
        'appId': 'app',
        'expiresAt': '100',
      });
      expect(token.uid, 7);
      expect(token.expiresAt, 100);
      expect(token.appId, 'app');
    });
  });

  group('PaginatedVideoCalls.fromJson', () {
    test('parses history list and pagination', () {
      final page = PaginatedVideoCalls.fromJson({
        'items': [
          {
            'id': 'call-1',
            'caller_id': 'a',
            'callee_id': 'b',
            'status': 'completed',
            'duration_minutes': 5,
            'points_spent': 0,
            'channel_name': 'call-1',
          },
        ],
        'pagination': {'page': 2, 'total_pages': 4},
      });

      expect(page.items, hasLength(1));
      expect(page.items.first.status, VideoCallStatus.completed);
      expect(page.page, 2);
      expect(page.totalPages, 4);
    });

    test('defaults empty list and page 1', () {
      final page = PaginatedVideoCalls.fromJson({});
      expect(page.items, isEmpty);
      expect(page.page, 1);
      expect(page.totalPages, 1);
    });
  });
}
