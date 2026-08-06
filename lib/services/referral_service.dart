import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../network/api_client.dart';

class ReferralInvite {
  final String id;
  final String status;
  final String? refereeName;
  final DateTime? createdAt;
  final DateTime? completedAt;

  const ReferralInvite({
    required this.id,
    required this.status,
    this.refereeName,
    this.createdAt,
    this.completedAt,
  });

  factory ReferralInvite.fromJson(Map<String, dynamic> j) {
    final referee = j['referee'] is Map ? Map<String, dynamic>.from(j['referee'] as Map) : null;
    DateTime? parse(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    return ReferralInvite(
      id: (j['id'] ?? '').toString(),
      status: (j['status'] ?? 'pending').toString(),
      refereeName: referee?['full_name']?.toString(),
      createdAt: parse(j['created_at']),
      completedAt: parse(j['completed_at']),
    );
  }
}

class ReferralInfo {
  final String referralCode;
  final String shareLink;
  final int invitedCount;
  final int completedCount;
  final int referrerReward;
  final int refereeReward;
  final List<ReferralInvite> invites;

  const ReferralInfo({
    required this.referralCode,
    required this.shareLink,
    required this.invitedCount,
    required this.completedCount,
    required this.referrerReward,
    required this.refereeReward,
    required this.invites,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> j) {
    final invites = <ReferralInvite>[];
    final raw = j['invites'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) invites.add(ReferralInvite.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return ReferralInfo(
      referralCode: (j['referral_code'] ?? '').toString(),
      shareLink: (j['share_link'] ?? '').toString(),
      invitedCount: int.tryParse('${j['invited_count'] ?? 0}') ?? 0,
      completedCount: int.tryParse('${j['completed_count'] ?? 0}') ?? 0,
      referrerReward: int.tryParse('${j['referrer_reward'] ?? 100}') ?? 100,
      refereeReward: int.tryParse('${j['referee_reward'] ?? 50}') ?? 50,
      invites: invites,
    );
  }
}

class ReferralService {
  Future<ReferralInfo> getMine() async {
    final resp = await apiClient.get(
      ApiConfig.referralsMe,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to load referrals', status);
    }
    return _parse(resp.data);
  }

  Future<void> applyCode(String code) async {
    final resp = await apiClient.post(
      ApiConfig.referralsApply,
      data: {'code': code.trim()},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to apply referral code', status);
    }
  }

  ReferralInfo _parse(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map[ApiConfig.dataKey];
      if (inner is Map) return ReferralInfo.fromJson(Map<String, dynamic>.from(inner));
      return ReferralInfo.fromJson(map);
    }
    throw ApiException('Invalid referral response', 500);
  }
}

final referralService = ReferralService();
