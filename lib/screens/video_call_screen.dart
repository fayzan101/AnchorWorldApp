import 'dart:async';
import 'dart:io' show Platform;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/video_call.dart';
import '../services/video_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/points_toast.dart';
import '../services/socket_service.dart';

/// Active voice/video call — Agora when available, timer UI otherwise.
class VideoCallScreen extends StatefulWidget {
  final VideoCall call;
  final bool isCaller;

  const VideoCallScreen({
    super.key,
    required this.call,
    required this.isCaller,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _service = VideoCallService();

  RtcEngine? _engine;
  int? _remoteUid;
  bool _joined = false;
  bool _muted = false;
  bool _videoOff = false;
  bool _ending = false;
  bool _agoraReady = false;
  String? _statusNote;
  late VideoCall _call;

  Timer? _ticker;
  Timer? _pendingPoll;
  Duration _remaining = Duration.zero;
  DateTime? _sessionStarted;
  bool _countdownStarted = false;
  StreamSubscription<Map<String, dynamic>>? _endedSub;
  StreamSubscription<Map<String, dynamic>>? _rejectedSub;
  StreamSubscription<Map<String, dynamic>>? _cancelledSub;

  @override
  void initState() {
    super.initState();
    _call = widget.call;
    _remaining = Duration(minutes: _call.durationMinutes);
    _endedSub = SocketService().onVideoCallEnded.listen(_onRemoteLifecycle);
    _rejectedSub = SocketService().onVideoCallRejected.listen(_onRemoteLifecycle);
    _cancelledSub = SocketService().onVideoCallCancelled.listen(_onRemoteLifecycle);
    if (_call.status == VideoCallStatus.active) {
      _startSession();
    } else if (_call.status == VideoCallStatus.pending && widget.isCaller) {
      _statusNote = 'Waiting for them to accept…';
      _pendingPoll = Timer.periodic(const Duration(seconds: 3), (_) => _pollPending());
      _scheduleExpireWatch();
    } else {
      _statusNote = 'Connecting…';
      _startSession();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pendingPoll?.cancel();
    _endedSub?.cancel();
    _rejectedSub?.cancel();
    _cancelledSub?.cancel();
    _leaveAgora();
    super.dispose();
  }

  void _onRemoteLifecycle(Map<String, dynamic> data) {
    final id = (data['call_id'] ?? data['callId'] ?? '').toString();
    if (id.isEmpty || id != _call.id) return;
    _forceCloseRemote();
  }

  void _forceCloseRemote() {
    if (_ending || !mounted) return;
    _ending = true;
    _ticker?.cancel();
    _pendingPoll?.cancel();
    _leaveAgora();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _scheduleExpireWatch() {
    final expires = _call.expiresAt;
    if (expires == null) return;
    final wait = expires.difference(DateTime.now());
    if (wait.isNegative) return;
    Future.delayed(wait, () {
      if (!mounted || _call.status != VideoCallStatus.pending) return;
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _pollPending() async {
    // Caller waits on this screen; when callee accepts, history/token becomes joinable.
    // Re-fetch token attempts once call is active via getToken.
    try {
      final token = await _service.getToken(_call.id);
      if (!mounted) return;
      if (_call.status == VideoCallStatus.pending) {
        setState(() {
          _call = VideoCall(
            id: _call.id,
            callerId: _call.callerId,
            calleeId: _call.calleeId,
            status: VideoCallStatus.active,
            callType: _call.callType,
            durationMinutes: _call.durationMinutes,
            pointsSpent: _call.pointsSpent,
            channelName: token.channelName,
            startedAt: DateTime.now(),
            expiresAt: _call.expiresAt,
            createdAt: _call.createdAt,
            caller: _call.caller,
            callee: _call.callee,
          );
          _statusNote = null;
        });
        _pendingPoll?.cancel();
        await _joinWithToken(token);
        // Countdown starts when the other person joins Agora (see onUserJoined).
      }
    } catch (_) {
      // Still pending or expired — ignore until expiry handler pops.
    }
  }

  Future<void> _startSession() async {
    try {
      final token = await _service.getToken(_call.id);
      if (!mounted) return;
      await _joinWithToken(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusNote = 'Connecting…';
        _agoraReady = false;
        _joined = true;
      });
      // Fallback: if Agora can't start, still allow timed session after a short grace.
      _beginCountdown();
    }
  }

  bool get _canUseAgora {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> _joinWithToken(VideoCallToken token) async {
    if (!_canUseAgora) {
      setState(() {
        _agoraReady = false;
        _statusNote = 'Live video is available on mobile';
        _joined = true;
      });
      _beginCountdown();
      return;
    }

    try {
      if (_call.isVoice) {
        await Permission.microphone.request();
      } else {
        await [Permission.microphone, Permission.camera].request();
      }
      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: token.appId));
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted) return;
            setState(() {
              _joined = true;
              _agoraReady = true;
              _statusNote = widget.isCaller || _remoteUid != null
                  ? null
                  : 'Waiting for them to join…';
            });
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted) return;
            setState(() {
              _remoteUid = remoteUid;
              _statusNote = null;
            });
            // 5-min timer starts only once both sides are connected.
            _beginCountdown();
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (!mounted) return;
            if (_remoteUid == remoteUid) {
              setState(() => _remoteUid = null);
              // Peer left — close this screen quietly.
              _endCall(auto: true, silent: true);
            }
          },
        ),
      );
      if (_call.isVoice) {
        await engine.enableAudio();
        await engine.disableVideo();
      } else {
        await engine.enableVideo();
        await engine.startPreview();
      }
      await engine.joinChannel(
        token: token.token,
        channelId: token.channelName,
        uid: token.uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      _engine = engine;
      if (mounted) setState(() => _agoraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _agoraReady = false;
        _joined = true;
        _statusNote = _call.isVoice
            ? 'Connected (audio only)'
            : 'Connected without camera preview';
      });
    }
  }

