import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

import '../models/profile.dart';
import '../config/api_config.dart';
import '../services/follow_service.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import 'profile_detail_screen.dart';

import '../utils/custom_snackbar.dart';
import '../utils/app_caches.dart';
import '_requests_appbar.dart';

class RequestsScreen extends StatefulWidget {
  final String currentUserId;
  const RequestsScreen({Key? key, required this.currentUserId}) : super(key: key);

  static void clearCache([String? userId]) {
    if (userId == null) {
      _RequestsScreenState._receivedCache.clear();
      _RequestsScreenState._sentCache.clear();
    } else {
      _RequestsScreenState._receivedCache.remove(userId);
      _RequestsScreenState._sentCache.remove(userId);
    }
  }

  /// Drop a received request from cache (e.g. sender cancelled while this screen is closed).
  static void removeReceivedFromCache(String userId, {String? followId, String? followerId}) {
    final list = _RequestsScreenState._receivedCache[userId];
    if (list == null) return;
    list.removeWhere((r) {
      final id = r['id']?.toString() ?? '';
      final fid = (r['follower'] is Map ? r['follower']['id'] : null)?.toString() ?? '';
      if (followId != null && followId.isNotEmpty && id == followId) return true;
      if (followerId != null && followerId.isNotEmpty && fid == followerId) return true;
      return false;
    });
  }

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> with SingleTickerProviderStateMixin {
  static final Map<String, List<Map<String, dynamic>>> _receivedCache = {};
  static final Map<String, List<Map<String, dynamic>>> _sentCache = {};

  List<Map<String, dynamic>>? get _cachedReceived => _receivedCache[widget.currentUserId];
  void _setCachedReceived(List<Map<String, dynamic>> items) {
    _receivedCache[widget.currentUserId] = List<Map<String, dynamic>>.from(items.map((m) => Map<String, dynamic>.from(m)));
  }

  List<Map<String, dynamic>>? get _cachedSent => _sentCache[widget.currentUserId];
  void _setCachedSent(List<Map<String, dynamic>> items) {
    _sentCache[widget.currentUserId] = List<Map<String, dynamic>>.from(items.map((m) => Map<String, dynamic>.from(m)));
  }

  late List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _acceptLoading = {};
  final Map<String, bool> _rejectLoading = {};
  final Map<String, bool> _cancelSentLoading = {};
  final Set<String> _removingIds = {};
  StreamSubscription? _cancelSub;

  late final TabController _tabController;
  final List<Tab> _tabs = const [
    Tab(text: 'Received'),
    Tab(text: 'Sent'),
  ];
  List<Map<String, dynamic>> _sentUsers = [];
  bool _sentLoading = false;
  String? _sentError;

  void _goToCircles() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'openTab': 'circles'},
    );
  }

  Future<void> _loadSentUsers() async {
    final cached = _cachedSent;
    if (cached != null && cached.isNotEmpty && _sentUsers.isEmpty) {
      setState(() {
        _sentUsers = List<Map<String, dynamic>>.from(cached.map((m) => Map<String, dynamic>.from(m)));
        _sentLoading = false;
      });
    }
    if (!mounted) return;
    setState(() {
      _sentLoading = _sentUsers.isEmpty;
      _sentError = null;
    });
    try {
      final items = await FollowService().getSent();
      final users = <Map<String, dynamic>>[];
      for (final item in items) {
        Map<String, dynamic>? user;
        final following = item['following'];
        if (following is Map) {
          user = Map<String, dynamic>.from(following);
        } else if (item['following_id'] != null || item['user'] is Map) {
          // Fallback shapes if API nests differently
          final nested = item['user'];
          if (nested is Map) {
            user = Map<String, dynamic>.from(nested);
          } else {
            user = {
              'id': item['following_id']?.toString() ?? '',
              'full_name': item['full_name'] ?? item['name'] ?? 'Member',
              'profile_picture': item['profile_picture'],
            };
          }
        }
        if (user != null && (user['id']?.toString() ?? '').isNotEmpty) {
          user['follow_request_id'] = item['id'];
          users.add(user);
        }
      }
      if (!mounted) return;
      _setCachedSent(users);
      setState(() {
        _sentUsers = users;
        _sentError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sentError = e.toString().replaceAll('Exception: ', '');
        if (_sentUsers.isEmpty) _sentUsers = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _sentLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) {
        _loadSentUsers();
      } else {
        _loadPending();
      }
    });
    _requests = [];
    final cached = _cachedReceived;
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _requests = List<Map<String, dynamic>>.from(cached.map((m) => Map<String, dynamic>.from(m)));
        _loading = false;
      });
      _loadPending(showLoading: false);
    } else {
      _loadPending(showLoading: true);
    }
    // Preload sent so the Sent tab isn't empty on first open / swipe.
    _loadSentUsers();
    SocketService().ensureConnection();
    _cancelSub = SocketService().onFollowRequestCancelled.listen((event) {
      final followId = (event['follow_id'] ?? event['followId'] ?? '').toString();
      final followerId = (event['follower_id'] ?? event['followerId'] ?? '').toString();
      _slideOutReceived(followId: followId, followerId: followerId);
    });
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _slideOutReceived({String? followId, String? followerId}) async {
    String? matchId;
    for (final r in _requests) {
      final id = r['id']?.toString() ?? '';
      final fid = (r['follower'] is Map ? r['follower']['id'] : null)?.toString() ?? '';
      if ((followId != null && followId.isNotEmpty && id == followId) ||
          (followerId != null && followerId.isNotEmpty && fid == followerId)) {
        matchId = id.isNotEmpty ? id : fid;
        break;
      }
    }
    if (matchId == null) {
      RequestsScreen.removeReceivedFromCache(
        widget.currentUserId,
        followId: followId,
        followerId: followerId,
      );
      return;
    }
    if (_removingIds.contains(matchId)) return;
    setState(() => _removingIds.add(matchId!));
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _requests.removeWhere((r) {
        final id = r['id']?.toString() ?? '';
        final fid = (r['follower'] is Map ? r['follower']['id'] : null)?.toString() ?? '';
        if (followId != null && followId.isNotEmpty && id == followId) return true;
        if (followerId != null && followerId.isNotEmpty && fid == followerId) return true;
        return false;
      });
      _removingIds.remove(matchId);
      _setCachedReceived(_requests);
    });
  }


  Future<void> _loadPending({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final List<Map<String, dynamic>> items = await followService.getPending();
      _setCachedReceived(items);
      setState(() {
        _requests = items;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _requests = [];
        _error = e.toString();
      });
      _setCachedReceived([]);
    } finally {
      if (mounted && showLoading) setState(() { _loading = false; });
    }
  }

  void _cancel(Profile p) {
    _slideOutReceived(followerId: p.id);
    customSnackBar('Success', 'Cancelled request to ${p.name}');
  }

  void _confirm(Profile p) {
    _slideOutReceived(followerId: p.id);
    customSnackBar('Success', 'Confirmed request from ${p.name}');
  }

  Future<void> _openProfile(Profile p) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final Map<String, dynamic> userMap = await AuthService().getUserById(p.id, forceRefresh: true);
      final raw = Profile.fromJson(userMap);
      final fetched = Profile(
        id: raw.id.isNotEmpty ? raw.id : p.id,
        name: raw.name.isNotEmpty ? raw.name : p.name,
        age: raw.age != 0 ? raw.age : p.age,
        bio: raw.bio.isNotEmpty ? raw.bio : p.bio,
        imageUrl: raw.imageUrl.isNotEmpty ? raw.imageUrl : p.imageUrl,
        gender: raw.gender,
        location: raw.location,
        city: raw.city,
        country: raw.country,
        interests: raw.interests,
        hobbies: raw.hobbies,
        postCount: raw.postCount,
        pointsBalance: raw.pointsBalance,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: fetched, requested: _tabController.index == 1, hideFollowButton: _tabController.index == 0, onFollow: (profileId) {
        try {
          setState(() {
            _requests.removeWhere((r) => (r['follower'] is Map ? (r['follower']['id'] ?? r['id']) : r['id']) == profileId);
            _setCachedReceived(_requests);
          });
        } catch (_) {}
      })));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      customSnackBar('Error', e is Exception ? e.toString() : 'Failed to load profile');
    }
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon, String primaryLabel, VoidCallback onPrimary) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.gradientPurple.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 80,
              color: AppColors.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200, // Reduced from double.infinity to 200
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(primaryLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: const PreferredSize(
            preferredSize: Size.fromHeight(72),
            child: RequestsAppBar(),
          ),
          body: Column(
            children: [
              Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabController,
                  tabs: _tabs,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.body,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  labelStyle: AppTextStyles.ui(size: 14, weight: FontWeight.w800),
                  unselectedLabelStyle: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
          _loading
            ? const Center(child: CircularProgressIndicator())
            : (_requests.isEmpty
              ? _buildEmptyState(
                'No Requests',
                _error == null
                  ? 'You have no incoming connection requests right now. Connect with people in your circles.'
                  : 'No requests (fallback). ${_error ?? ''}',
                Icons.person_add,
                'Explore Circles',
                _goToCircles,
                )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                itemCount: _requests.length,
                                itemBuilder: (context, i) {
                                  final req = _requests[i];
                                  final follower = (req['follower'] is Map<String, dynamic>)
                                      ? Map<String, dynamic>.from(req['follower'])
                                      : (req['follower'] is Profile ? (req['follower'] as Profile).toJson() : <String, dynamic>{});
                                  String? image = (follower['profile_picture'] ?? follower['imageUrl'] ?? follower['image_url'] ?? follower['avatar'])?.toString();
                                  if (image != null && image.isNotEmpty && image.startsWith('/uploads/')) {
                                    try {
                                      final base = ApiConfig.baseUrl;
                                      final uri = Uri.parse(base);
                                      final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
                                      follower['imageUrl'] = origin + image;
                                    } catch (_) {}
                                  }
                                  follower['id'] = follower['id'] ?? (req['id'] ?? '');
                                  final p = Profile.fromJson(follower);
                                  final String requestId = req['id']?.toString() ?? '';
                                  final removing = _removingIds.contains(requestId) ||
                                      _removingIds.contains(p.id);
                                  return AnimatedSlide(
                                    offset: removing ? const Offset(-1.05, 0) : Offset.zero,
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeInCubic,
                                    child: AnimatedOpacity(
                                      opacity: removing ? 0 : 1,
                                      duration: const Duration(milliseconds: 220),
                                      child: _RequestTile(
                                    profile: p,
                                    badge: 'New',
                                    badgeColor: AppColors.primary,
                                    onTap: () => _openProfile(p),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ActionButton(
                                          icon: Icons.check_rounded,
                                          color: const Color(0xFF4CAF50),
                                          loading: _acceptLoading[requestId] == true,
                                          onTap: () async {
                                            setState(() { _acceptLoading[requestId] = true; _rejectLoading[requestId] = false; });
                                            try {
                                              if (requestId.isNotEmpty) {
                                                final res = await followService.acceptRequest(requestId);
                                                final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
                                                final awarded = data['points_awarded'] ?? data['pointsAwarded'];
                                                if (awarded is int && awarded > 0) {
                                                  customSnackBar('Success', '+$awarded Anchor Points \u2014 you\'re connected!', type: SnackType.success);
                                                } else {
                                                  customSnackBar('Success', 'Connection accepted', type: SnackType.success);
                                                }
                                              }
                                              _confirm(p);
                                              AppCaches.invalidateAfterConnectionChange();
                                            } catch (e) {
                                              final msg = e.toString().toLowerCase();
                                              if (msg.contains('404') || msg.contains('not found')) {
                                                await _slideOutReceived(followId: requestId, followerId: p.id);
                                                customSnackBar('Info', 'This request is no longer available', type: SnackType.info);
                                              } else {
                                                customSnackBar('Error', e is Exception ? e.toString() : 'Failed to accept', type: SnackType.error);
                                              }
                                            } finally {
                                              if (mounted) setState(() => _acceptLoading[requestId] = false);
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        _ActionButton(
                                          icon: Icons.close_rounded,
                                          color: AppColors.body,
                                          loading: _rejectLoading[requestId] == true,
                                          onTap: () async {
                                            setState(() { _rejectLoading[requestId] = true; _acceptLoading[requestId] = false; });
                                            try {
                                              if (requestId.isNotEmpty) await followService.deleteRequest(requestId);
                                              _cancel(p);
                                            } catch (e) {
                                              final msg = e.toString().toLowerCase();
                                              if (msg.contains('404') || msg.contains('not found')) {
                                                await _slideOutReceived(followId: requestId, followerId: p.id);
                                              } else {
                                                customSnackBar('Error', e is Exception ? e.toString() : 'Failed to decline');
                                              }
                                            } finally {
                                              if (mounted) setState(() => _rejectLoading[requestId] = false);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                    ),
                                  );
                                },
                              )),
                    _sentLoading
                        ? const Center(child: CircularProgressIndicator())
                        : (_sentError != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Could not load sent requests',
                                        style: AppTextStyles.ui(weight: FontWeight.w700, size: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(_sentError!, style: AppTextStyles.body, textAlign: TextAlign.center),
                                      const SizedBox(height: 16),
                                      TextButton(
                                        onPressed: _loadSentUsers,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
              : (_sentUsers.isEmpty
                ? _buildEmptyState(
                    'Nothing Sent',
                    'You haven\'t sent any requests yet. Connect with people in your circles to grow your network.',
                    Icons.send,
                    'Explore Circles',
                    _goToCircles,
                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    itemCount: _sentUsers.length,
                                    itemBuilder: (context, i) {
                                      final user = _sentUsers[i];
                                      final p = Profile.fromJson(user);
                                      final requestId = (user['follow_request_id'] ?? '').toString();
                                      return _RequestTile(
                                        profile: p,
                                        badge: 'Pending',
                                        badgeColor: AppColors.accentGold,
                                        onTap: () => _openProfile(p),
                                        trailing: _ActionButton(
                                          icon: Icons.close_rounded,
                                          color: AppColors.body,
                                          loading: _cancelSentLoading[requestId] == true,
                                          onTap: () async {
                                            if (requestId.isEmpty) return;
                                            setState(() => _cancelSentLoading[requestId] = true);
                                            try {
                                              await followService.deleteRequest(requestId);
                                              if (!mounted) return;
                                              setState(() {
                                                _sentUsers = _sentUsers
                                                    .where((u) => (u['follow_request_id'] ?? '').toString() != requestId)
                                                    .toList();
                                                _setCachedSent(_sentUsers);
                                              });
                                              AppCaches.invalidateAfterConnectionChange();
                                              customSnackBar('Cancelled', 'Connection request cancelled', type: SnackType.success);
                                            } catch (e) {
                                              customSnackBar(
                                                'Error',
                                                e is Exception ? e.toString() : 'Could not cancel',
                                                type: SnackType.error,
                                              );
                                            } finally {
                                              if (mounted) setState(() => _cancelSentLoading[requestId] = false);
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ))),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

}

class _RequestTile extends StatelessWidget {
  final Profile profile;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;
  final Widget? trailing;

  const _RequestTile({
    required this.profile,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    backgroundColor: AppColors.chipIdle,
                    backgroundImage: profile.imageUrl.isNotEmpty ? NetworkImage(profile.imageUrl) : null,
                    child: profile.imageUrl.isEmpty
                        ? Text(
                            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                            style: AppTextStyles.ui(size: 20, weight: FontWeight.w800, color: AppColors.primary),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              style: AppTextStyles.ui(size: 15, weight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: badgeColor.withOpacity(0.3)),
                            ),
                            child: Text(
                              badge,
                              style: AppTextStyles.ui(size: 10, weight: FontWeight.w700, color: badgeColor),
                            ),
                          ),
                        ],
                      ),
                      if (profile.age > 0) ...[
                        const SizedBox(height: 3),
                        Text('${profile.age} yrs', style: AppTextStyles.ui(size: 12, color: AppColors.body)),
                      ],
                      if (profile.location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 12, color: AppColors.body),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                profile.location,
                                style: AppTextStyles.ui(size: 12, color: AppColors.body),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, color: color, size: 20),
      ),
    );
  }
}
