class VideoCallParticipant {
  final String id;
  final String fullName;
  final String? profilePicture;

  const VideoCallParticipant({
    required this.id,
    required this.fullName,
    this.profilePicture,
  });

  factory VideoCallParticipant.fromJson(Map<String, dynamic> j) {
    return VideoCallParticipant(
      id: (j['id'] ?? '').toString(),
      fullName: (j['full_name'] ?? j['name'] ?? 'Member').toString(),
      profilePicture: j['profile_picture']?.toString() ?? j['profilePicture']?.toString(),
    );
  }
}

enum VideoCallStatus {
  pending,
  active,
  rejected,
  cancelled,
  completed,
  missed,
  unknown;

  static VideoCallStatus fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return VideoCallStatus.pending;
      case 'active':
        return VideoCallStatus.active;
      case 'rejected':
        return VideoCallStatus.rejected;
      case 'cancelled':
      case 'canceled':
        return VideoCallStatus.cancelled;
      case 'completed':
        return VideoCallStatus.completed;
      case 'missed':
        return VideoCallStatus.missed;
      default:
        return VideoCallStatus.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case VideoCallStatus.pending:
        return 'pending';
      case VideoCallStatus.active:
        return 'active';
      case VideoCallStatus.rejected:
        return 'rejected';
      case VideoCallStatus.cancelled:
        return 'cancelled';
      case VideoCallStatus.completed:
        return 'completed';
      case VideoCallStatus.missed:
        return 'missed';
      case VideoCallStatus.unknown:
        return 'unknown';
    }
  }
}

enum CallType {
  voice,
  video;

  static CallType fromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'voice':
        return CallType.voice;
      default:
        return CallType.video;
    }
  }

  String get apiValue => this == CallType.voice ? 'voice' : 'video';
}

class VideoCall {
  final String id;
  final String callerId;
  final String calleeId;
  final VideoCallStatus status;
  final CallType callType;
  final int durationMinutes;
  final int pointsSpent;
  final String channelName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final VideoCallParticipant? caller;
  final VideoCallParticipant? callee;

  const VideoCall({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.status,
    this.callType = CallType.video,
    required this.durationMinutes,
    required this.pointsSpent,
    required this.channelName,
    this.startedAt,
    this.endedAt,
    this.expiresAt,
    this.createdAt,
    this.caller,
    this.callee,
  });

  bool get isVoice => callType == CallType.voice;

  factory VideoCall.fromJson(Map<String, dynamic> j) {
    DateTime? parseDt(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    return VideoCall(
      id: (j['id'] ?? '').toString(),
      callerId: (j['caller_id'] ?? j['callerId'] ?? '').toString(),
      calleeId: (j['callee_id'] ?? j['calleeId'] ?? '').toString(),
      status: VideoCallStatus.fromString(j['status']?.toString()),
      callType: CallType.fromString((j['call_type'] ?? j['callType'])?.toString()),
      durationMinutes: j['duration_minutes'] is int
          ? j['duration_minutes'] as int
          : int.tryParse('${j['duration_minutes'] ?? 5}') ?? 5,
      pointsSpent: j['points_spent'] is int
          ? j['points_spent'] as int
          : int.tryParse('${j['points_spent'] ?? 0}') ?? 0,
      channelName: (j['channel_name'] ?? j['channelName'] ?? j['id'] ?? '').toString(),
      startedAt: parseDt(j['started_at'] ?? j['startedAt']),
      endedAt: parseDt(j['ended_at'] ?? j['endedAt']),
      expiresAt: parseDt(j['expires_at'] ?? j['expiresAt']),
      createdAt: parseDt(j['created_at'] ?? j['createdAt']),
      caller: j['caller'] is Map ? VideoCallParticipant.fromJson(Map<String, dynamic>.from(j['caller'] as Map)) : null,
      callee: j['callee'] is Map ? VideoCallParticipant.fromJson(Map<String, dynamic>.from(j['callee'] as Map)) : null,
    );
  }

  int get costForDuration => 0;

  static int costFor(int minutes) => 0;
}

class VideoCallToken {
  final String callId;
  final String channelName;
  final String token;
  final int uid;
  final String appId;
  final int expiresAt;
  final CallType callType;

  const VideoCallToken({
    required this.callId,
    required this.channelName,
    required this.token,
    required this.uid,
    required this.appId,
    required this.expiresAt,
    this.callType = CallType.video,
  });

  factory VideoCallToken.fromJson(Map<String, dynamic> j) {
    final expiresRaw = j['expires_at'] ?? j['expiresAt'];
    return VideoCallToken(
      callId: (j['call_id'] ?? j['callId'] ?? '').toString(),
      channelName: (j['channel_name'] ?? j['channelName'] ?? '').toString(),
      token: (j['token'] ?? '').toString(),
      uid: j['uid'] is int ? j['uid'] as int : int.tryParse('${j['uid'] ?? 0}') ?? 0,
      appId: (j['app_id'] ?? j['appId'] ?? '').toString(),
      expiresAt: expiresRaw is int
          ? expiresRaw
          : int.tryParse('${expiresRaw ?? 0}') ?? 0,
      callType: CallType.fromString((j['call_type'] ?? j['callType'])?.toString()),
    );
  }
}

class PaginatedVideoCalls {
  final List<VideoCall> items;
  final int page;
  final int totalPages;

  const PaginatedVideoCalls({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
  });

  factory PaginatedVideoCalls.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final items = <VideoCall>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) items.add(VideoCall.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final pagination = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : <String, dynamic>{};
    return PaginatedVideoCalls(
      items: items,
      page: pagination['page'] is int ? pagination['page'] as int : 1,
      totalPages: pagination['total_pages'] is int
          ? pagination['total_pages'] as int
          : int.tryParse('${pagination['total_pages'] ?? 1}') ?? 1,
    );
  }
}
