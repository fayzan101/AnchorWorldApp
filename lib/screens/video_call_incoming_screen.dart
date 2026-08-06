import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_call.dart';
import '../network/api_client.dart' show ApiException;
import '../services/socket_service.dart';
import '../services/video_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/call_invite_handler.dart';
import '../utils/custom_snackbar.dart';
import 'video_call_screen.dart';

/// Full-screen incoming voice/video call request (phone-app style).
class VideoCallIncomingScreen extends StatefulWidget {
  final VideoCall call;

  const VideoCallIncomingScreen({super.key, required this.call});

  @override
  State<VideoCallIncomingScreen> createState() => _VideoCallIncomingScreenState();
}

class _VideoCallIncomingScreenState extends State<VideoCallIncomingScreen>
    with SingleTickerProviderStateMixin {
  final _service = VideoCallService();
  bool _busy = false;
  bool _closing = false;
  late AnimationController _pulse;
  Timer? _statusPoll;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  StreamSubscription<Map<String, dynamic>>? _endedSub;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _statusPoll = Timer.periodic(const Duration(seconds: 2), (_) => _checkStillPending());
    _cancelSub = SocketService().onVideoCallCancelled.listen(_onRemoteClosed);
    _endedSub = SocketService().onVideoCallEnded.listen(_onRemoteClosed);
    final expires = widget.call.expiresAt;
    if (expires != null) {
      final wait = expires.difference(DateTime.now());
      if (!wait.isNegative) {
        Future.delayed(wait, () {
          if (mounted && !_busy) _closeQuietly();
        });
      }
    }
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    _cancelSub?.cancel();
    _endedSub?.cancel();
    _pulse.dispose();
    CallInviteHandler.instance.clearActiveIncoming(widget.call.id);
    super.dispose();
  }

  String get _callerName => widget.call.caller?.fullName ?? 'A connection';
  bool get _isVoice => widget.call.isVoice;

  void _onRemoteClosed(Map<String, dynamic> data) {
    final id = (data['call_id'] ?? data['callId'] ?? '').toString();
    if (id.isEmpty || id != widget.call.id) return;
    _closeQuietly();
  }

  Future<void> _checkStillPending() async {
    if (_busy || _closing || !mounted) return;
    try {
      final call = await _service.getById(widget.call.id);
      if (!mounted) return;
      if (call.status != VideoCallStatus.pending) {
        _closeQuietly();
      }
    } catch (_) {}
  }

  void _closeQuietly() {
    if (_closing || !mounted) return;
    _closing = true;
    _statusPoll?.cancel();
    Navigator.of(context).maybePop();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final call = await _service.accept(widget.call.id);
      if (!mounted) return;
      _statusPoll?.cancel();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VideoCallScreen(call: call, isCaller: false)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is ApiException ? (e.message ?? 'Could not accept') : e.toString();
      // Caller already cancelled / expired — just leave.
      if (msg.toLowerCase().contains('pending') ||
          msg.toLowerCase().contains('not found') ||
          msg.toLowerCase().contains('expired')) {
        _closeQuietly();
        return;
      }
      customSnackBar('Error', msg, type: SnackType.error);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.reject(widget.call.id);
    } catch (_) {}
    if (!mounted) return;
    _closeQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.call.caller?.profilePicture ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (image.isNotEmpty)
            Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.72),
                    Colors.black.withOpacity(0.88),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                Text(
                  _isVoice ? 'Incoming voice call' : 'Incoming video call',
                  style: AppTextStyles.ui(size: 14, weight: FontWeight.w600, color: Colors.white70),
                ),
                const Spacer(flex: 2),
                ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.05).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 36),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 72,
                      backgroundColor: AppColors.chipIdle,
                      backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                      child: image.isEmpty
                          ? Text(
                              _callerName.isNotEmpty ? _callerName[0].toUpperCase() : '?',
                              style: AppTextStyles.ui(size: 44, weight: FontWeight.w800, color: AppColors.primary),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _callerName,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.ui(size: 28, weight: FontWeight.w800, color: AppColors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _isVoice ? 'Voice call' : 'Video call',
                  style: AppTextStyles.ui(size: 15, color: Colors.white70),
                ),
                const Spacer(flex: 3),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundAction(
                          color: const Color(0xFFE53935),
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          onTap: _decline,
                        ),
                        _RoundAction(
                          color: const Color(0xFF2ECC71),
                          icon: _isVoice ? Icons.call_rounded : Icons.videocam_rounded,
                          label: 'Accept',
                          onTap: _accept,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: AppTextStyles.ui(size: 13, weight: FontWeight.w600, color: Colors.white70)),
      ],
    );
  }
}
