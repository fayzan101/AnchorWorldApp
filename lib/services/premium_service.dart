import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/premium_status.dart';
import '../network/api_client.dart';

class PremiumService {
  static PremiumStatus? _statusCache;
  static DateTime? _statusCacheAt;
  static const _ttl = Duration(minutes: 3);

  static void clearCache() {
    _statusCache = null;
    _statusCacheAt = null;
  }

  Future<PremiumStatus> getStatus({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _statusCache != null &&
        _statusCacheAt != null &&
        DateTime.now().difference(_statusCacheAt!) < _ttl) {
      return _statusCache!;
    }
    final resp = await apiClient.get(
      ApiConfig.premiumStatus,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to load Premium status', status);
    }
    final parsed = _parse(resp.data);
    _statusCache = parsed;
    _statusCacheAt = DateTime.now();
    return parsed;
  }

  /// Confirms Premium after a successful RevenueCat purchase / restore.
  Future<PremiumStatus> confirmPurchase() async {
    final resp = await apiClient.post(
      ApiConfig.premiumConfirm,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to confirm Premium', status);
    }
    final parsed = _parse(resp.data);
    _statusCache = parsed;
    _statusCacheAt = DateTime.now();
    return parsed;
  }

  @Deprecated('Use IAP + confirmPurchase')
  Future<PremiumStatus> subscribe() => confirmPurchase();

  PremiumStatus _parse(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map[ApiConfig.dataKey];
      if (inner is Map) {
        return PremiumStatus.fromJson(Map<String, dynamic>.from(inner));
      }
      return PremiumStatus.fromJson(map);
    }
    throw ApiException('Invalid Premium response', 500);
  }
}

final premiumService = PremiumService();
