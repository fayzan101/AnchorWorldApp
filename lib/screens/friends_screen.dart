import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../models/profile.dart';
import '../widgets/empty_state.dart';
import '../services/fcm_service.dart';
import 'chat_screen.dart';
import 'profile_detail_screen.dart';
import 'video_call_history_screen.dart';
import '../models/video_call.dart' show CallType;
import '../utils/start_intro_call.dart';

/// Mutual connections list (formerly Friends / matches).
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({Key? key}) : super(key: key);

  static void clearCache() {
    _FriendsScreenState._cache = null;
    _FriendsScreenState._cacheAt = null;
  }

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();

  static List<Map<String, dynamic>>? _cache;
  static DateTime? _cacheAt;
  static const _ttl = Duration(minutes: 5);

  bool get _cacheFresh =>
      _cacheAt != null && DateTime.now().difference(_cacheAt!) < _ttl;

  @override
  void initState() {
    super.initState();
    if (_cache != null && _cache!.isNotEmpty) {
      _connections = List<Map<String, dynamic>>.from(
        _cache!.map((m) => Map<String, dynamic>.from(m)),
      );
      _applyFilter();
      _loading = false;
      _load(silent: _cacheFresh);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _connections.isEmpty;
        _error = null;
      });
    }
    try {
      final res = await followService.getConnections();
      if (!mounted) return;
      setState(() {
        _connections = res;
        _applyFilter();
        _loading = false;
        _error = null;
      });
      _cache = List<Map<String, dynamic>>.from(res.map((m) => Map<String, dynamic>.from(m)));
      _cacheAt = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        if (_connections.isEmpty) {
          _connections = [];
          _filtered = [];
        }
        _loading = false;
      });
      if (_connections.isEmpty) {
        customSnackBar('Error', _error ?? 'Failed to load connections', type: SnackType.error);
      }
    }
  }

  void _applyFilter([String? q]) {
    final query = (q ?? _searchCtrl.text).trim().toLowerCase();
    if (query.isEmpty) {
      _filtered = List<Map<String, dynamic>>.from(_connections);
      return;
    }
    _filtered = _connections.where((m) {
      final name = (m['full_name'] ?? m['name'] ?? '').toString().toLowerCase();
      final city = (m['city'] ?? '').toString().toLowerCase();
      final bio = (m['bio'] ?? '').toString().toLowerCase();
      return name.contains(query) || city.contains(query) || bio.contains(query);
    }).toList();
  }

  Future<void> _openProfile(Map<String, dynamic> m) async {
    final String userId = (m['id'] ?? '').toString();
    if (userId.isEmpty) return;
    final cached = AuthService().getCachedUser(userId);
    if (cached != null) {
      final profile = Profile.fromJson(cached);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileDetailScreen(
            profile: profile,
            hideFollowButton: true,
            onFollow: (_) {},
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final Map<String, dynamic> userMap = await AuthService().getUserById(userId);
      final profile = Profile.fromJson(userMap);
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileDetailScreen(
            profile: profile,
            hideFollowButton: true,
            onFollow: (_) {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      customSnackBar('Error', e is Exception ? e.toString() : 'Failed to load profile', type: SnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Connections', style: AppTextStyles.ui(size: 20, weight: FontWeight.w800, color: AppColors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Intro history',
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoCallHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _connections.isEmpty
              ? (_error != null
                  ? EmptyState(
                      title: 'Couldn’t load connections',
                      subtitle: _error!,
                      primaryLabel: 'Retry',
                      onPrimary: _load,
                      icon: Icons.people_outline,
                    )
                  : EmptyState(
                      title: 'No connections yet',
                      subtitle: 'Connect with people in your circles — messaging unlocks when it’s mutual.',
                      primaryLabel: 'Explore Circles',
                      onPrimary: () => Navigator.of(context).pushNamedAndRemoveUntil(
                        '/home',
                        (r) => false,
                        arguments: {'openTab': 'circles'},
                      ),
                      icon: Icons.groups_outlined,
                    ))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_connections.length} connection${_connections.length == 1 ? '' : 's'}',
                                style: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.body),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _applyFilter(v)),
                                style: AppTextStyles.ui(size: 15),
                                decoration: InputDecoration(
                                  hintText: 'Search by name or city',
                                  hintStyle: AppTextStyles.ui(size: 14, color: AppColors.body),
                                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.body),
                                  filled: true,
                                  fillColor: AppColors.card,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: AppColors.mutedBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: AppColors.mutedBorder),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'No matches for “${_searchCtrl.text.trim()}”',
                              style: AppTextStyles.ui(size: 14, color: AppColors.body),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          sliver: SliverList.separated(
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (ctx, i) {
                              final m = _filtered[i];
                              return _ConnectionTile(
                                data: m,
                                onOpen: () => _openProfile(m),
                                onMessage: () async {
                                  final userId = (m['id'] ?? '').toString();
                                  final name = (m['full_name'] ?? m['name'] ?? 'Member').toString();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        currentUserId: 'me',
                                        peerId: userId,
                                        peerName: name,
                                        isConnected: true,
                                      ),
                                    ),
                                  );
                                  // Let the messages list refresh itself via an app event
                                  // instead of force-busting cache from this screen.
                                  FcmService().notifyConversationsUpdated();
                                },
                                onVoice: () {
                                  final userId = (m['id'] ?? '').toString();
                                  final name = (m['full_name'] ?? m['name'] ?? 'Member').toString();
                                  startIntroCall(
                                    context: context,
                                    calleeId: userId,
                                    calleeName: name,
                                    callType: CallType.voice,
                                  );
                                },
                                onVideoStub: () {
                                  final userId = (m['id'] ?? '').toString();
                                  final name = (m['full_name'] ?? m['name'] ?? 'Member').toString();
                                  startIntroCall(
                                    context: context,
                                    calleeId: userId,
                                    calleeName: name,
                                    callType: CallType.video,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  final VoidCallback onMessage;
  final VoidCallback onVoice;
  final VoidCallback onVideoStub;

  const _ConnectionTile({
    required this.data,
    required this.onOpen,
    required this.onMessage,
    required this.onVoice,
    required this.onVideoStub,
  });

  String _avatarUrl(String raw) {
    if (raw.isEmpty || raw == 'null') return '';
    final r = raw.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    final base = ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '');
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '$base/$filename';
    }
    return '$base/${r.split('/').last}';
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['full_name'] ?? data['name'] ?? 'Member').toString();
    final image = _avatarUrl((data['imageUrl'] ?? data['profile_picture'] ?? '').toString());
    final bio = (data['bio'] ?? '').toString().trim();
    final city = (data['city'] ?? '').toString().trim();
    final online = data['is_online'] == true || data['online'] == true;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.mutedBorder),
            boxShadow: AppColors.cardShadow,
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.brandGradient,
                        ),
                        child: CircleAvatar(
                          backgroundColor: AppColors.chipIdle,
                          backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                          child: image.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: AppTextStyles.ui(size: 22, weight: FontWeight.w800, color: AppColors.primary),
                                )
                              : null,
                        ),
                      ),
                      if (online)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.accentMint,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.ui(size: 16, weight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.body, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          city.isNotEmpty ? city : 'Connected',
                          style: AppTextStyles.caption,
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.ui(size: 13, color: AppColors.body, height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ActionChip(
                      label: 'Message',
                      icon: Icons.chat_bubble_outline_rounded,
                      filled: true,
                      onTap: onMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionChip(
                      label: 'Voice',
                      icon: Icons.mic_none_rounded,
                      filled: false,
                      onTap: onVoice,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionChip(
                      label: 'Video',
                      icon: Icons.videocam_outlined,
                      filled: false,
                      onTap: onVideoStub,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : AppColors.chipIdle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : AppColors.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: filled ? Colors.white : AppColors.primaryDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
