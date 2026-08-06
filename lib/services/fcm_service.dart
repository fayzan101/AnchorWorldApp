import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_service.dart';
import '../network/api_client.dart';
import 'notification_service.dart';
import '../screens/post_detail_screen.dart';
import '../screens/points_wallet_screen.dart';
import '../screens/requests_screen.dart';
import '../utils/open_user_profile.dart';
import '../utils/call_invite_handler.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('auth_token');
    if (storedToken != null && storedToken.isNotEmpty) {
      apiClient.setAuthTokenInMemory(storedToken);
    }
    try {
      await messageService.getConversations();
    } catch (_) {}
  } catch (_) {}
}

class FcmService {
  FcmService._();
  static final FcmService _instance = FcmService._();
  factory FcmService() => _instance;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String?>? _tokenSub;
  final StreamController<void> _notificationArrivedCtrl = StreamController<void>.broadcast();

  Stream<void> get onNotificationArrived => _notificationArrivedCtrl.stream;
  final StreamController<void> _conversationsUpdatedCtrl = StreamController<void>.broadcast();

  Stream<void> get onConversationsUpdated => _conversationsUpdatedCtrl.stream;
  void notifyConversationsUpdated() {
    try {
      _conversationsUpdatedCtrl.add(null);
    } catch (_) {}
  }

  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications',
    importance: Importance.high,
  );

  Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await Firebase.initializeApp();
    } catch (_) {}

    await _initLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Android 13+ notification permission
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } catch (_) {}

    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        try {
          await notificationService.postFcmToken(token);
        } catch (_) {}
      }
    } catch (_) {}

    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      try {
        await notificationService.postFcmToken(newToken);
      } catch (_) {}
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final type = (data['type'] ?? '').toString().toLowerCase();
      final screen = (data['screen'] ?? '').toString().toLowerCase();
      final action = (data['action'] ?? '').toString().toLowerCase();
      final callId = (data['callId'] ?? data['call_id'] ?? '').toString();

      // Live incoming call — open ringing UI immediately (don't wait for tap).
      if (callId.isNotEmpty &&
          (screen == 'videointro' || type.contains('video_call')) &&
          action != 'cancelled' &&
          action != 'ended' &&
          !type.contains('accepted') &&
          !type.contains('rejected')) {
        CallInviteHandler.instance.openIncomingCall(callId);
      }

      _showLocalNotification(message);
      try {
        _notificationArrivedCtrl.add(null);
      } catch (_) {}
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      try {
        _handleNotificationNavigation(message.data);
      } catch (_) {}
      try {
        _notificationArrivedCtrl.add(null);
      } catch (_) {}
    });

    messaging.getInitialMessage().then((message) {
      if (message != null) {
        try {
          _handleNotificationNavigation(message.data);
        } catch (_) {}
        try {
          _notificationArrivedCtrl.add(null);
        } catch (_) {}
      }
    });
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _navigateForData(data);
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
  }

  Future<void> unregisterToken([String? token]) async {
    try {
      String? tk = token;
      if (tk == null || tk.isEmpty) {
        tk = await FirebaseMessaging.instance.getToken();
      }
      if (tk != null && tk.isNotEmpty) {
        await notificationService.deleteFcmToken(tk);
      }
    } catch (_) {}
  }

  Future<void> _initLocalNotifications() async {
    try {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _local.initialize(initSettings, onDidReceiveNotificationResponse: (response) {
        try {
          if (response.payload != null && response.payload!.isNotEmpty) {
            final Map<String, dynamic> data = jsonDecode(response.payload!);
            _navigateForData(data);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notif = message.notification;
      final data = message.data;
      if (notif == null) return;

      final androidDetails = AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      final platform = NotificationDetails(android: androidDetails, iOS: iosDetails);

      final payload = data.isNotEmpty ? jsonEncode(data) : null;
      await _local.show(
        notif.hashCode,
        notif.title,
        notif.body,
        platform,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Routes using backend `data.screen` when present:
  /// Chat | Post | Profile | VideoIntro | Points | ConnectionRequests
  void _navigateForData(Map<String, dynamic> data) {
    try {
      final screen = (data['screen'] ?? '').toString().toLowerCase().trim();
      final type = (data['type'] ?? data['notification_type'] ?? data['action'] ?? '')
          .toString()
          .toLowerCase();

      final senderId = (data['senderId'] ??
              data['sender_id'] ??
              data['peerId'] ??
              data['peer_id'] ??
              data['userId'] ??
              data['user_id'])
          ?.toString();
      final senderName = (data['senderName'] ??
              data['sender_name'] ??
              data['peerName'] ??
              data['peer_name'] ??
              data['userName'] ??
              data['user_name'])
          ?.toString();
      final postId = (data['postId'] ?? data['post_id'] ?? data['reference_id'])?.toString();
      final callId = (data['callId'] ?? data['call_id'])?.toString();

      final isChat = screen == 'chat' ||
          type.contains('new_message') ||
          type == 'message' ||
          data.containsKey('conversationId') ||
          data.containsKey('conversation_id');

      if (isChat || screen == 'chat') {
        _openChat(senderId, senderName);
        return;
      }

      if (screen == 'post' || type.contains('post_liked') || type.contains('post_commented')) {
        if (postId != null && postId.isNotEmpty) {
          Get.to(() => PostDetailScreen(postId: postId));
          return;
        }
      }

      if (screen == 'profile') {
        final userId = senderId;
        if (userId != null && userId.isNotEmpty) {
          final ctx = Get.context;
          if (ctx != null) {
            openUserProfile(ctx, userId: userId, fallbackName: senderName ?? 'Member');
            return;
          }
        }
      }

      if (screen == 'connectionrequests' ||
          type.contains('friend_request') ||
          type.contains('connection_request')) {
        Get.to(() => const RequestsScreen(currentUserId: 'me'));
        return;
      }

      if (screen == 'points' || type.contains('points')) {
        Get.to(() => const PointsWalletScreen());
        return;
      }

      if (screen == 'videointro' || type.contains('video_call') || type.contains('video_intro')) {
        final action = (data['action'] ?? '').toString().toLowerCase();
        // Cancelled / ended — don't reopen a ringing screen.
        if (action == 'cancelled' || action == 'ended') {
          return;
        }
        if (callId != null && callId.isNotEmpty && !type.contains('accepted') && !type.contains('rejected')) {
          CallInviteHandler.instance.openIncomingCall(callId);
          return;
        }
        Get.toNamed('/notifications');
        return;
      }

      // Default: notifications inbox
      Get.toNamed('/notifications');
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('pending_open_screen', 'notifications');
      });
    } catch (_) {
      try {
        Get.toNamed('/notifications');
      } catch (_) {}
    }
  }

  void _openChat(String? peerId, String? peerName) {
    try {
      Get.offAllNamed('/home', arguments: {'openTab': 'chat'});
    } catch (_) {}
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('pending_open_tab', 'chat');
      if (peerId != null && peerId.isNotEmpty) prefs.setString('pending_chat_id', peerId);
      if (peerName != null && peerName.isNotEmpty) prefs.setString('pending_chat_name', peerName);
    });
  }
}

final fcmService = FcmService();
