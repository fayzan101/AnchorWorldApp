import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/video_call.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/video_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/start_intro_call.dart';
import '../widgets/empty_state.dart';

class VideoCallHistoryScreen extends StatefulWidget {
  const VideoCallHistoryScreen({super.key});

  @override
  State<VideoCallHistoryScreen> createState() => _VideoCallHistoryScreenState();
}

class _VideoCallHistoryScreenState extends State<VideoCallHistoryScreen> {
  final _service = VideoCallService();
  List<VideoCall> _items = [];
  bool _loading = true;
  String? _myId;

  @override
  void initState() {
    super.initState();
    final me = AuthService().getCachedProfile();
    _myId = me?['id']?.toString();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await _service.getHistory();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not load history') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  VideoCallParticipant? _otherParticipant(VideoCall call) {
    final me = _myId;
    if (me != null && me.isNotEmpty) {
      if (call.callerId == me) return call.callee;
      if (call.calleeId == me) return call.caller;
    }
    return call.callee ?? call.caller;
  }

  bool _isOutgoing(VideoCall call) {
    final me = _myId;
    if (me != null && me.isNotEmpty) return call.callerId == me;
    return false;
  }

  bool _isMissed(VideoCall call) {
    return call.status == VideoCallStatus.missed ||
        (call.status == VideoCallStatus.rejected && !_isOutgoing(call));
  }

  String _avatarUrl(String? path) {
    if (path == null || path.isEmpty || path == 'null') return '';
    final r = path.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/$filename';
    }
    return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/${r.split('/').last}';
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String? _durationLabel(VideoCall call) {
    if (call.startedAt == null || call.endedAt == null) return null;
    final secs = call.endedAt!.difference(call.startedAt!).inSeconds;
    if (secs <= 0) return null;
    final m = secs ~/ 60;
    final s = secs % 60;
    if (m <= 0) return '${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _subtitle(VideoCall call) {
    final outgoing = _isOutgoing(call);
    final kind = call.isVoice ? 'Voice' : 'Video';
    String status;
    switch (call.status) {
      case VideoCallStatus.completed:
        status = outgoing ? 'Outgoing' : 'Incoming';
        break;
      case VideoCallStatus.missed:
        status = 'Missed';
        break;
      case VideoCallStatus.rejected:
        status = outgoing ? 'Declined by them' : 'Declined';
        break;
      case VideoCallStatus.cancelled:
        status = outgoing ? 'Cancelled' : 'Cancelled by them';
        break;
      case VideoCallStatus.active:
        status = 'In progress';
        break;
      case VideoCallStatus.pending:
        status = 'Ringing';
        break;
      case VideoCallStatus.unknown:
        status = kind;
        break;
    }
    final dur = _durationLabel(call);
    final parts = <String>[
      status,
      kind,
      if (dur != null) dur,
    ];
    return parts.join(' · ');
  }

  IconData _directionIcon(VideoCall call) {
    if (_isMissed(call)) return Icons.call_missed_outgoing_rounded;
    if (_isOutgoing(call)) {
      return call.isVoice ? Icons.call_made_rounded : Icons.videocam_outlined;
    }
    return call.isVoice ? Icons.call_received_rounded : Icons.videocam_outlined;
  }

  Color _directionColor(VideoCall call) {
    if (_isMissed(call)) return AppColors.danger;
    if (call.status == VideoCallStatus.completed) return AppColors.accentMint;
    return AppColors.body;
  }

  Future<void> _callBack(VideoCall call) async {
    final other = _otherParticipant(call);
    final id = other?.id ?? '';
    if (id.isEmpty) {
      customSnackBar('Info', 'Can’t call this contact', type: SnackType.info);
      return;
    }
    await startIntroCall(
      context: context,
      calleeId: id,
      calleeName: other?.fullName ?? 'Member',
      callType: call.callType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            'Recent calls',
            style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _items.isEmpty
                ? EmptyState(
                    title: 'No calls yet',
                    subtitle: 'Voice and video calls with connections will show up here.',
                    primaryLabel: 'Got it',
                    onPrimary: () => Navigator.of(context).maybePop(),
                    icon: Icons.call_outlined,
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 78, color: AppColors.mutedBorder),
                      itemBuilder: (context, i) {
                        final call = _items[i];
                        final other = _otherParticipant(call);
                        final name = (other?.fullName.trim().isNotEmpty == true) ? other!.fullName : 'Member';
                        final avatar = _avatarUrl(other?.profilePicture);
                        final missed = _isMissed(call);
                        final when = _relativeTime(call.endedAt ?? call.startedAt ?? call.createdAt);

                        return InkWell(
                          onTap: () => _callBack(call),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AppColors.chipIdle,
                                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                  child: avatar.isEmpty
                                      ? Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                                          style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.primary),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: AppTextStyles.ui(
                                          size: 16,
                                          weight: FontWeight.w700,
                                          color: missed ? AppColors.danger : AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            _directionIcon(call),
                                            size: 16,
                                            color: _directionColor(call),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _subtitle(call),
                                              style: AppTextStyles.ui(size: 13, color: AppColors.body),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (when.isNotEmpty)
                                      Text(when, style: AppTextStyles.ui(size: 12, color: AppColors.body)),
                                    const SizedBox(height: 8),
                                    Icon(
                                      call.isVoice ? Icons.call_rounded : Icons.videocam_rounded,
                                      color: AppColors.primary,
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
