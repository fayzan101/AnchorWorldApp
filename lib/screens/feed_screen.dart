import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/layout_insets.dart';
import '../utils/app_caches.dart';
import '../utils/custom_snackbar.dart';
import '../utils/open_user_profile.dart';
import '../widgets/empty_state.dart';
import '../widgets/feed_coach_marks.dart';
import '../widgets/post_card.dart';
import '../widgets/safety_dialogs.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'people_search_screen.dart';
import '../config/api_config.dart';
import '../models/post.dart';
import '../network/api_client.dart' show ApiException;

class _FeedBucket {
  final List<Post> posts;
  final int page;
  final bool hasMore;
  final DateTime updatedAt;
  _FeedBucket({
    required this.posts,
    required this.page,
    required this.hasMore,
  }) : updatedAt = DateTime.now();

  bool get isFresh => DateTime.now().difference(updatedAt) < const Duration(minutes: 3);
}

class FeedScreen extends StatefulWidget {
  final VoidCallback? onOpenCircles;
  final VoidCallback? onCreatePost;
  final VoidCallback? onOpenPoints;

  const FeedScreen({
    super.key,
    this.onOpenCircles,
    this.onCreatePost,
    this.onOpenPoints,
  });

  static void clearCache([String? filter]) {
    if (filter == null) {
      _FeedScreenState._cache.clear();
    } else {
      _FeedScreenState._cache.remove(filter);
    }
  }

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _filters = [
    ('circles', 'My Circles'),
    ('following', 'Following'),
    ('local', 'Local'),
    ('all', 'All'),
  ];

  static final Map<String, _FeedBucket> _cache = {};

  final _service = PostService();
  final _scroll = ScrollController();