  void _beginCountdown() {
    if (_countdownStarted) return;
    _countdownStarted = true;
    _sessionStarted ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_sessionStarted!);
      final total = Duration(minutes: _call.durationMinutes);
      final left = total - elapsed;
      if (left <= Duration.zero) {
        setState(() => _remaining = Duration.zero);
        _endCall(auto: true, silent: true);
      } else {
        setState(() => _remaining = left);
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _leaveAgora() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (_) {}
    _engine = null;
  }

  Future<void> _endCall({bool auto = false, bool silent = false}) async {
    if (_ending) return;
    setState(() => _ending = true);
    _ticker?.cancel();
    _pendingPoll?.cancel();

    if (_call.status == VideoCallStatus.pending && widget.isCaller) {
      try {
        await _service.cancel(_call.id);
      } catch (_) {}
      await _leaveAgora();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }

    try {
      await _service.end(_call.id);
      if (!silent && !auto) {
        final elapsed = _sessionStarted == null
            ? 0
            : DateTime.now().difference(_sessionStarted!).inSeconds;
        if (elapsed > 30) {
          showPointsToast(100, reason: 'Call complete!');
        }
      }
    } catch (_) {
      // Ignore "not active" / already ended — just leave the screen.
    }
    await _leaveAgora();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  String get _peerName {
    if (widget.isCaller) return _call.callee?.fullName ?? 'Connection';
    return _call.caller?.fullName ?? 'Connection';
  }

  String? get _peerAvatar {
    if (widget.isCaller) return _call.callee?.profilePicture;
    return _call.caller?.profilePicture;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Duration get _elapsed {
    if (_sessionStarted == null) return Duration.zero;
    return DateTime.now().difference(_sessionStarted!);
  }

  @override
  Widget build(BuildContext context) {
    final avatar = (_peerAvatar ?? '').trim();
    final connected = _joined && (_remoteUid != null || !_agoraReady);
    final showElapsed = _countdownStarted && _sessionStarted != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: (!_call.isVoice && _agoraReady && _remoteUid != null && !_videoOff)
                  ? AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(uid: _remoteUid),
                        connection: RtcConnection(channelId: _call.channelName),
                      ),
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1A2330), Color(0xFF0B0F14)],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 56,
                                backgroundColor: AppColors.chipIdle,
                                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                child: avatar.isEmpty
                                    ? Text(
                                        _peerName.isNotEmpty ? _peerName[0].toUpperCase() : '?',
                                        style: AppTextStyles.ui(
                                          size: 36,
                                          weight: FontWeight.w800,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _peerName,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.ui(size: 24, weight: FontWeight.w800, color: AppColors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusNote ??
                                  (_call.status == VideoCallStatus.pending
                                      ? 'Calling…'
                                      : connected
                                          ? (_call.isVoice ? 'Voice connected' : 'Connected')
                                          : 'Connecting…'),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.ui(size: 15, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (_agoraReady && !_call.isVoice && !_videoOff)
              Positioned(
                right: 16,
                top: 72,
                width: 108,
                height: 148,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (!_call.isVoice)
                    Expanded(
                      child: Text(
                        _peerName,
                        style: AppTextStyles.ui(size: 16, weight: FontWeight.w700, color: AppColors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _call.isVoice ? Icons.call_rounded : Icons.videocam_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          showElapsed ? _fmt(_elapsed) : _fmt(_remaining),
                          style: AppTextStyles.ui(size: 14, weight: FontWeight.w800, color: AppColors.white),
                        ),
                        if (showElapsed) ...[
                          Text('  ·  ', style: AppTextStyles.ui(size: 12, color: Colors.white54)),
                          Text(
                            '${_fmt(_remaining)} left',
                            style: AppTextStyles.ui(size: 12, color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlBtn(
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _muted ? 'Unmute' : 'Mute',
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        setState(() => _muted = !_muted);
                        await _engine?.muteLocalAudioStream(_muted);
                      },
                    ),
                    if (!_call.isVoice)
                      _ControlBtn(
                        icon: _videoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                        label: _videoOff ? 'Cam on' : 'Cam off',
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          setState(() => _videoOff = !_videoOff);
                          await _engine?.muteLocalVideoStream(_videoOff);
                        },
                      ),
                    _ControlBtn(
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      danger: true,
                      large: true,
                      onTap: _ending ? null : () => _endCall(),
                    ),
                  ],
                ),
              ),
            ),
            if (_ending)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black45,
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool large;

  const _ControlBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: danger ? const Color(0xFFE53935) : Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: Colors.white, size: large ? 28 : 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTextStyles.ui(size: 11, weight: FontWeight.w600, color: Colors.white70),
        ),
      ],
    );
  }
}
