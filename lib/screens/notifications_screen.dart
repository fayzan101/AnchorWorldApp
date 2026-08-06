import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/video_call.dart';
import '../network/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/video_call_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/open_user_profile.dart';
import '../widgets/empty_state.dart';
import 'chat_screen.dart';
import 'points_wallet_screen.dart';
import 'post_detail_screen.dart';
import 'requests_screen.dart';
import 'video_call_incoming_screen.dart';
import 'video_call_screen.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  static void clearCache() {
    _NotificationsScreenState._cache = null;
    _NotificationsScreenState._cacheAt = null;
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  final int _page = 1;
  final int _limit = 20;
  List<Map<String, dynamic>> _items = [];
  bool _pushEnabled = true;
  bool _togglingPush = false;

  static List<Map<String, dynamic>>? _cache;
  static DateTime? _cacheAt;
  static const _ttl = Duration(minutes: 2);

  bool get _cacheFresh =>
      _cacheAt != null && DateTime.now().difference(_cacheAt!) < _ttl;

  @override
  void initState() {
    super.initState();
    _loadPushPref();
    if (_cache != null && _cache!.isNotEmpty) {
      _items = List<Map<String, dynamic>>.from(
        _cache!.map((m) => Map<String, dynamic>.from(m)),
      );
      _loading = false;
      _load(refresh: true, silent: _cacheFresh);
    } else {
      _load();
    }
  }

  Future<void> _loadPushPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _pushEnabled = prefs.getBool('notifications_enabled') ?? true);
    } catch (_) {}
  }

  Future<bool> _togglePush(bool enabled) async {
    if (_togglingPush) return false;
    setState(() {
      _togglingPush = true;
      _pushEnabled = enabled;
    });
    try {
      await notificationService.toggleNotifications(enabled);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);
      if (!mounted) return true;
      customSnackBar(
        'Success',
        enabled ? 'Push notifications turned on' : 'Push notifications turned off',
        type: SnackType.success,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _pushEnabled = !enabled);
      return false;
    } finally {
      if (mounted) setState(() => _togglingPush = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationSettingsScreen(
          pushEnabled: _pushEnabled,
          hasNotifications: _items.isNotEmpty,
          hasUnread: _items.any((n) => !(_pickBool(n, ['read', 'is_read', 'isRead']) ?? false)),
          onMarkAllRead: _markAllRead,
          onDeleteAll: () async {
            await _deleteAllConfirmed();
          },
          onTogglePush: _togglePush,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _deleteAllConfirmed() async {
    try {
      await notificationService.deleteAllNotifications();
      if (!mounted) return;
      setState(() => _items = []);
      _cache = [];
      _cacheAt = DateTime.now();
      customSnackBar('Success', 'All notifications deleted', type: SnackType.success);
    } catch (e) {
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Delete failed') : e.toString(), type: SnackType.error);
    }
  }

  Future<void> _load({bool refresh = false, bool silent = false}) async {
    if (!refresh && !silent) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final resp = await notificationService.fetchNotifications(page: _page, limit: _limit);
      final rawItems = resp['items'];
      final items = <Map<String, dynamic>>[];
      if (rawItems is List) {
        for (final e in rawItems) {
          if (e is Map) items.add(Map<String, dynamic>.from(e));
        }
      }
      final filtered = items.where((n) {
        if (_isCircleJoinNotification(n)) return false;
        final title = _pickString(n, ['title', 'notification_title', 'name', 'from_user_name']) ?? '';
        final body = _pickString(n, ['body', 'message', 'content', 'text']) ?? '';
        // Message notifications disappear once read — don't keep them in the inbox.
        if (_isNewMessage(n, title: title, body: body)) {
          final read = _pickBool(n, ['read', 'is_read', 'isRead']) ?? false;
          if (read) return false;
        }
        return true;
      }).toList();
      if (!mounted) return;
      setState(() {
        _items = filtered;
        _error = null;
        _loading = false;
      });
      _cache = List<Map<String, dynamic>>.from(filtered.map((m) => Map<String, dynamic>.from(m)));
      _cacheAt = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_items.isEmpty) {
          _error = e is ApiException ? e.message : e.toString();
        }
        _loading = false;
      });
    }
  }

  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    if (Get.key.currentState?.canPop() == true) {
      Get.back();
      return;
    }
    Get.offAllNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: _goBack,
        ),
        title: Text(
          'Notifications',
          style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? EmptyState(
                  title: 'Couldn’t load notifications',
                  subtitle: _error!,
                  primaryLabel: 'Try again',
                  onPrimary: _load,
                  icon: Icons.wifi_off_rounded,
                )
              : _items.isEmpty
                  ? EmptyState(
                      title: 'You’re all caught up',
                      subtitle: 'Likes, comments, connections, and calls will show up here.',
                      primaryLabel: 'Back to Feed',
                      onPrimary: () => Get.offAllNamed('/home'),
                      icon: Icons.notifications_none_rounded,
                    )
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () => _load(refresh: true),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _buildTile(_items[i]),
                      ),
                    ),
    );
  }

  Widget _buildTile(Map<String, dynamic> n) {
    final String rawTitle = _pickString(n, ['title', 'notification_title', 'name', 'from_user_name']) ?? 'Notification';
    final String rawBody = _pickString(n, ['body', 'message', 'content', 'text']) ?? '';
    final display = _displayCallCopy(n, rawTitle, rawBody);
    final String title = display.title;
    final String body = display.body;
    final String time = _relativeTime(_pickString(n, ['created_at', 'createdAt', 'timestamp', 'time']));
    final bool read = _pickBool(n, ['read', 'is_read', 'isRead']) ?? false;
    final id = (n['id'] ?? '').toString();
    final avatarUrl = _actorAvatarUrl(n);
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '?';
    final isSystem = _isSystemNotification(n, title: title, body: body);

    final leading = isSystem
        ? CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  _systemIcon(n, title: title, body: body),
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ),
          )
        : CircleAvatar(
            radius: 22,
            backgroundColor: read ? AppColors.chipIdle : AppColors.primary.withOpacity(0.12),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    initial,
                    style: AppTextStyles.ui(
                      weight: FontWeight.w800,
                      color: read ? AppColors.body : AppColors.primary,
                    ),
                  )
                : null,
          );

    final tile = Material(
      color: read ? AppColors.card : AppColors.primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onTap(n, title: title, body: body),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: read ? AppColors.mutedBorder : AppColors.primary.withOpacity(0.18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.ui(
                                size: 15,
                                weight: FontWeight.w800,
                                color: read ? AppColors.body : AppColors.ink,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(time, style: AppTextStyles.caption),
                          ],
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.ui(
                            size: 13,
                            height: 1.35,
                            color: AppColors.body,
                          ),
                        ),
                      ],
                      if (!read) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.body, size: 20),
                  onSelected: (value) {
                    if (value == 'read') _markOneRead(n);
                    if (value == 'delete') _deleteOne(n);
                  },
                  itemBuilder: (ctx) => [
                    if (!read)
                      const PopupMenuItem(
                        value: 'read',
                        child: Row(
                          children: [
                            Icon(Icons.mark_email_read_outlined, size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text('Mark as read'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                          SizedBox(width: 10),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey(id.isNotEmpty ? 'notif-$id' : 'notif-${n.hashCode}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (!read) await _markOneRead(n);
          return false;
        }
        await _deleteOne(n);
        return false;
      },
      child: tile,
    );
  }

  bool _isSystemNotification(Map<String, dynamic> n, {String? title, String? body}) {
    final type = _typeOf(n);
    if (type.contains('points') ||
        type.contains('system') ||
        type.contains('premium') ||
        type.contains('welcome') ||
        type.contains('admin')) {
      return true;
    }
    final actorId = _relatedUserId(n);
    if (actorId != null && actorId.isNotEmpty) return false;
    if (_actorAvatarUrl(n) != null) return false;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('points') || text.contains('subscription') || text.contains('welcome');
  }

  IconData _systemIcon(Map<String, dynamic> n, {String? title, String? body}) {
    final type = _typeOf(n);
    if (type.contains('points') || '${title ?? ''} ${body ?? ''}'.toLowerCase().contains('points')) {
      return Icons.stars_rounded;
    }
    return Icons.notifications_rounded;
  }

  String? _actorAvatarUrl(Map<String, dynamic> n) {
    String? raw;
    final data = _dataMap(n);
    if (data != null) {
      raw = (data['profile_picture'] ??
              data['profile_picture_url'] ??
              data['actor_profile_picture'] ??
              data['from_user_picture'] ??
              data['picture'] ??
              data['avatar'])
          ?.toString();
      final actor = data['actor'] ?? data['from_user'] ?? data['user'] ?? data['sender'];
      if ((raw == null || raw.isEmpty) && actor is Map) {
        raw = (actor['profile_picture'] ??
                actor['profile_picture_url'] ??
                actor['picture'] ??
                actor['avatar'])
            ?.toString();
      }
    }
    raw ??= _pickString(n, [
      'profile_picture',
      'profile_picture_url',
      'actor_profile_picture',
      'from_user_picture',
      'picture',
      'avatar',
    ]);
    if (raw == null || raw.trim().isEmpty) return null;
    final pic = raw.trim();
    if (pic.startsWith('http')) return pic;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return pic.startsWith('/') ? '$base$pic' : '$base/$pic';
  }

  Future<void> _deleteOne(Map<String, dynamic> n) async {
    final id = (n['id'] ?? '').toString();
    setState(() {
      _items.removeWhere((item) => identical(item, n) || (id.isNotEmpty && item['id']?.toString() == id));
    });
    _syncCache();
    if (id.isEmpty) return;
    try {
      await notificationService.deleteNotification(id);
    } catch (_) {
      // Keep optimistic removal; backend may not be ready yet.
    }
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Delete all notifications?', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800)),
        content: Text('This removes every notification from your inbox.', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete all', style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _items = []);
    _syncCache();
    try {
      await notificationService.deleteAllNotifications();
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await notificationService.markAllAsRead();
      if (!mounted) return;
      setState(() {
        // Drop message notifications entirely; mark others as read.
        _items.removeWhere((n) {
          final t = _pickString(n, ['title', 'notification_title', 'name', 'from_user_name']) ?? '';
          final b = _pickString(n, ['body', 'message', 'content', 'text']) ?? '';
          return _isNewMessage(n, title: t, body: b);
        });
        for (final n in _items) {
          n['is_read'] = true;
          n['read'] = true;
        }
      });
      _syncCache();
    } catch (_) {}
  }

  void _syncCache() {
    _cache = List<Map<String, dynamic>>.from(_items.map((m) => Map<String, dynamic>.from(m)));
    _cacheAt = DateTime.now();
  }

  Future<void> _markOneRead(Map<String, dynamic> n, {bool removeIfMessage = false}) async {
    final id = (n['id'] ?? '').toString();
    final already = _pickBool(n, ['read', 'is_read', 'isRead']) ?? false;
    final title = _pickString(n, ['title', 'notification_title', 'name', 'from_user_name']) ?? '';
    final body = _pickString(n, ['body', 'message', 'content', 'text']) ?? '';
    final isMessage = _isNewMessage(n, title: title, body: body);

    if (isMessage || removeIfMessage) {
      setState(() {
        _items.removeWhere((item) => identical(item, n) || (id.isNotEmpty && (item['id']?.toString() == id)));
      });
      _syncCache();
    } else if (!already) {
      setState(() {
        n['is_read'] = true;
        n['read'] = true;
      });
      _syncCache();
    }

    if (id.isEmpty || already) return;
    try {
      await notificationService.markAsRead(id);
    } catch (_) {}
  }

  Future<void> _openMessageChat(Map<String, dynamic> n, {required String title}) async {
    final peerId = _relatedUserId(n);
    final peerName = _messageSenderName(n, title: title);

    if (peerId == null || peerId.isEmpty) {
      customSnackBar('Info', 'Open Messages to continue the conversation', type: SnackType.info);
      Get.offAllNamed('/home', arguments: {'openTab': 'chat'});
      return;
    }

    final profile = AuthService().getCachedProfile();
    final currentUserId = profile != null && profile['id'] != null && profile['id'].toString().isNotEmpty
        ? profile['id'].toString()
        : 'me';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          currentUserId: currentUserId,
          peerId: peerId,
          peerName: peerName,
          isConnected: true,
        ),
      ),
    );
  }

  String _messageSenderName(Map<String, dynamic> n, {required String title}) {
    final data = _dataMap(n);
    if (data != null) {
      final fromData = (data['senderName'] ?? data['sender_name'] ?? data['peerName'] ?? data['name'])?.toString();
      if (fromData != null && fromData.isNotEmpty) return fromData;
    }
    final fromRoot = _pickString(n, ['from_user_name', 'sender_name', 'senderName', 'name']);
    if (fromRoot != null && fromRoot.isNotEmpty) return fromRoot;
    // Title is often "New message from Alice"
    final m = RegExp(r'from\s+(.+)$', caseSensitive: false).firstMatch(title);
    if (m != null) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return 'Chat';
  }

  void _onTap(Map<String, dynamic> n, {required String title, required String body}) {
    if (_isNewMessage(n, title: title, body: body)) {
      _markOneRead(n, removeIfMessage: true);
      _openMessageChat(n, title: title);
      return;
    }

    _markOneRead(n);

    if (_isVideoIntroRequest(n, title: title, body: body) || _isVideoIntroAccepted(n, title: title, body: body)) {
      _openVideoIntro(n);
      return;
    }
    if (_isFriendRequest(n, title: title, body: body) || _isConnectionMade(n, title: title, body: body)) {
      final profile = AuthService().getCachedProfile();
      final currentUserId = profile != null && profile['id'] != null && profile['id'].toString().isNotEmpty
          ? profile['id'].toString()
          : 'me';
      if (_isConnectionMade(n, title: title, body: body)) {
        final userId = _relatedUserId(n);
        if (userId != null && userId.isNotEmpty) {
          openUserProfile(context, userId: userId, fallbackName: title, isAlreadyConnected: true);
          return;
        }
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RequestsScreen(currentUserId: currentUserId)),
      );
      return;
    }
    if (_isPointsNotification(n, title: title, body: body)) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PointsWalletScreen()),
      );
      return;
    }
    if (_isPostNotification(n, title: title, body: body)) {
      final postId = _relatedPostId(n);
      if (postId != null && postId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
        );
        return;
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title, style: AppTextStyles.ui(size: 18, weight: FontWeight.w800)),
        content: Text(body.isNotEmpty ? body : 'No additional details', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  String _relativeTime(String? isoOrMillis) {
    if (isoOrMillis == null || isoOrMillis.isEmpty) return '';
    DateTime? dt;
    try {
      if (RegExp(r'^\d{10,}$').hasMatch(isoOrMillis)) {
        final ms = int.tryParse(isoOrMillis);
        if (ms != null) dt = DateTime.fromMillisecondsSinceEpoch(ms);
      }
      dt ??= DateTime.tryParse(isoOrMillis);
    } catch (_) {}
    dt ??= DateTime.now();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k].toString();
    }
    return null;
  }

  bool? _pickBool(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        final v = m[k];
        if (v is bool) return v;
        if (v is num) return v != 0;
        final s = v.toString().toLowerCase();
        if (s == 'true') return true;
        if (s == 'false') return false;
      }
    }
    return null;
  }

  bool _isVideoIntroRequest(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('video_call_request') || type.contains('video_intro_request')) return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('guided video intro') ||
        text.contains('video intro request') ||
        text.contains('incoming voice call') ||
        text.contains('incoming video call') ||
        text.contains('is calling you') ||
        text.contains('is video calling you');
  }

  bool _isVideoIntroAccepted(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('video_call_accepted') || type.contains('video_intro_accepted')) return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('accepted your video') ||
        text.contains('intro was accepted') ||
        text.contains('call accepted') ||
        text.contains('call was accepted');
  }

  /// Rewrite legacy "guided video intro" copy for display.
  ({String title, String body}) _displayCallCopy(Map<String, dynamic> n, String title, String body) {
    final data = _dataMap(n);
    final callType = (data?['call_type'] ?? data?['callType'] ?? '').toString().toLowerCase();
    final isVoice = callType == 'voice' ||
        title.toLowerCase().contains('voice') ||
        body.toLowerCase().contains('voice');
    final type = _typeOf(n);
    final legacy = title.toLowerCase().contains('video intro') ||
        body.toLowerCase().contains('guided video intro') ||
        body.toLowerCase().contains('video intro');

    if (_isVideoIntroRequest(n, title: title, body: body) &&
        (legacy || type.contains('video_call_request'))) {
      final name = _callerNameFromNotif(n, body);
      return (
        title: isVoice ? 'Incoming voice call' : 'Incoming video call',
        body: name.isNotEmpty
            ? (isVoice ? '$name is calling you' : '$name is video calling you')
            : (isVoice ? 'Someone is calling you' : 'Someone is video calling you'),
      );
    }
    if (_isVideoIntroAccepted(n, title: title, body: body) && legacy) {
      return (
        title: 'Call accepted',
        body: isVoice ? 'Your voice call was accepted' : 'Your video call was accepted',
      );
    }
    if ((type.contains('video_call_rejected') || title.toLowerCase().contains('declined')) &&
        legacy) {
      return (
        title: 'Call declined',
        body: isVoice ? 'Your voice call was declined' : 'Your video call was declined',
      );
    }
    return (title: title, body: body);
  }

  String _callerNameFromNotif(Map<String, dynamic> n, String body) {
    final data = _dataMap(n);
    final fromData = (data?['caller_name'] ?? data?['callerName'] ?? data?['from_user_name'])
        ?.toString()
        .trim();
    if (fromData != null && fromData.isNotEmpty) return fromData;
    // Legacy: "Alice wants a guided video intro"
    final lower = body.toLowerCase();
    final idx = lower.indexOf(' wants ');
    if (idx > 0) return body.substring(0, idx).trim();
    final callIdx = lower.indexOf(' is calling');
    if (callIdx > 0) return body.substring(0, callIdx).trim();
    final videoIdx = lower.indexOf(' is video calling');
    if (videoIdx > 0) return body.substring(0, videoIdx).trim();
    return '';
  }

  bool _isConnectionMade(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('connection_made') || type.contains('follow_accepted')) return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('connected with you') || text.contains('you are now connected');
  }

  bool _isPointsNotification(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('points_earned') || type.contains('points_updated')) return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('points') && (text.contains('earned') || text.contains('awarded'));
  }

  bool _isPostNotification(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('post_liked') || type.contains('post_commented') || type.contains('comment')) return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('liked your post') || text.contains('commented on your post');
  }

  String _typeOf(Map<String, dynamic> m) {
    for (final k in ['type', 'notification_type', 'category', 'action', 'event']) {
      final v = m[k];
      if (v != null) return v.toString().toLowerCase();
    }
    return '';
  }

  Map<String, dynamic>? _dataMap(Map<String, dynamic> n) {
    final data = n['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String? _relatedUserId(Map<String, dynamic> n) {
    final data = _dataMap(n);
    if (data != null) {
      final id = (data['senderId'] ??
              data['sender_id'] ??
              data['peerId'] ??
              data['peer_id'] ??
              data['user_id'] ??
              data['userId'] ??
              data['from_user_id'] ??
              data['actor_id'])
          ?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return (n['senderId'] ??
            n['sender_id'] ??
            n['peerId'] ??
            n['user_id'] ??
            n['from_user_id'] ??
            n['actor_id'])
        ?.toString();
  }

  String? _relatedPostId(Map<String, dynamic> n) {
    final data = _dataMap(n);
    if (data != null) {
      final id = (data['post_id'] ?? data['postId'] ?? data['reference_id'] ?? data['id'])?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return (n['post_id'] ?? n['postId'] ?? n['reference_id'])?.toString();
  }

  Future<void> _openVideoIntro(Map<String, dynamic> n) async {
    String? callId;
    final data = _dataMap(n);
    if (data != null) {
      callId = (data['callId'] ?? data['call_id'] ?? data['id'])?.toString();
    }
    callId ??= (n['call_id'] ?? n['callId'] ?? n['reference_id'])?.toString();

    if (callId == null || callId.isEmpty) {
      customSnackBar('Info', 'Open Connections to manage video calls', type: SnackType.info);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final history = await VideoCallService().getHistory(limit: 30);
      VideoCall? match;
      for (final c in history.items) {
        if (c.id == callId) {
          match = c;
          break;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();

      if (match == null) {
        customSnackBar('Call expired', 'This call is no longer available', type: SnackType.info);
        return;
      }

      final expired = match.status == VideoCallStatus.missed ||
          match.status == VideoCallStatus.cancelled ||
          match.status == VideoCallStatus.rejected ||
          match.status == VideoCallStatus.completed ||
          match.status == VideoCallStatus.unknown ||
          (match.status == VideoCallStatus.pending &&
              match.expiresAt != null &&
              match.expiresAt!.isBefore(DateTime.now()));

      if (expired) {
        final msg = match.status == VideoCallStatus.rejected
            ? 'This call was declined'
            : match.status == VideoCallStatus.cancelled
                ? 'This call was cancelled'
                : match.status == VideoCallStatus.completed
                    ? 'This call has ended'
                    : 'Call already expired';
        customSnackBar('Unavailable', msg, type: SnackType.info);
        return;
      }

      if (match.status == VideoCallStatus.pending) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoCallIncomingScreen(call: match!)),
        );
      } else if (match.status == VideoCallStatus.active) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoCallScreen(call: match!, isCaller: false)),
        );
      } else {
        customSnackBar('Info', 'This call is no longer available', type: SnackType.info);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      customSnackBar('Error', e.toString().replaceAll('ApiException: ', ''), type: SnackType.error);
    }
  }

  bool _isCircleJoinNotification(Map<String, dynamic> m) {
    final type = _typeOf(m);
    if (type.contains('circle_join') || type == 'circle_joined') return true;
    final title = (_pickString(m, ['title', 'notification_title']) ?? '').toLowerCase();
    final body = (_pickString(m, ['body', 'message', 'content', 'text']) ?? '').toLowerCase();
    final text = '$title $body';
    return text.contains('welcome to the circle') || text.contains('you joined ');
  }

  bool _isFriendRequest(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('follow_request') ||
        type.contains('friend_request') ||
        type.contains('connection_request') ||
        type.contains('new_follow_request') ||
        type.contains('request_received')) {
      return true;
    }
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    if (text.contains('follow request') ||
        text.contains('friend request') ||
        text.contains('connection request') ||
        text.contains('requested to follow') ||
        text.contains('wants to follow') ||
        text.contains('wants to connect') ||
        text.contains('sent you a request')) {
      return true;
    }
    return false;
  }

  bool _isNewMessage(Map<String, dynamic> m, {String? title, String? body}) {
    final type = _typeOf(m);
    if (type.contains('new_message') || type.contains('message') || type == 'chat') return true;
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    return text.contains('new message') || text.contains('sent you a message') || text.contains('messaged you');
  }
}
