
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../config/api_config.dart';
import '../utils/custom_snackbar.dart';

class NotificationService {
  Future<void> postFcmToken(String token) async {
    if (token.isEmpty) return;

    try {
  final body = {'fcm_token': token};
      try {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString('auth_token') ?? '';
        if (stored.isEmpty) {
        } else {
        }
      } catch (e) {
      }
      final options = Options(headers: ApiConfig.jsonHeaders);
  final resp = await apiClient.post(ApiConfig.notificationsFcmToken, data: body, options: options);
      try {
      } catch (e) {
      }
      final status = resp.statusCode ?? 0;
      if (status == ApiConfig.success || status == ApiConfig.created) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('sent_fcm_token', token);
        } catch (_) {}
      }
    } catch (e) {
      try {
        if (e is ApiException && e.statusCode == ApiConfig.unauthorized) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pending_fcm_token', token);
          return;
        }
      } catch (_) {}
      try {
        if (e is ApiException) {
        } else {
        }
      } catch (_) {}
      try {
        customSnackBar('Notification registration', 'Failed to register device for notifications');
      } catch (_) {}
      rethrow;
    }
  }
  Future<void> retryPendingToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString('pending_fcm_token');
      if (pending == null || pending.isEmpty) return;
      try {
        await postFcmToken(pending);
        await prefs.remove('pending_fcm_token');
      } catch (e) {
      }
    } catch (e) {
    }
  }
  Future<void> deleteFcmToken([String? token]) async {
    try {
      if (token == null || token.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          token = prefs.getString('sent_fcm_token') ?? '';
        } catch (_) {
          token = '';
        }
      }

  if (token.isEmpty) return;

        final body = {'fcm_token': token}; // Updated to match server expectations
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await apiClient.delete(ApiConfig.notificationsFcmToken, data: body, options: options);

      final status = resp.statusCode ?? 0;
      if (status == ApiConfig.success || status == ApiConfig.created) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('sent_fcm_token');
        } catch (_) {}
      }
    } catch (e) {
      try {
        customSnackBar('Notification', 'Failed to unregister device for notifications');
      } catch (_) {}
      rethrow;
    }
  }
  Future<void> toggleNotifications(bool enabled) async {
    try {
  final body = {'enabled': enabled};
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await apiClient.put(ApiConfig.notificationsToggle, data: body, options: options);

      final status = resp.statusCode ?? 0;
      if (status == ApiConfig.success || status == ApiConfig.created) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notifications_enabled', enabled);
        } catch (_) {}
      }
    } catch (e) {
      try {
        customSnackBar('Notification', 'Failed to update notification settings');
      } catch (_) {}
      rethrow;
    }
  }
  Future<Map<String, dynamic>> fetchNotifications({int page = 1, int limit = 20}) async {
    try {
      final body = {'page': page, 'limit': limit};
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await apiClient.post(ApiConfig.notifications, data: body, options: options);

      final status = resp.statusCode ?? 0;
      if (status == ApiConfig.success || status == ApiConfig.created) {
        final data = resp.data;
        if (data is Map<String, dynamic>) {
          if (data[ApiConfig.dataKey] is List) {
            return {'items': data[ApiConfig.dataKey]};
          }
          final responseBody = (data[ApiConfig.dataKey] is Map<String, dynamic>) 
              ? Map<String, dynamic>.from(data[ApiConfig.dataKey]) 
              : data;
          if (responseBody['items'] == null) {
            // Backend may return a raw list in data
            if (data[ApiConfig.dataKey] is List) {
              responseBody['items'] = data[ApiConfig.dataKey];
            } else {
              responseBody['items'] = [];
            }
          }
          
          return responseBody;
        } else {
          return {'items': []};
        }
      } else {
        throw ApiException('Failed to fetch notifications', status);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getUnreadCount() async {
    final resp = await apiClient.get(
      ApiConfig.notificationsUnreadCount,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to load unread count', status);
    }
    final data = resp.data;
    if (data is Map) {
      final inner = data[ApiConfig.dataKey];
      if (inner is Map && inner['count'] != null) {
        return int.tryParse('${inner['count']}') ?? 0;
      }
      if (data['count'] != null) return int.tryParse('${data['count']}') ?? 0;
    }
    return 0;
  }

  Future<void> markAsRead(String id) async {
    if (id.isEmpty) return;
    final resp = await apiClient.put(
      '${ApiConfig.notifications}/$id/read',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to mark notification as read', status);
    }
  }

  Future<void> markAllAsRead() async {
    final resp = await apiClient.put(
      ApiConfig.notificationsReadAll,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to mark all as read', status);
    }
  }

  Future<void> deleteNotification(String id) async {
    if (id.isEmpty) return;
    final resp = await apiClient.delete(
      '${ApiConfig.notifications}/$id',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 204) {
      throw ApiException('Failed to delete notification', status);
    }
  }

  Future<void> deleteAllNotifications() async {
    final resp = await apiClient.delete(
      ApiConfig.notifications,
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 204) {
      throw ApiException('Failed to delete all notifications', status);
    }
  }
}
final notificationService = NotificationService();
