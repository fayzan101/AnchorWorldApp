import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/message.dart';
import '../models/chat_access.dart';
import '../config/api_config.dart';
import '../network/api_client.dart';
final Map<String, List<Message>> _inMemoryMessages = {};

class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final ApiClient _client = apiClient;

 
  Future<Map<String, dynamic>> sendMessage({
    required String receiverId,
    required String content,
  }) async {
    try {
      final body = {'content': content};
      final options = Options(headers: ApiConfig.jsonHeaders);
      
      final resp = await _client.post(
        '/messages/$receiverId',
        data: jsonEncode(body),
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to send message';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          } else if (bodyData.containsKey(ApiConfig.errorKey)) {
            final err = bodyData[ApiConfig.errorKey];
            if (err is String) {
              message = err;
            } else if (err is Map && err.values.isNotEmpty) {
              message = err.values.first.toString();
            }
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      throw ApiException('Invalid response from server', resp.statusCode);
    } catch (e) {
      rethrow;
    }
  }
  Future<Map<String, dynamic>> deleteMessage({
    required String messageId,
    required String scope, // me | everyone
  }) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.delete(
      '/messages/item/$messageId',
      queryParameters: {'scope': scope},
      options: options,
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created && status != 204) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to delete message';
      if (bodyData is Map) {
        message = (bodyData[ApiConfig.errorKey] ?? bodyData[ApiConfig.messageKey] ?? message).toString();
      }
      throw ApiException(message, status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      final inner = data[ApiConfig.dataKey];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return data;
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> editMessage({
    required String messageId,
    required String content,
  }) async {
    final options = Options(headers: ApiConfig.jsonHeaders);
    final resp = await _client.patch(
      '/messages/item/$messageId',
      data: jsonEncode({'content': content}),
      options: options,
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to edit message';
      if (bodyData is Map) {
        message = (bodyData[ApiConfig.errorKey] ?? bodyData[ApiConfig.messageKey] ?? message).toString();
      }
      throw ApiException(message, status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      final inner = data[ApiConfig.dataKey];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return data;
    }
    throw ApiException('Invalid response from server', status);
  }

  Future<Map<String, dynamic>> sendVoiceMessage({
    required String receiverId,
    required String filePath,
    int? durationMs,
    String? replyToMessageId,
  }) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: filePath.split(RegExp(r'[\\/]')).last),
      if (durationMs != null) 'duration_ms': durationMs,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    });
    final resp = await _client.post(
      '/messages/voice/$receiverId',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {
          // Let Dio set multipart boundary; keep auth from interceptor.
        },
      ),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final bodyData = resp.data;
      String message = resp.statusMessage ?? 'Failed to send voice message';
      if (bodyData is Map) {
        message = (bodyData[ApiConfig.errorKey] ?? bodyData[ApiConfig.messageKey] ?? message).toString();
      }
      throw ApiException(message, status);
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      final inner = data[ApiConfig.dataKey];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return data;
    }
    throw ApiException('Invalid response from server', status);
  }

  Future<bool> deleteConversation({
    required String userId,
  }) async {
    try {
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.delete(
        '/messages/$userId',
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status == ApiConfig.success || status == ApiConfig.created || status == 204) {
        return true;
      }
      String message = resp.statusMessage ?? 'Failed to delete conversation';
      final bodyData = resp.data;
      if (bodyData is Map<String, dynamic>) {
        if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
          message = bodyData[ApiConfig.messageKey];
        } else if (bodyData.containsKey(ApiConfig.errorKey)) {
          final err = bodyData[ApiConfig.errorKey];
          if (err is String) {
            message = err;
          } else if (err is Map && err.values.isNotEmpty) {
            message = err.values.first.toString();
          }
        }
      }
      throw ApiException(message, status);
    } catch (e) {
      rethrow;
    }
  }
  Future<Map<String, dynamic>> getMessages({
    required String userId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.get(
        '/messages/$userId',
        queryParameters: queryParams,
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to fetch messages';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        var result = data['data'];
        if (result is Map<String, dynamic>) {
          final items = result['items'] ?? result['messages'] ?? result['data'];
          final pagination = result['pagination'] ?? {};
          if (items is List) {
            return {
              'items': items.cast<Map<String, dynamic>>(),
              'pagination': pagination,
            };
          }
          return {'items': [], 'pagination': {}};
        } else if (result is List) {
          return {
            'items': result.cast<Map<String, dynamic>>(),
            'pagination': {},
          };
        }
        final items = data['items'] ?? data['messages'] ?? data['data'];
        if (items is List) {
          return {
            'items': items.cast<Map<String, dynamic>>(),
            'pagination': data['pagination'] ?? {},
          };
        }
        
        return {'items': [], 'pagination': {}};
      } else if (data is List) {
        return {
          'items': data.cast<Map<String, dynamic>>(),
          'pagination': {},
        };
      }

      return {'items': [], 'pagination': {}};
    } catch (e) {
      rethrow;
    }
  }
  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.get(
        '/messages/conversations',
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to fetch conversations';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        var items = data['data'];
        if (items is Map<String, dynamic>) {
          items = items['conversations'] ?? items['data'] ?? items['items'];
        } else if (items == null) {
          items = data['conversations'] ?? data['items'];
        }
        
        if (items is List) {
          return items
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        return [];
      } else if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }
  Future<Map<String, dynamic>> markMessageAsRead({
    required String messageId,
  }) async {
    try {
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.put(
        '/messages/$messageId/read',
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to mark message as read';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          } else if (bodyData.containsKey(ApiConfig.errorKey)) {
            final err = bodyData[ApiConfig.errorKey];
            if (err is String) {
              message = err;
            } else if (err is Map && err.values.isNotEmpty) {
              message = err.values.first.toString();
            }
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      return {'success': true};
    } catch (e) {
      rethrow;
    }
  }
  Future<Map<String, dynamic>> markAllMessagesAsRead({
    required String senderUserId,
  }) async {
    try {
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.put(
        '/messages/$senderUserId/read-all',
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to mark all messages as read';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          } else if (bodyData.containsKey(ApiConfig.errorKey)) {
            final err = bodyData[ApiConfig.errorKey];
            if (err is String) {
              message = err;
            } else if (err is Map && err.values.isNotEmpty) {
              message = err.values.first.toString();
            }
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      return {'success': true};
    } catch (e) {
      rethrow;
    }
  }
  Future<int> getUnreadCount({
    required String userId,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'userId': userId,
      };
      
      final options = Options(headers: ApiConfig.jsonHeaders);
      final resp = await _client.get(
        '/messages/unread-count',
        queryParameters: queryParams,
        options: options,
      );

      final status = resp.statusCode ?? 0;
      if (status != ApiConfig.success && status != ApiConfig.created) {
        final bodyData = resp.data;
        String message = resp.statusMessage ?? 'Failed to fetch unread count';
        if (bodyData is Map<String, dynamic>) {
          if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
            message = bodyData[ApiConfig.messageKey];
          } else if (bodyData.containsKey(ApiConfig.errorKey)) {
            final err = bodyData[ApiConfig.errorKey];
            if (err is String) {
              message = err;
            } else if (err is Map && err.values.isNotEmpty) {
              message = err.values.first.toString();
            }
          }
        }
        throw ApiException(message, status);
      }

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        var result = data['data'];
        if (result is Map<String, dynamic>) {
          final count = result['count'] ?? result['unread_count'] ?? result['unreadCount'];
          if (count is int) {
            return count;
          } else if (count is String) {
            return int.tryParse(count) ?? 0;
          }
        } else if (result is int) {
          return result;
        }
        final count = data['count'] ?? data['unread_count'] ?? data['unreadCount'];
        if (count is int) {
          return count;
        } else if (count is String) {
          return int.tryParse(count) ?? 0;
        }
        
        return 0;
      } else if (data is int) {
        
        return data;
      }

      return 0;
    } catch (e) {
      rethrow;
    }
  }
    Future<int> getTotalUnreadCount() async {
      try {
        final options = Options(headers: ApiConfig.jsonHeaders);
        final resp = await _client.get(
          '/messages/unread-count',
          options: options,
        );

        final status = resp.statusCode ?? 0;
        if (status != ApiConfig.success && status != ApiConfig.created) {
          final bodyData = resp.data;
          String message = resp.statusMessage ?? 'Failed to fetch total unread count';
          if (bodyData is Map<String, dynamic>) {
            if (bodyData.containsKey(ApiConfig.messageKey) && bodyData[ApiConfig.messageKey] is String) {
              message = bodyData[ApiConfig.messageKey];
            } else if (bodyData.containsKey(ApiConfig.errorKey)) {
              final err = bodyData[ApiConfig.errorKey];
              if (err is String) {
                message = err;
              } else if (err is Map && err.values.isNotEmpty) {
                message = err.values.first.toString();
              }
            }
          }
          throw ApiException(message, status);
        }
  final data = resp.data;

        if (data is Map<String, dynamic>) {
          var result = data['data'];
          if (result is Map<String, dynamic>) {
            final count = result['count'] ?? result['total'] ?? result['unread_count'] ?? result['unreadCount'];
            if (count is int) {
              return count;
            } else if (count is String) {
              return int.tryParse(count) ?? 0;
            }
          } else if (result is int) {
            return result;
          }
          final count = data['count'] ?? data['total'] ?? data['unread_count'] ?? data['unreadCount'];
          if (count is int) {
            return count;
          } else if (count is String) {
            return int.tryParse(count) ?? 0;
          }

          return 0;
        } else if (data is int) {
          return data;
        }

        return 0;
      } catch (e) {
        return 0;
      }
    }

  static void clearInMemory() {
    _inMemoryMessages.clear();
  }

  static List<Message> getConversation(String a, String b) {
    final key = _convKey(a, b);
    return _inMemoryMessages.putIfAbsent(key, () => []);
  }

  static void send(String from, String to, String text) {
    final key = _convKey(from, to);
    final list = _inMemoryMessages.putIfAbsent(key, () => []);
    final msg = Message(fromId: from, toId: to, text: text, timestamp: DateTime.now());
    list.add(msg);
  }

  static String _convKey(String a, String b) => (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';

  Future<ChatAccess> getChatAccess(String peerId) async {
    final resp = await _client.get(
      '/messages/chat-access/$peerId',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      throw ApiException('Failed to load chat access', status);
    }
    final data = resp.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map[ApiConfig.dataKey];
      if (inner is Map) {
        return ChatAccess.fromJson(Map<String, dynamic>.from(inner));
      }
      return ChatAccess.fromJson(map);
    }
    throw ApiException('Invalid chat access response', status);
  }

  Future<ChatAccess> unlockChat(String peerId) async {
    final resp = await _client.post(
      '/messages/unlock/$peerId',
      options: Options(headers: ApiConfig.jsonHeaders),
    );
    final status = resp.statusCode ?? 0;
    if (status != ApiConfig.success && status != ApiConfig.created) {
      final body = resp.data;
      String message = 'Failed to unlock chat';
      if (body is Map) {
        message = (body[ApiConfig.errorKey] ?? body[ApiConfig.messageKey] ?? message).toString();
      }
      throw ApiException(message, status);
    }
    final data = resp.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map[ApiConfig.dataKey];
      if (inner is Map) {
        return ChatAccess.fromJson(Map<String, dynamic>.from(inner));
      }
      return ChatAccess.fromJson(map);
    }
    throw ApiException('Invalid unlock response', status);
  }
}

final MessageService messageService = MessageService();
