import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _connecting = false;
  final Set<String> _presenceSubscriptions = <String>{};
  String? _activeChatPeerId;

  final _newMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageSentCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageErrorCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _userTypingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReadCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _userStatusCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _followRequestCancelledCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _chatUnlockedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageEditedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _videoCallRequestCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _videoCallAcceptedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _videoCallCancelledCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _videoCallRejectedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _videoCallEndedCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageSent => _messageSentCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageError => _messageErrorCtrl.stream;
  Stream<Map<String, dynamic>> get onUserTyping => _userTypingCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageRead => _messageReadCtrl.stream;
  Stream<Map<String, dynamic>> get onUserStatusChanged => _userStatusCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted => _messageDeletedCtrl.stream;
  Stream<Map<String, dynamic>> get onFollowRequestCancelled =>
      _followRequestCancelledCtrl.stream;
  Stream<Map<String, dynamic>> get onChatUnlocked => _chatUnlockedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageEdited => _messageEditedCtrl.stream;
  Stream<Map<String, dynamic>> get onVideoCallRequest => _videoCallRequestCtrl.stream;
  Stream<Map<String, dynamic>> get onVideoCallAccepted => _videoCallAcceptedCtrl.stream;
  Stream<Map<String, dynamic>> get onVideoCallCancelled => _videoCallCancelledCtrl.stream;
  Stream<Map<String, dynamic>> get onVideoCallRejected => _videoCallRejectedCtrl.stream;
  Stream<Map<String, dynamic>> get onVideoCallEnded => _videoCallEndedCtrl.stream;

  void requestUserStatus(String userId) {
    if (isConnected) {
      _socket!.emit('get_user_status', {'user_id': userId});
    }
  }

  bool get isConnected => _socket?.connected == true;

  Future<void> ensureConnection() async {
    if (!isConnected) {
      await connect();
    } else {
      _emitAllPresenceSubscriptions();
    }
  }

  Future<void> connect() async {
    if (_connecting) return;
    if (isConnected) {
      _emitAllPresenceSubscriptions();
      return;
    }
    _connecting = true;

    try {
      var base = ApiConfig.baseUrl;
      if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
      final uri = Uri.parse(base);
      String scheme;
      if (uri.scheme == 'https') {
        scheme = 'wss';
      } else if (uri.scheme == 'http') {
        scheme = 'ws';
      } else if (uri.scheme == 'wss' || uri.scheme == 'ws') {
        scheme = uri.scheme;
      } else {
        scheme = 'ws';
      }
      final socketUrl = Uri(
        scheme: scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/',
      ).toString();

      final token = await _getAuthToken();
      final headers = <String, dynamic>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final opts = IO.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(500)
          .setTimeout(20000)
          .setExtraHeaders(headers)
          .setAuth(token != null && token.isNotEmpty ? {'token': token} : {})
          .build();

      // Tear down any stale socket before creating a new one.
      try {
        _socket?.clearListeners();
        _socket?.disconnect();
        _socket?.dispose();
      } catch (_) {}

      _socket = IO.io(socketUrl, opts);

      _socket!.on('connect', (_) {
        _emitAllPresenceSubscriptions();
        _reemitActiveChat();
      });
      _socket!.on('reconnect', (_) {
        _emitAllPresenceSubscriptions();
        _reemitActiveChat();
      });
      _socket!.on('new_message', (data) => _pushMap(_newMessageCtrl, data));
      _socket!.on('message_sent', (data) => _pushMap(_messageSentCtrl, data));
      _socket!.on('message_error', (data) => _pushMap(_messageErrorCtrl, data));
      _socket!.on('user_typing', (data) => _pushMap(_userTypingCtrl, data));
      _socket!.on('message_read', (data) => _pushMap(_messageReadCtrl, data));
      _socket!.on('message_deleted', (data) => _pushMap(_messageDeletedCtrl, data));
      _socket!.on('user_status_changed', (data) => _pushMap(_userStatusCtrl, data));
      _socket!.on('user_status_initial', (data) => _pushMap(_userStatusCtrl, data));
      _socket!.on('follow_request_cancelled', (data) => _pushMap(_followRequestCancelledCtrl, data));
      _socket!.on('chat_unlocked', (data) => _pushMap(_chatUnlockedCtrl, data));
      _socket!.on('message_edited', (data) => _pushMap(_messageEditedCtrl, data));
      _socket!.on('video_call_request', (data) => _pushMap(_videoCallRequestCtrl, data));
      _socket!.on('video_call_accepted', (data) => _pushMap(_videoCallAcceptedCtrl, data));
      _socket!.on('video_call_cancelled', (data) => _pushMap(_videoCallCancelledCtrl, data));
      _socket!.on('video_call_rejected', (data) => _pushMap(_videoCallRejectedCtrl, data));
      _socket!.on('video_call_ended', (data) => _pushMap(_videoCallEndedCtrl, data));

      if (!_socket!.connected) {
        _socket!.connect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _emitAllPresenceSubscriptions() {
    try {
      if (!isConnected) return;
      for (final uid in _presenceSubscriptions) {
        _socket!.emit('subscribe_user_status', {'user_id': uid});
        _socket!.emit('get_user_status', {'user_id': uid});
      }
    } catch (_) {}
  }

  void _reemitActiveChat() {
    final peerId = _activeChatPeerId;
    if (peerId == null || peerId.isEmpty || !isConnected) return;
    try {
      _socket!.emit('chat_open', {'peer_id': peerId});
    } catch (_) {}
  }

  /// Tell the server this device is viewing a chat so message notifications are suppressed.
  void setActiveChat(String peerId) {
    _activeChatPeerId = peerId;
    if (!isConnected) return;
    try {
      _socket!.emit('chat_open', {'peer_id': peerId});
    } catch (_) {}
  }

  void clearActiveChat([String? peerId]) {
    final current = _activeChatPeerId;
    if (peerId != null && peerId.isNotEmpty && current != null && current != peerId) {
      return;
    }
    final closing = peerId ?? current;
    _activeChatPeerId = null;
    if (!isConnected || closing == null || closing.isEmpty) return;
    try {
      _socket!.emit('chat_close', {'peer_id': closing});
    } catch (_) {}
  }

  Future<void> disconnect() async {
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  void sendMessage({
    required String toUserId,
    required String content,
    String? messageId,
    String? roomId,
    String? replyToMessageId,
    Map<String, dynamic>? extra,
  }) {
    if (!isConnected) {
      _messageErrorCtrl.add({
        'success': false,
        'error': 'Not connected',
        'client_message_id': messageId,
      });
      return;
    }
    _socket!.emit('send_message', {
      'receiver_id': toUserId,
      'to': toUserId,
      'content': content,
      if (messageId != null) 'client_message_id': messageId,
      if (messageId != null) 'message_id': messageId,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (roomId != null) 'room_id': roomId,
      if (extra != null) ...extra,
    });
  }

  void typingStart({required String toUserId, String? roomId}) {
    if (!isConnected) return;
    _socket!.emit('typing_start', {
      'receiver_id': toUserId,
      'to': toUserId,
      if (roomId != null) 'room_id': roomId,
    });
  }

  void typingStop({required String toUserId, String? roomId}) {
    if (!isConnected) return;
    _socket!.emit('typing_stop', {
      'receiver_id': toUserId,
      'to': toUserId,
      if (roomId != null) 'room_id': roomId,
    });
  }

  void markAsRead({required String messageId, String? roomId}) {
    if (!isConnected) return;
    _socket!.emit('mark_as_read', {
      'message_id': messageId,
      if (roomId != null) 'room_id': roomId,
    });
  }

  void subscribeUserStatus(String userId) {
    _presenceSubscriptions.add(userId);
    if (isConnected) {
      _socket!.emit('subscribe_user_status', {'user_id': userId});
      _socket!.emit('get_user_status', {'user_id': userId});
    }
  }

  void unsubscribeUserStatus(String userId) {
    _presenceSubscriptions.remove(userId);
    if (!isConnected) return;
    _socket!.emit('unsubscribe_user_status', {'user_id': userId});
  }

  void _pushMap(StreamController<Map<String, dynamic>> ctrl, dynamic data) {
    try {
      if (data is Map) {
        try {
          ctrl.add(Map<String, dynamic>.from(data as Map));
        } catch (_) {
          ctrl.add(Map<String, dynamic>.from(
            data.map((k, v) => MapEntry(k.toString(), v)),
          ));
        }
      } else {
        ctrl.add({'data': data});
      }
    } catch (_) {
      try {
        ctrl.add({'data': data});
      } catch (_) {}
    }
  }

  Future<String?> _getAuthToken() async {
    try {
      final token = await _readPrefs('auth_token');
      if (token != null && token.isNotEmpty) return token;
      final cached = AuthService().getCachedProfile();
      if (cached != null) {
        final t = cached['access_token'] ?? cached['token'];
        if (t is String && t.isNotEmpty) return t;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _readPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _newMessageCtrl.close();
    _messageSentCtrl.close();
    _messageErrorCtrl.close();
    _userTypingCtrl.close();
    _messageReadCtrl.close();
    _userStatusCtrl.close();
    _messageDeletedCtrl.close();
    _followRequestCancelledCtrl.close();
    _chatUnlockedCtrl.close();
    _messageEditedCtrl.close();
    _videoCallRequestCtrl.close();
    _videoCallAcceptedCtrl.close();
    _videoCallCancelledCtrl.close();
    _videoCallRejectedCtrl.close();
    _videoCallEndedCtrl.close();
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
  }
}
