import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/video_call.dart';
import '../screens/video_call_incoming_screen.dart';
import '../services/socket_service.dart';
import '../services/video_call_service.dart';

/// Opens the full-screen incoming call UI from FCM / socket events.
class CallInviteHandler {
  CallInviteHandler._();
  static final CallInviteHandler instance = CallInviteHandler._();

  StreamSubscription<Map<String, dynamic>>? _requestSub;
  String? _activeIncomingCallId;
  bool _opening = false;

  void start() {
    _requestSub?.cancel();
    _requestSub = SocketService().onVideoCallRequest.listen((data) {
      final callId = (data['call_id'] ?? data['callId'] ?? '').toString();
      if (callId.isEmpty) return;
      openIncomingCall(callId);
    });
  }

  void stop() {
    _requestSub?.cancel();
    _requestSub = null;
  }

  void clearActiveIncoming(String? callId) {
    if (callId == null || callId == _activeIncomingCallId) {
      _activeIncomingCallId = null;
    }
  }

  Future<void> openIncomingCall(String callId) async {
    final id = callId.trim();
    if (id.isEmpty) return;
    if (_activeIncomingCallId == id || _opening) return;

    _opening = true;
    try {
      final call = await VideoCallService().getById(id);
      if (call.status != VideoCallStatus.pending) return;

      final ctx = Get.context;
      final nav = ctx != null ? Navigator.of(ctx, rootNavigator: true) : null;
      if (nav == null) return;

      _activeIncomingCallId = id;
      await nav.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoCallIncomingScreen(call: call),
        ),
      );
    } catch (_) {
      // Call may have expired / already handled.
    } finally {
      _opening = false;
      if (_activeIncomingCallId == id) _activeIncomingCallId = null;
    }
  }
}