  String _filter = 'circles';
  final List<Post> _posts = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final cached = _cache[_filter];
    if (cached != null && cached.posts.isNotEmpty) {
      _posts
        ..clear()
        ..addAll(cached.posts);
      _page = cached.page;
      _hasMore = cached.hasMore;
      _loading = false;
      _load(refresh: true, silent: cached.isFresh);
    } else {
      _load(refresh: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load({bool refresh = false, bool silent = false}) async {
    if (refresh && !silent) {
      setState(() {
        _loading = _posts.isEmpty;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      final result = await _service.getFeed(filter: _filter, page: 1, limit: 20);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(result.items);
        _page = 1;
        _hasMore = result.hasMore;
        _loading = false;
        _error = null;
      });
      _cache[_filter] = _FeedBucket(
        posts: List<Post>.from(result.items),
        page: 1,
        hasMore: result.hasMore,
      );
      _precachePostImages(result.items.take(6));
    } catch (e) {
      if (!mounted) return;
      // Local feed returns 400 when the user has no location set.
      // Treat this as an empty/info state rather than a hard error.
      final isLocalNeedsLocation = _filter == 'local' &&
          (e is ApiException && (e.statusCode == 400 || e.statusCode == 422) ||
              e.toString().toLowerCase().contains('location') ||
              e.toString().toLowerCase().contains('400'));
      setState(() {
        _loading = false;
        if (_posts.isEmpty) {
          _error = isLocalNeedsLocation
              ? 'location_required'
              : (e is ApiException ? (e.message ?? 'Failed to load feed') : e.toString());
        }
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await _service.getFeed(filter: _filter, page: next, limit: 20);
      if (!mounted) return;
      setState(() {
        _posts.addAll(result.items);
        _page = next;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
      _cache[_filter] = _FeedBucket(
        posts: List<Post>.from(_posts),
        page: next,
        hasMore: result.hasMore,
      );
      _precachePostImages(result.items.take(4));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _precachePostImages(Iterable<Post> posts) {
    for (final post in posts) {
      final path = post.mediaUrl;
      if (path == null || path.isEmpty || post.mediaType != 'image') continue;
      final url = path.startsWith('http')
          ? path
          : '${ApiConfig.baseUrl.replaceAll('/api', '')}${path.startsWith('/') ? path : '/$path'}';
      precacheImage(NetworkImage(url), context).catchError((_) {});
    }
  }

  Future<void> _toggleLike(Post post) async {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index < 0) return;
    final wasLiked = post.isLikedByMe;
    setState(() {
      _posts[index] = post.copyWith(
        isLikedByMe: !wasLiked,
        likeCount: wasLiked ? (post.likeCount - 1).clamp(0, 999999) : post.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await _service.unlikePost(post.id);
      } else {
        await _service.likePost(post.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _posts[index] = post);
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not update like') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  Future<void> _editPost(Post post) async {
    final updated = await Navigator.of(context).push<Post>(
      MaterialPageRoute(builder: (_) => CreatePostScreen(editPost: post)),
    );
    if (updated == null || !mounted) return;
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index >= 0) {
      setState(() => _posts[index] = updated);
    }
  }

  Future<void> _deletePost(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deletePost(post.id);
      AppCaches.invalidateAfterPost();
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      customSnackBar('Success', 'Post deleted', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Delete failed') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  Future<void> _reportPost(Post post) async {
    final myId = AuthService().getCachedProfile()?['id']?.toString();
    if (myId != null && post.user.id == myId) {
      customSnackBar('Info', 'You can’t report your own post', type: SnackType.info);
      return;
    }
    final reason = await showReportReasonDialog(context, title: 'Report post');
    if (reason == null) return;
    try {
      await _service.reportPost(post.id, reason: reason.isEmpty ? null : reason);
      customSnackBar('Success', 'Thanks — we received your report', type: SnackType.success);
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Report failed') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PeopleSearchScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.mutedBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Find people to connect with…',
                            style: AppTextStyles.ui(size: 14, color: AppColors.body),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.body.withOpacity(0.6)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (key, label) = _filters[i];
                  final selected = _filter == key;
                  return GestureDetector(
                    onTap: () {
                      if (_filter == key) return;
                      setState(() => _filter = key);
                      final cached = _cache[key];
                      if (cached != null && cached.posts.isNotEmpty) {
                        setState(() {
                          _posts
                            ..clear()
                            ..addAll(cached.posts);
                          _page = cached.page;
                          _hasMore = cached.hasMore;
                          _loading = false;
                          _error = null;
                        });
                        _load(refresh: true, silent: cached.isFresh);
                      } else {
                        _load(refresh: true);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.brandGradient : null,
                        color: selected ? null : AppColors.chipIdle,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: selected ? AppColors.cardShadow : null,
                      ),
                      child: Text(
                        label,
                        style: AppTextStyles.ui(
                          size: 13,
                          weight: FontWeight.w700,
                          color: selected ? AppColors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
        FeedCoachMarks(
          onOpenCircles: widget.onOpenCircles,
          onOpenPoints: widget.onOpenPoints,
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(0, 8, 0, LayoutInsets.navClearance(context)),
        itemCount: 4,
        itemBuilder: (_, __) => const _FeedSkeleton(),
      );
    }

    if (_error != null && _posts.isEmpty) {
      if (_error == 'location_required') {
        return EmptyState(
          title: 'Location not set',
          subtitle: 'Add your city in your profile to see posts from people near you.',
          primaryLabel: 'Edit profile',
          onPrimary: () => Navigator.of(context).pushNamed('/profile'),
          icon: Icons.location_off_rounded,
        );
      }
      return EmptyState(
        title: 'Couldn’t load feed',
        subtitle: _error!,
        primaryLabel: 'Try again',
        onPrimary: () => _load(refresh: true),
        icon: Icons.wifi_off_rounded,
      );
    }

    if (_posts.isEmpty) {
      return EmptyState(
        title: 'No posts yet',
        subtitle: _filter == 'circles'
            ? 'Join a circle to see posts here'
            : 'Nothing to show for this filter yet',
        primaryLabel: _filter == 'circles' ? 'Explore Circles' : 'Refresh',
        onPrimary: () {
          if (_filter == 'circles') {
            widget.onOpenCircles?.call();
          } else {
            _load(refresh: true);
          }
        },
        secondaryLabel: _filter == 'circles' ? 'Create a post' : null,
        onSecondary: widget.onCreatePost,
        icon: Icons.forum_outlined,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(refresh: true),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(0, 8, 0, LayoutInsets.navClearance(context)),
        itemCount: _posts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }
          final post = _posts[index];
          final myId = AuthService().getCachedProfile()?['id']?.toString();
          final isMine = myId != null && post.user.id == myId;
          return PostCard(
            post: post,
            staggerIndex: index < 5 ? index : null,
            isOwnPost: isMine,
            onLikeToggle: () => _toggleLike(post),
            onCommentTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
                ),
              );
            },
            onAuthorTap: () => openUserProfile(
              context,
              userId: post.user.id,
              fallbackName: post.user.fullName,
            ),
            onCircleTap: () {},
            onEdit: isMine ? () => _editPost(post) : null,
            onDelete: isMine ? () => _deletePost(post) : null,
            onReport: isMine ? null : () => _reportPost(post),
            onOpenSourcePost: (post.sourcePostId ?? '').isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.sourcePostId!),
                      ),
                    );
                  },
          );
        },
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bone({double? width, double height = 12, double radius = 8}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.chipIdle,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bone(width: 44, height: 44, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bone(width: 120, height: 14),
                    const SizedBox(height: 8),
                    bone(width: 72, height: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          bone(height: 12),
          const SizedBox(height: 8),
          bone(width: 180, height: 12),
          const SizedBox(height: 14),
          bone(height: 120, radius: 16),
        ],
      ),
    );
  }
}
