import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/circle.dart';
import '../models/post.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/circle_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/circle_cover.dart';
import '../utils/custom_snackbar.dart';
import '../utils/open_user_profile.dart';
import '../utils/points_toast.dart';
import '../theme/layout_insets.dart';
import '../widgets/empty_state.dart';
import '../widgets/post_card.dart';
import '../widgets/safety_dialogs.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

class CircleDetailScreen extends StatefulWidget {
  final String circleId;
  final Circle? initial;

  const CircleDetailScreen({super.key, required this.circleId, this.initial});

  @override
  State<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends State<CircleDetailScreen> {
  final _circles = CircleService();
  final _posts = PostService();

  Circle? _circle;
  final List<Post> _items = [];
  bool _loading = true;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _circle = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _circles.getCircle(widget.circleId),
        _circles.getCirclePosts(widget.circleId),
      ]);
      if (!mounted) return;
      setState(() {
        _circle = results[0] as Circle;
        _items
          ..clear()
          ..addAll((results[1] as PaginatedPosts).items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? (e.message ?? 'Failed to load') : e.toString();
      });
    }
  }

  Future<void> _toggleJoin() async {
    final circle = _circle;
    if (circle == null || _joining) return;
    setState(() => _joining = true);
    HapticFeedback.selectionClick();
    try {
      if (circle.isJoined) {
        await _circles.leave(circle.id);
        setState(() {
          _circle = circle.copyWith(isJoined: false, memberCount: (circle.memberCount - 1).clamp(0, 999999));
        });
        customSnackBar('Success', 'Left ${circle.name}', type: SnackType.success);
      } else {
        final result = await _circles.join(circle.id);
        final awarded = result['points_awarded'];
        setState(() {
          _circle = circle.copyWith(isJoined: true, memberCount: circle.memberCount + 1);
        });
        if (awarded is int && awarded > 0) {
          showPointsToast(awarded, reason: 'Joined ${circle.name}');
        } else {
          customSnackBar('Success', 'Joined ${circle.name}', type: SnackType.success);
        }
      }
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not update') : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _toggleLike(Post post) async {
    final index = _items.indexWhere((p) => p.id == post.id);
    if (index < 0) return;
    final wasLiked = post.isLikedByMe;
    setState(() {
      _items[index] = post.copyWith(
        isLikedByMe: !wasLiked,
        likeCount: wasLiked ? (post.likeCount - 1).clamp(0, 999999) : post.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await _posts.unlikePost(post.id);
      } else {
        await _posts.likePost(post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _items[index] = post);
    }
  }

  void _openCreate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          initialCircleId: widget.circleId,
          onPosted: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final circle = _circle;

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: circle?.isJoined == true
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              label: Text('Post here', style: AppTextStyles.ui(color: AppColors.white, weight: FontWeight.w700)),
            )
          : null,
      body: _loading && circle == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null && circle == null
              ? EmptyState(
                  title: 'Couldn’t load circle',
                  subtitle: _error!,
                  primaryLabel: 'Try again',
                  onPrimary: _load,
                  icon: Icons.groups_outlined,
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        expandedHeight: 200,
                        pinned: true,
                        backgroundColor: AppColors.primaryDeep,
                        iconTheme: const IconThemeData(color: Colors.white),
                        flexibleSpace: FlexibleSpaceBar(
                          title: Text(
                            circle?.name ?? 'Circle',
                            style: AppTextStyles.ui(size: 16, weight: FontWeight.w800, color: AppColors.white),
                          ),
                          background: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                CircleCover.resolve(
                                  iconUrl: circle?.iconUrl,
                                  slug: circle?.slug,
                                  name: circle?.name,
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(gradient: AppColors.heroOverlay),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          if (circle != null)
                            TextButton(
                              onPressed: _joining ? null : _toggleJoin,
                              child: Text(
                                circle.isJoined ? 'Leave' : 'Join',
                                style: AppTextStyles.ui(color: AppColors.white, weight: FontWeight.w800),
                              ),
                            ),
                        ],
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.groups_rounded, size: 16, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${circle?.memberCount ?? 0} members',
                                      style: AppTextStyles.ui(
                                        size: 13,
                                        weight: FontWeight.w700,
                                        color: AppColors.primaryDeep,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (circle?.description != null && circle!.description!.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Text(circle.description!, style: AppTextStyles.body),
                          ),
                        ),
                      if (_items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            title: 'No posts yet',
                            subtitle: 'Be the first to share in this circle',
                            primaryLabel: circle?.isJoined == true ? 'Create post' : 'Join circle',
                            onPrimary: circle?.isJoined == true ? _openCreate : _toggleJoin,
                            icon: Icons.forum_outlined,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(0, 12, 0, LayoutInsets.navClearance(context)),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final post = _items[i];
                                final myId = AuthService().getCachedProfile()?['id']?.toString();
                                final isMine = myId != null && post.user.id == myId;
                                return PostCard(
                                  post: post,
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
                                  onReport: isMine
                                      ? null
                                      : () async {
                                          final reason = await showReportReasonDialog(context, title: 'Report post');
                                          if (reason == null) return;
                                          try {
                                            await PostService().reportPost(
                                              post.id,
                                              reason: reason.isEmpty ? null : reason,
                                            );
                                            customSnackBar('Success', 'Thanks — we received your report', type: SnackType.success);
                                          } catch (e) {
                                            customSnackBar(
                                              'Error',
                                              e is ApiException ? (e.message ?? 'Report failed') : e.toString(),
                                              type: SnackType.error,
                                            );
                                          }
                                        },
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
                              childCount: _items.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
