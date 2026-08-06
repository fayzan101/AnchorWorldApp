import 'dart:ui';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/fcm_service.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/empty_state.dart';
import 'friends_screen.dart';

import '../config/api_config.dart';
import '../services/message_service.dart';
import '../theme/layout_insets.dart';
import 'chat_screen.dart';
import '../utils/custom_snackbar.dart';

class ChatsListScreen extends StatefulWidget {
  final String currentUserId;
  final VoidCallback? onReturnFromChat;
  /// When true (home tab), hide the local AppBar to avoid a double bar.
  final bool embedded;
  const ChatsListScreen({
    Key? key,
    required this.currentUserId,
    this.onReturnFromChat,
    this.embedded = false,
  }) : super(key: key);
  static void clearCache() {
    _ChatsListScreenState._conversationsCache = null;
  }

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allConversations = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  static List<Map<String, dynamic>>? _conversationsCache;
  String? _selectedUserId;
  String? _selectedUserName;
  StreamSubscription<RemoteMessage>? _fcmOnMessageSub;
  StreamSubscription<RemoteMessage>? _fcmOnOpenedSub;
  StreamSubscription<void>? _notifArrivedSub;
  StreamSubscription<void>? _conversationsUpdatedSub;

  Future<void> _deleteConversation(String userId, String userName) async {
    if (userId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final ok = await MessageService().deleteConversation(userId: userId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _allConversations.removeWhere((c) {
            final u = c['user'] ?? c['other_user'] ?? {};
            return (u['id']?.toString() ?? '') == userId;
          });
          _conversations.removeWhere((c) {
            final u = c['user'] ?? c['other_user'] ?? {};
            return (u['id']?.toString() ?? '') == userId;
          });
          _conversationsCache = List<Map<String, dynamic>>.from(_allConversations);
          if (_selectedUserId == userId) {
            _selectedUserId = null;
            _selectedUserName = null;
          }
        });
        ChatScreen.clearCacheForPeer(widget.currentUserId, userId);
        customSnackBar('Success', 'Deleted conversation with $userName');
      } else {
        customSnackBar('Error', 'Failed to delete conversation');
      }
    } catch (e) {
      if (!mounted) return;
      customSnackBar('Error', e.toString().replaceAll('ApiException: ', ''));
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_conversationsCache != null && _conversationsCache!.isNotEmpty) {
      _allConversations = List<Map<String, dynamic>>.from(_conversationsCache!);
      _conversations = List<Map<String, dynamic>>.from(_conversationsCache!);
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadConversations());
    } else {
      _loadConversations();
    }
    try {
      _fcmOnMessageSub = FirebaseMessaging.onMessage.listen((message) {
        _loadConversations();
      });
      _fcmOnOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _loadConversations();
      });
      final fcmService = FcmService();
      _notifArrivedSub = fcmService.onNotificationArrived.listen((_) {
        _loadConversations();
      });
      _conversationsUpdatedSub = fcmService.onConversationsUpdated.listen((_) {
        _loadConversations();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fcmOnMessageSub?.cancel();
    _fcmOnOpenedSub?.cancel();
    _notifArrivedSub?.cancel();
    _conversationsUpdatedSub?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadConversations();
    }
  }

  Future<void> _loadConversations() async {
    if (_conversations.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = false;
        _error = null;
      });
    }

    try {
      final convs = await MessageService().getConversations();
      if (mounted) {
        setState(() {
          _allConversations = List<Map<String, dynamic>>.from(convs);
          _loading = false;
        });
        _conversationsCache = List<Map<String, dynamic>>.from(convs);
        _applyFilter(_searchController.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
          _loading = false;
          _conversations = [];
          _allConversations = [];
        });
      }
    }
  }

  void _applyFilter([String? q]) {
    final query = (q ?? _searchController.text).toString().toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _conversations = List<Map<String, dynamic>>.from(_allConversations);
      } else {
        _conversations = _allConversations.where((c) {
          final u = c['user'] ?? c['other_user'] ?? {};
          final name = (u['name'] ?? u['full_name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        }).toList();
      }
    });
  }

  String _resolveImage(String raw) {
    if (raw.isEmpty || raw == 'null') return '';
    if (raw.startsWith('http')) return raw;
    try {
      var path = raw;
      if (path.startsWith('/api') && ApiConfig.baseUrl.endsWith('/api')) {
        path = path.substring('/api'.length);
      }
      var base = ApiConfig.baseUrl;
      if (base.endsWith('/api')) base = base.substring(0, base.length - 4);
      if (path.contains('/api/profile/picture/') || path.contains('/profile/picture/')) {
        path = path.replaceFirst('/api/profile/picture/', '/uploads/');
        path = path.replaceFirst('/profile/picture/', '/uploads/');
      }
      return '$base$path';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedUserId != null) {
          setState(() {
            _selectedUserId = null;
            _selectedUserName = null;
          });
          return false;
        }
        if (widget.embedded) return true;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: widget.embedded
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                  ),
                  flexibleSpace: ClipRRect(
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
                    ),
                  ),
                  leading: IconButton(
                    icon: Icon(_selectedUserId != null ? Icons.close : Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      if (_selectedUserId != null) {
                        setState(() {
                          _selectedUserId = null;
                          _selectedUserName = null;
                        });
                      } else {
                        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                      }
                    },
                  ),
                  title: Text(
                    _selectedUserId != null ? '1 selected' : 'Messages',
                    style: AppTextStyles.ui(size: 20, weight: FontWeight.w800, color: AppColors.white),
                  ),
                  iconTheme: const IconThemeData(color: Colors.white),
                  actions: [
                    if (_selectedUserId != null)
                      IconButton(
                        tooltip: 'Delete conversation',
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                        onPressed: () {
                          final uid = _selectedUserId!;
                          final uname = _selectedUserName ?? 'User';
                          _deleteConversation(uid, uname);
                        },
                      )
                    else
                      IconButton(
                        tooltip: 'Connections',
                        icon: const Icon(Icons.people_outline, color: Colors.white),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const FriendsScreen()),
                        ),
                      ),
                  ],
                ),
              ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (_selectedUserId != null && widget.embedded)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _selectedUserId = null;
                        _selectedUserName = null;
                      }),
                    ),
                  Expanded(
                    child: _selectedUserId != null
                        ? Text(
                            '1 conversation selected',
                            style: AppTextStyles.ui(size: 15, weight: FontWeight.w700),
                          )
                        : TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            autofocus: false,
                            onTapOutside: (_) => _searchFocus.unfocus(),
                            onChanged: (v) {
                              _applyFilter(v);
                              setState(() {});
                            },
                            style: AppTextStyles.ui(size: 15),
                            decoration: InputDecoration(
                              hintText: 'Search conversations',
                              hintStyle: AppTextStyles.ui(size: 14, color: AppColors.body),
                              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.body),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        _applyFilter('');
                                        setState(() {});
                                      },
                                    )
                                  : null,
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
                  ),
                  if (_selectedUserId != null)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () {
                        final uid = _selectedUserId!;
                        final uname = _selectedUserName ?? 'User';
                        _deleteConversation(uid, uname);
                      },
                    )
                  else if (widget.embedded)
                    IconButton(
                      tooltip: 'Connections',
                      icon: const Icon(Icons.people_outline_rounded, color: AppColors.primary),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FriendsScreen()),
                      ),
                    ),
                ],
              ),
            ),
            if (!_loading && _allConversations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_conversations.length} conversation${_conversations.length == 1 ? '' : 's'}',
                    style: AppTextStyles.ui(size: 12, weight: FontWeight.w700, color: AppColors.body),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _conversations.isEmpty
                      ? EmptyState(
                          title: _searchController.text.trim().isNotEmpty ? 'No matches' : 'No chats yet',
                          subtitle: _error == null
                              ? (_searchController.text.trim().isNotEmpty
                                  ? 'Try a different name.'
                                  : 'Start a conversation with someone you’re connected with.')
                              : 'Failed to load conversations: ${_error ?? ''}',
                          primaryLabel: 'View Connections',
                          onPrimary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
                          secondaryLabel: _error != null ? 'Retry' : null,
                          onSecondary: _error != null ? _loadConversations : null,
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadConversations,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(16, 4, 16, LayoutInsets.navClearance(context)),
                            itemCount: _conversations.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final conv = _conversations[i];
                              final user = conv['user'] ?? conv['other_user'] ?? {};
                              final userId = user['id']?.toString() ?? '';
                              final userName = user['name']?.toString() ?? user['full_name']?.toString() ?? 'User';
                              final userImage = _resolveImage(
                                user['imageUrl']?.toString() ??
                                    user['profile_picture']?.toString() ??
                                    user['avatar']?.toString() ??
                                    '',
                              );
                              final lastMsg = conv['last_message'] ?? conv['lastMessage'];
                              String lastContent = '';
                              String lastTime = '';
                              bool sentByMe = false;
                              if (lastMsg is Map) {
                                lastContent =
                                    (lastMsg['content'] ?? lastMsg['text'] ?? lastMsg['message'] ?? '').toString();
                                lastTime =
                                    (lastMsg['timestamp'] ?? lastMsg['created_at'] ?? lastMsg['createdAt'] ?? '')
                                        .toString();
                                sentByMe = lastMsg['is_sent_by_me'] == true || lastMsg['isSentByMe'] == true;
                              } else if (lastMsg is String) {
                                lastContent = lastMsg;
                              }
                              final preview = lastContent.isEmpty
                                  ? 'Say hi!'
                                  : (sentByMe ? 'You: $lastContent' : lastContent);
                              final unreadRaw = conv['unread_count'] ?? conv['unreadCount'] ?? 0;
                              final unreadCount =
                                  unreadRaw is int ? unreadRaw : (int.tryParse(unreadRaw.toString()) ?? 0);
                              final hasUnread = unreadCount > 0;
                              final isSelected = _selectedUserId == userId;
                              final online = user['is_online'] == true || user['online'] == true;

                              return Material(
                                color: isSelected ? AppColors.primary.withOpacity(0.06) : AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () async {
                                    if (_selectedUserId != null) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedUserId = null;
                                          _selectedUserName = null;
                                        } else {
                                          _selectedUserId = userId;
                                          _selectedUserName = userName;
                                        }
                                      });
                                      return;
                                    }
                                    final result = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          currentUserId: widget.currentUserId,
                                          peerId: userId,
                                          peerName: userName,
                                        ),
                                      ),
                                    );
                                    if (!mounted) return;
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    _searchFocus.unfocus();
                                    try {
                                      // Drop list cache so last-message / unread reflect deletes & new msgs.
                                      _conversationsCache = null;
                                      if (result != null && result is Map && result['markedRead'] == true) {
                                        await _loadConversations();
                                      } else {
                                        await _loadConversations();
                                      }
                                    } catch (_) {
                                      _loadConversations();
                                    }
                                    widget.onReturnFromChat?.call();
                                  },
                                  onLongPress: () {
                                    setState(() {
                                      _selectedUserId = userId;
                                      _selectedUserName = userName;
                                    });
                                  },
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary.withOpacity(0.35)
                                            : AppColors.mutedBorder,
                                      ),
                                      boxShadow: AppColors.cardShadow,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                                    child: Row(
                                      children: [
                                        Stack(
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: AppColors.brandGradient,
                                              ),
                                              child: CircleAvatar(
                                                backgroundColor: AppColors.chipIdle,
                                                backgroundImage:
                                                    userImage.isNotEmpty ? NetworkImage(userImage) : null,
                                                child: userImage.isEmpty
                                                    ? Text(
                                                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                                        style: AppTextStyles.ui(
                                                          size: 20,
                                                          weight: FontWeight.w800,
                                                          color: AppColors.primary,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            ),
                                            if (online)
                                              Positioned(
                                                right: 1,
                                                bottom: 1,
                                                child: Container(
                                                  width: 13,
                                                  height: 13,
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
                                                      userName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTextStyles.ui(
                                                        size: 16,
                                                        weight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    lastTime.isNotEmpty ? _formatTime(lastTime) : '',
                                                    style: AppTextStyles.ui(
                                                      size: 12,
                                                      weight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                                                      color: hasUnread ? AppColors.primary : AppColors.body,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      preview,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTextStyles.ui(
                                                        size: 13,
                                                        weight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                                                        color: hasUnread ? AppColors.ink : AppColors.body,
                                                      ),
                                                    ),
                                                  ),
                                                  if (hasUnread) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                                      alignment: Alignment.center,
                                                      decoration: const BoxDecoration(
                                                        color: AppColors.primary,
                                                        borderRadius: BorderRadius.all(Radius.circular(11)),
                                                      ),
                                                      child: Text(
                                                        unreadCount > 99 ? '99+' : '$unreadCount',
                                                        style: AppTextStyles.ui(
                                                          size: 11,
                                                          weight: FontWeight.w800,
                                                          color: AppColors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(String isoOrRelative) {
    try {
      final dt = DateTime.parse(isoOrRelative);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays >= 1) return '${diff.inDays}d';
      if (diff.inHours >= 1) return '${diff.inHours}h';
      if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return isoOrRelative;
    }
  }
}
