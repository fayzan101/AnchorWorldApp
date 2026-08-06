import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/open_user_profile.dart';
import '../utils/app_caches.dart';
import '../widgets/comment_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/fullscreen_image.dart';
import '../widgets/post_video_player.dart';
import '../widgets/safety_dialogs.dart';
import '../widgets/share_post_sheet.dart';
import 'create_post_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final Post? initialPost;

  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _service = PostService();
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  final _scroll = ScrollController();

  Post? _post;
  final List<PostComment> _comments = [];
  bool _loading = true;
  bool _loadingComments = true;
  bool _sending = false;
  String? _error;
  bool _contentUnavailable = false;
  PostComment? _replyingTo;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _resolveMyId();
    _load();
  }

  Future<void> _resolveMyId() async {
    var id = AuthService().getCachedProfile()?['id']?.toString();
    if (id == null || id.isEmpty) {
      try {
        final profile = await AuthService().getProfile();
        id = profile['id']?.toString();
      } catch (_) {}
    }
    if (mounted && id != null && id.isNotEmpty) {
      setState(() => _myId = id);
    }
  }

  bool _isOwnPost(Post? post) {
    if (post == null) return false;
    final myId = _myId ?? AuthService().getCachedProfile()?['id']?.toString();
    if (myId == null || myId.isEmpty) return false;
    return post.user.id == myId;
  }

  @override
  void dispose() {
    _commentFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _post == null;
      _error = null;
      _contentUnavailable = false;
    });
    try {
      final results = await Future.wait([
        _service.getPost(widget.postId),
        _service.getComments(widget.postId),
      ]);
      if (!mounted) return;
      setState(() {
        _post = results[0] as Post;
        _comments
          ..clear()
          ..addAll((results[1] as PaginatedComments).items);
        _loading = false;
        _loadingComments = false;
      });
    } catch (e) {
      if (!mounted) return;
      final status = e is ApiException ? e.statusCode : null;
      final msg = e is ApiException ? (e.message ?? '') : e.toString();
      final unavailable = status == 404 ||
          status == 400 ||
          msg.toLowerCase().contains('not found') ||
          msg.toLowerCase().contains('deleted');
      setState(() {
        _loading = false;
        _loadingComments = false;
        _contentUnavailable = unavailable && _post == null;
        _error = unavailable
            ? 'Content not available'
            : (e is ApiException ? (e.message ?? 'Failed to load') : e.toString());
      });
    }
  }

  Future<void> _editPost() async {
    final post = _post;
    if (post == null) return;
    final updated = await Navigator.of(context).push<Post>(
      MaterialPageRoute(builder: (_) => CreatePostScreen(editPost: post)),
    );
    if (updated != null && mounted) {
      setState(() => _post = updated);
    }
  }

  Future<void> _deletePost() async {
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
      await _service.deletePost(widget.postId);
      AppCaches.invalidateAfterPost();
      customSnackBar('Success', 'Post deleted', type: SnackType.success);
      if (mounted) Navigator.of(context).pop({'deleted': true});
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Delete failed') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  String _mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    if (path.startsWith('/')) return '$base$path';
    return '$base/$path';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;
    final wasLiked = post.isLikedByMe;
    HapticFeedback.lightImpact();
    setState(() {
      _post = post.copyWith(
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _post = post);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _service.addComment(
        widget.postId,
        text,
        parentId: _replyingTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _comments.add(comment);
        _commentCtrl.clear();
        _replyingTo = null;
        if (_post != null) {
          _post = _post!.copyWith(commentCount: _post!.commentCount + 1);
        }
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not comment') : e.toString(),
        type: SnackType.error,
      );
    }
  }

  Future<void> _toggleCommentLike(PostComment c) async {
    final idx = _comments.indexWhere((x) => x.id == c.id);
    if (idx < 0) return;
    final wasLiked = c.isLikedByMe;
    setState(() {
      _comments[idx] = c.copyWith(
        isLikedByMe: !wasLiked,
        likeCount: wasLiked ? (c.likeCount - 1).clamp(0, 999999) : c.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await _service.unlikeComment(c.id);
      } else {
        await _service.likeComment(c.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _comments[idx] = c);
    }
  }

  Future<void> _deleteComment(PostComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
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
      await _service.deleteComment(c.id);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((x) => x.id == c.id);
        if (_post != null) {
          _post = _post!.copyWith(commentCount: (_post!.commentCount - 1).clamp(0, 999999));
        }
      });
    } catch (e) {
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Delete failed') : e.toString(), type: SnackType.error);
    }
  }

  Future<void> _report() async {
    if (_isOwnPost(_post)) {
      customSnackBar('Info', 'You can’t report your own post', type: SnackType.info);
      return;
    }
    final reason = await showReportReasonDialog(context, title: 'Report post');
    if (reason == null) return;
    try {
      await _service.reportPost(widget.postId, reason: reason.isEmpty ? null : reason);
      customSnackBar('Success', 'Thanks — we received your report', type: SnackType.success);
    } catch (e) {
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Report failed') : e.toString(), type: SnackType.error);
    }
  }

  Future<void> _onCommentLongPress(PostComment c, {required bool isMine}) async {
    if (isMine) {
      await _deleteComment(c);
      return;
    }
    final reason = await showReportReasonDialog(context, title: 'Report comment');
    if (reason == null) return;
    try {
      await _service.reportComment(c.id, reason: reason.isEmpty ? null : reason);
      customSnackBar('Success', 'Thanks — we received your report', type: SnackType.success);
    } catch (e) {
      customSnackBar('Error', e is ApiException ? (e.message ?? 'Report failed') : e.toString(), type: SnackType.error);
    }
  }

  List<Widget> _threadedCommentTiles(String? myId) {
    final byParent = <String, List<PostComment>>{};
    final roots = <PostComment>[];
    final seen = <String>{};

    for (final c in _comments) {
      final parentId = c.parentId?.trim() ?? '';
      if (parentId.isEmpty) {
        roots.add(c);
      } else {
        byParent.putIfAbsent(parentId, () => []).add(c);
      }
    }

    final tiles = <Widget>[];

    void walk(PostComment c, int depth) {
      if (seen.contains(c.id)) return;
      seen.add(c.id);
      tiles.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CommentTile(
            comment: c,
            depth: depth,
            onAuthorTap: () => openUserProfile(
              context,
              userId: c.user.id,
              fallbackName: c.user.fullName,
            ),
            onReply: () => setState(() => _replyingTo = c),
            onLike: () => _toggleCommentLike(c),
            onLongPress: () => _onCommentLongPress(
              c,
              isMine: myId != null && myId == c.user.id,
            ),
            isMine: myId != null && myId == c.user.id,
          ),
        ),
      );
      final children = byParent[c.id] ?? const <PostComment>[];
      for (final child in children) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    for (final c in _comments) {
      if (!seen.contains(c.id)) walk(c, 1);
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final myId = _myId ?? AuthService().getCachedProfile()?['id']?.toString();
    final isMine = _isOwnPost(post);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Post', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'report') _report();
              if (v == 'edit') _editPost();
              if (v == 'delete') _deletePost();
            },
            itemBuilder: (_) {
              if (isMine) {
                return const [
                  PopupMenuItem(value: 'edit', child: Text('Edit post')),
                  PopupMenuItem(value: 'delete', child: Text('Delete post')),
                ];
              }
              return const [
                PopupMenuItem(value: 'report', child: Text('Report post')),
              ];
            },
          ),
        ],
      ),
      body: _loading && post == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _contentUnavailable
              ? EmptyState(
                  title: 'Content not available',
                  subtitle: 'This post may have been deleted or is no longer available.',
                  primaryLabel: 'Go back',
                  onPrimary: () => Navigator.of(context).pop(),
                  icon: Icons.broken_image_outlined,
                )
              : _error != null && post == null
              ? EmptyState(
                  title: 'Couldn’t load post',
                  subtitle: _error!,
                  primaryLabel: 'Try again',
                  onPrimary: _load,
                  icon: Icons.error_outline,
                )
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _load,
                        child: ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 20),
                          children: [
                            if (post != null) ...[
                              // FB-style header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () => openUserProfile(
                                        context,
                                        userId: post.user.id,
                                        fallbackName: post.user.fullName,
                                      ),
                                      child: CircleAvatar(
                                        radius: 20,
                                        backgroundColor: AppColors.chipIdle,
                                        backgroundImage: _mediaUrl(post.user.profilePicture).isNotEmpty
                                            ? NetworkImage(_mediaUrl(post.user.profilePicture))
                                            : null,
                                        child: _mediaUrl(post.user.profilePicture).isEmpty
                                            ? Text(
                                                post.user.fullName.isNotEmpty
                                                    ? post.user.fullName[0].toUpperCase()
                                                    : '?',
                                                style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary),
                                              )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => openUserProfile(
                                          context,
                                          userId: post.user.id,
                                          fallbackName: post.user.fullName,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: post.user.fullName,
                                                    style: AppTextStyles.ui(
                                                      size: 15,
                                                      weight: FontWeight.w800,
                                                      color: AppColors.ink,
                                                    ),
                                                  ),
                                                  if ((post.sourcePostId ?? '').isNotEmpty)
                                                    TextSpan(
                                                      text: ' shared a post',
                                                      style: AppTextStyles.ui(
                                                        size: 15,
                                                        weight: FontWeight.w500,
                                                        color: AppColors.body,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              [
                                                _relativeTime(post.createdAt),
                                                if (post.circleName != null && post.circleName!.isNotEmpty)
                                                  post.circleName!,
                                                if (post.city != null && post.city!.isNotEmpty) post.city!,
                                              ].join(' · '),
                                              style: AppTextStyles.ui(size: 12, color: AppColors.body),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (() {
                                    var caption = post.content;
                                    final sourceContent = (post.sourcePost?.content ?? '').trim();
                                    final isShared = (post.sourcePostId ?? '').isNotEmpty;
                                    if (isShared && sourceContent.isNotEmpty) {
                                      final trimmed = caption.trim();
                                      if (trimmed == sourceContent) return false;
                                      if (trimmed.endsWith(sourceContent)) {
                                        caption = trimmed
                                            .substring(0, trimmed.length - sourceContent.length)
                                            .trim();
                                      }
                                    }
                                    return caption.isNotEmpty;
                                  }())
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                  child: Text(
                                    () {
                                      var caption = post.content;
                                      final sourceContent = (post.sourcePost?.content ?? '').trim();
                                      final isShared = (post.sourcePostId ?? '').isNotEmpty;
                                      if (isShared && sourceContent.isNotEmpty) {
                                        final trimmed = caption.trim();
                                        if (trimmed == sourceContent) return '';
                                        if (trimmed.endsWith(sourceContent)) {
                                          return trimmed
                                              .substring(0, trimmed.length - sourceContent.length)
                                              .trim();
                                        }
                                      }
                                      return caption;
                                    }(),
                                    style: AppTextStyles.ui(size: 15, height: 1.45),
                                  ),
                                ),
                              if ((post.sourcePostId ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PostDetailScreen(postId: post.sourcePostId!),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.mutedBorder),
                                        color: AppColors.surface,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Builder(
                                        builder: (context) {
                                          final source = post.sourcePost;
                                          final name = (source?.user.fullName ?? post.sourceAuthorName ?? '').trim();
                                          final avatar = _mediaUrl(source?.user.profilePicture);
                                          final content = (source?.content ?? '').trim();
                                          final mediaType = source?.mediaType ?? post.mediaType;
                                          final mediaUrl = _mediaUrl(
                                            (source?.mediaUrl ?? '').isNotEmpty ? source!.mediaUrl : post.mediaUrl,
                                          );
                                          final meta = <String>[
                                            if (source?.createdAt != null) _relativeTime(source!.createdAt!),
                                            if ((source?.circleName ?? '').isNotEmpty) source!.circleName!,
                                          ];
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 18,
                                                      backgroundColor: AppColors.chipIdle,
                                                      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                                      child: avatar.isEmpty
                                                          ? Text(
                                                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                              style: AppTextStyles.ui(
                                                                size: 14,
                                                                weight: FontWeight.w800,
                                                                color: AppColors.primary,
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            name.isNotEmpty ? name : 'Original post',
                                                            style: AppTextStyles.ui(size: 14, weight: FontWeight.w800),
                                                          ),
                                                          if (meta.isNotEmpty)
                                                            Text(
                                                              meta.join(' · '),
                                                              style: AppTextStyles.ui(size: 12, color: AppColors.body),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (content.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                                  child: Text(
                                                    content,
                                                    style: AppTextStyles.ui(size: 14, height: 1.4),
                                                  ),
                                                ),
                                              if (mediaUrl.isNotEmpty && mediaType == 'image')
                                                AspectRatio(
                                                  aspectRatio: 16 / 9,
                                                  child: Image.network(mediaUrl, fit: BoxFit.cover, width: double.infinity),
                                                ),
                                              if (mediaUrl.isNotEmpty && mediaType == 'video')
                                                PostVideoPlayer(videoUrl: mediaUrl),
                                              if (content.isEmpty && mediaUrl.isEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                                  child: Text(
                                                    'Tap to open the original post',
                                                    style: AppTextStyles.ui(size: 13, color: AppColors.body),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              if ((post.sourcePostId ?? '').isEmpty &&
                                  _mediaUrl(post.mediaUrl).isNotEmpty &&
                                  post.mediaType == 'image')
                                GestureDetector(
                                  onTap: () => openFullscreenImage(context, _mediaUrl(post.mediaUrl)),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Image.network(
                                      _mediaUrl(post.mediaUrl),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                                  ),
                                ),
                              if ((post.sourcePostId ?? '').isEmpty &&
                                  _mediaUrl(post.mediaUrl).isNotEmpty &&
                                  post.mediaType == 'video')
                                PostVideoPlayer(videoUrl: _mediaUrl(post.mediaUrl)),
                              if (post.likeCount > 0 || post.commentCount > 0)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                                  child: Row(
                                    children: [
                                      if (post.likeCount > 0) ...[
                                        Container(
                                          width: 18,
                                          height: 18,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: AppColors.brandGradient,
                                          ),
                                          child: const Icon(Icons.favorite, size: 10, color: Colors.white),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${post.likeCount}',
                                          style: AppTextStyles.ui(size: 13, color: AppColors.body),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (post.commentCount > 0)
                                        Text(
                                          post.commentCount == 1
                                              ? '1 comment'
                                              : '${post.commentCount} comments',
                                          style: AppTextStyles.ui(size: 13, color: AppColors.body),
                                        ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: AppColors.mutedBorder.withOpacity(0.85),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: _toggleLike,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                post.isLikedByMe
                                                    ? Icons.favorite_rounded
                                                    : Icons.favorite_border_rounded,
                                                size: 20,
                                                color: post.isLikedByMe ? AppColors.primary : AppColors.body,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Like',
                                                style: AppTextStyles.ui(
                                                  size: 13,
                                                  weight: FontWeight.w700,
                                                  color: post.isLikedByMe ? AppColors.primary : AppColors.body,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => _commentFocus.requestFocus(),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.chat_bubble_outline_rounded,
                                                  size: 20, color: AppColors.body),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Comment',
                                                style: AppTextStyles.ui(
                                                  size: 13,
                                                  weight: FontWeight.w700,
                                                  color: AppColors.body,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => showSharePostSheet(context, post),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.share_outlined, size: 20, color: AppColors.body),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Share',
                                                style: AppTextStyles.ui(
                                                  size: 13,
                                                  weight: FontWeight.w700,
                                                  color: AppColors.body,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: AppColors.mutedBorder),
                            ],
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                              child: Row(
                                children: [
                                  Text('Comments', style: AppTextStyles.sectionTitle),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.chipIdle,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_comments.length}',
                                      style: AppTextStyles.ui(size: 12, weight: FontWeight.w800, color: AppColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_loadingComments)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                              )
                            else if (_comments.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: AppColors.mutedBorder),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.forum_outlined, size: 36, color: AppColors.primary.withOpacity(0.7)),
                                      const SizedBox(height: 10),
                                      Text('No comments yet', style: AppTextStyles.ui(size: 15, weight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Text('Be the first to share a thought', style: AppTextStyles.body, textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ..._threadedCommentTiles(myId),
                          ],
                        ),
                      ),
                    ),
                    _ComposerBar(
                      controller: _commentCtrl,
                      focusNode: _commentFocus,
                      sending: _sending,
                      replyingTo: _replyingTo,
                      onCancelReply: () => setState(() => _replyingTo = null),
                      onSend: _sendComment,
                    ),
                  ],
                ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool sending;
  final VoidCallback onSend;
  final PostComment? replyingTo;
  final VoidCallback? onCancelReply;

  const _ComposerBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.focusNode,
    this.replyingTo,
    this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: const Border(top: BorderSide(color: AppColors.mutedBorder)),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to ${replyingTo!.user.fullName}',
                        style: AppTextStyles.ui(size: 12, weight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelReply,
                      icon: const Icon(Icons.close, size: 18, color: AppColors.body),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    style: AppTextStyles.ui(size: 15),
                    decoration: InputDecoration(
                      hintText: replyingTo != null ? 'Write a reply…' : 'Add a comment…',
                      hintStyle: AppTextStyles.ui(size: 15, color: AppColors.body.withOpacity(0.7)),
                      filled: true,
                      fillColor: AppColors.chipIdle,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: sending ? null : onSend,
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                      ),
                      child: sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
