import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/point_transaction.dart';
import '../network/api_client.dart';

class PointService {
  final ApiClient _client = apiClient;

  Future<PointsBalance> getBalance() async {
    final resp = await _client.get(
      ApiConfig.pointsBalance,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PointsBalance.fromJson(_unwrapMap(resp));
  }

  Future<PaginatedPointTransactions> getTransactions({int page = 1, int limit = 20}) async {
    final resp = await _client.get(
      ApiConfig.pointsTransactions,
      queryParameters: {'page': page, 'limit': limit},
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    return PaginatedPointTransactions.fromJson(_unwrapMap(resp));
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
