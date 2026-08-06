import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/profile.dart';
import '../network/api_client.dart' show ApiException;
import '../services/block_service.dart';
import '../services/follow_service.dart' show followService;
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/profile_posts_grid.dart';
import '../widgets/safety_dialogs.dart';
import '../models/video_call.dart' show CallType;
import '../utils/start_intro_call.dart';
import 'chat_screen.dart';
import 'menu_screen.dart';
import 'profile_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  final Profile profile;
  final bool requested;
  final bool hideFollowButton;
  final bool isOwnProfile;
  final void Function(String profileId)? onFollow;
  /// When true, used as a home tab: no back, hamburger opens menu.
  final bool embedded;
  final VoidCallback? onOpenMenu;
  final VoidCallback? onProfileUpdated;

  const ProfileDetailScreen({
    Key? key,
    required this.profile,
    this.requested = false,
    this.hideFollowButton = false,
    this.isOwnProfile = false,
    this.onFollow,
    this.embedded = false,
    this.onOpenMenu,
    this.onProfileUpdated,
  }) : super(key: key);

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  late bool _requested;
  bool _loading = false;
  bool _iBlockedThem = false;
  bool _checkingBlock = false;
  late Profile _profile;

  @override
  void initState() {
    super.initState();
    _requested = widget.requested;
    _profile = widget.profile;
    if (!widget.isOwnProfile) _checkBlocked();
  }

  @override
  void didUpdateWidget(covariant ProfileDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _profile = widget.profile;
    }
  }

  Future<void> _checkBlocked() async {
    setState(() => _checkingBlock = true);
    try {
      final list = await blockService.listBlocked();
      final id = _profile.id;
      final blocked = list.any((item) {
        final blockedId = (item['blocked_id'] ?? item['blockedId'] ?? '').toString();
        if (blockedId == id) return true;
        final user = item['blocked_user'];
        if (user is Map && user['id']?.toString() == id) return true;
        return false;
      });
      if (mounted) setState(() => _iBlockedThem = blocked);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checkingBlock = false);
    }
  }

  Future<void> _unblock() async {
    try {
      await blockService.unblockUser(_profile.id);
      if (!mounted) return;
      setState(() => _iBlockedThem = false);
      customSnackBar('Unblocked', '${_profile.name} was unblocked', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not unblock') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  String _resolveImageUrl(String raw) {
    if (raw.isEmpty || raw == 'null') return '';
    final r = raw.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/$filename';
    }
    return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/${r.split('/').last}';
  }

  Future<void> _cancelRequest() async {
    setState(() => _loading = true);
    try {
      final ok = await followService.cancelSentTo(_profile.id);
      if (!mounted) return;
      if (ok) {
        setState(() => _requested = false);
        try {
          AuthService().invalidateUser(_profile.id);
        } catch (_) {}
        customSnackBar('Cancelled', 'Connection request cancelled', type: SnackType.success);
      } else {
        customSnackBar('Info', 'No pending request found', type: SnackType.info);
        setState(() => _requested = false);
      }
    } catch (e) {
      if (!mounted) return;
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not cancel') : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendConnect() async {
    if (_requested) return;
    setState(() => _loading = true);
    try {
      await followService.follow(_profile.id);
      if (!mounted) return;
      setState(() => _requested = true);
      try {
        widget.onFollow?.call(_profile.id);
      } catch (_) {}
      try {
        AuthService().invalidateUser(_profile.id);
      } catch (_) {}
      customSnackBar('Success', 'Connection request sent to ${_profile.name}', type: SnackType.success);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.statusCode : null;
      final msg = e is ApiException ? (e.message ?? '') : e.toString();
      final lower = msg.toLowerCase();
      if (code == 409 ||
          lower.contains('already') ||
          lower.contains('conflict') ||
          lower.contains('pending') ||
          lower.contains('exists')) {
        setState(() => _requested = true);
        customSnackBar('Info', 'Connection request already sent', type: SnackType.info);
      } else {
        customSnackBar('Error', msg.isNotEmpty ? msg : 'Could not send request', type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _block({bool popAfter = true}) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Block ${_profile.name}?',
      message: 'They won’t be able to message or connect with you. You can unblock them later from Menu.',
      confirmLabel: 'Block',
    );
    if (!ok) return;
    try {
      await blockService.blockUser(_profile.id);
      if (!mounted) return;
      setState(() => _iBlockedThem = true);
      customSnackBar('Blocked', '${_profile.name} was blocked', type: SnackType.success);
      if (popAfter && !widget.embedded) Navigator.of(context).pop();
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not block') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  Future<void> _reportAndBlock() async {
    final reason = await showReportReasonDialog(context, title: 'Report & Block ${_profile.name}');
    if (reason == null) return;
    try {
      await blockService.reportUser(_profile.id, reason: reason.isEmpty ? null : reason);
      await blockService.blockUser(_profile.id);
      if (!mounted) return;
      setState(() => _iBlockedThem = true);
      customSnackBar(
        'Reported & blocked',
        '${_profile.name} was reported and blocked. Our team will review the report.',
        type: SnackType.success,
      );
      if (!widget.embedded) Navigator.of(context).pop();
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not report & block') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  void _openMessage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          currentUserId: 'me',
          peerId: _profile.id,
          peerName: _profile.name.isNotEmpty ? _profile.name : 'Member',
          isConnected: true,
        ),
      ),
    );
  }

  void _openMenu() {
    if (widget.onOpenMenu != null) {
      widget.onOpenMenu!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen(userId: 'me')),
    );
    if (!mounted) return;
    try {
      final updated = await AuthService().getProfile();
      if (!mounted) return;
      setState(() => _profile = Profile.fromJson(updated));
      widget.onProfileUpdated?.call();
    } catch (_) {
      widget.onProfileUpdated?.call();
    }
  }

  String get _titleName {
    final name = _profile.name.trim();
    if (name.isNotEmpty) return name;
    final email = (_profile.email ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Profile';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final displayName = profile.name.isNotEmpty ? profile.name : 'Member';
    final imageUrl = _resolveImageUrl(profile.imageUrl);
    final location = [
      if (profile.city != null && profile.city!.isNotEmpty) profile.city!,
      if (profile.country != null && profile.country!.isNotEmpty) profile.country!,
    ].join(', ');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: widget.embedded
          ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              flexibleSpace: Container(
                decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              centerTitle: true,
              title: Text(
                widget.isOwnProfile ? _titleName : displayName,
                style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
              ),
              actions: [
                if (widget.isOwnProfile)
                  IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: _openMenu,
                  )
                else
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    offset: const Offset(0, 42),
                    position: PopupMenuPosition.under,
                    onSelected: (v) {
                      if (v == 'block') _block();
                      if (v == 'unblock') _unblock();
                      if (v == 'report_block') _reportAndBlock();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'report_block', child: Text('Report & Block')),
                      if (_iBlockedThem)
                        const PopupMenuItem(value: 'unblock', child: Text('Unblock'))
                      else if (!_checkingBlock)
                        const PopupMenuItem(value: 'block', child: Text('Block')),
                    ],
                  ),
              ],
            ),
      body: ListView(
        clipBehavior: Clip.none,
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 12 : 8, 16, widget.embedded ? 100 : 24),
        children: [
          // IG header: avatar + stats
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: CircleAvatar(
                  backgroundColor: AppColors.chipIdle,
                  backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                  child: imageUrl.isEmpty
                      ? Text(
                          displayName[0].toUpperCase(),
                          style: AppTextStyles.ui(size: 30, weight: FontWeight.w800, color: AppColors.primary),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatColumn(value: '${profile.postCount}', label: 'Posts'),
                    _StatColumn(value: '${profile.circles.length}', label: 'Circles'),
                    _StatColumn(value: '${profile.pointsBalance}', label: 'Points'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(displayName, style: AppTextStyles.ui(size: 15, weight: FontWeight.w800)),
          if (profile.age > 0 || location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (profile.age > 0) '${profile.age}',
                if (location.isNotEmpty) location,
              ].join(' · '),
              style: AppTextStyles.ui(size: 13, color: AppColors.body),
            ),
          ],
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(profile.bio, style: AppTextStyles.ui(size: 14, height: 1.4)),
          ],
          const SizedBox(height: 14),
          if (widget.isOwnProfile) ...[
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton(
                onPressed: _editProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.mutedBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                child: Text('Edit profile', style: AppTextStyles.ui(size: 13, weight: FontWeight.w700)),
              ),
            ),
          ] else if (_iBlockedThem) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.chipIdle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.mutedBorder),
              ),
              child: Text(
                'You blocked this user. Unblock them from the menu to message or call again.',
                style: AppTextStyles.ui(size: 13, color: AppColors.body),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (!widget.hideFollowButton) ...[
            SizedBox(
              height: 36,
              width: double.infinity,
              child: _requested
                  ? OutlinedButton(
                      onPressed: _loading ? null : _cancelRequest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.mutedBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            )
                          : Text('Cancel request', style: AppTextStyles.ui(size: 13, weight: FontWeight.w700)),
                    )
                  : ElevatedButton(
                      onPressed: _loading ? null : _sendConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Connect', style: AppTextStyles.ui(size: 13, weight: FontWeight.w800, color: AppColors.white)),
                    ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: _openMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Message', style: AppTextStyles.ui(size: 13, weight: FontWeight.w800, color: AppColors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () {
                        startIntroCall(
                          context: context,
                          calleeId: profile.id,
                          calleeName: displayName,
                          callType: CallType.voice,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.mutedBorder),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Voice', style: AppTextStyles.ui(size: 13, weight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () {
                        startIntroCall(
                          context: context,
                          calleeId: profile.id,
                          calleeName: displayName,
                          callType: CallType.video,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.mutedBorder),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Video', style: AppTextStyles.ui(size: 13, weight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.mutedBorder),
          const SizedBox(height: 4),
          ProfilePostsGrid(userId: profile.id),
        ],
      ),
    ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppTextStyles.ui(size: 17, weight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.ui(size: 12, color: AppColors.body)),
      ],
    );
  }
}
