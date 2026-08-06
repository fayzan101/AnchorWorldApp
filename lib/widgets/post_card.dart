import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'fullscreen_image.dart';
import 'post_video_player.dart';
import 'share_post_sheet.dart';

/// Facebook-style feed post card — keeps existing like / comment / share / edit / report.
class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onCommentTap;
  final VoidCallback? onCircleTap;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onOpenSourcePost;
  final bool isOwnPost;
  final int? staggerIndex;

  const PostCard({
    super.key,
    required this.post,
    this.onLikeToggle,
    this.onCommentTap,
    this.onCircleTap,
    this.onAuthorTap,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onOpenSourcePost,
    this.isOwnPost = false,
    this.staggerIndex,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late AnimationController _heartCtrl;
  bool _visible = false;
  bool _expandedCaption = false;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      lowerBound: 0.85,
      upperBound: 1.2,
      value: 1.0,
    );
    final hasMedia = (widget.post.mediaUrl ?? '').isNotEmpty &&
        (widget.post.mediaType == 'image' || widget.post.mediaType == 'video');
    if (hasMedia || widget.staggerIndex == null) {
      _visible = true;
    } else {
      final delay = (widget.staggerIndex ?? 0) * 40;
      Future.delayed(Duration(milliseconds: delay.clamp(0, 200)), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  String _mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    if (path.startsWith('/')) return '$base$path';
    return '$base/$path';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  bool get _hasOverflowMenu =>
      (widget.isOwnPost && (widget.onEdit != null || widget.onDelete != null)) ||
      (!widget.isOwnPost && widget.onReport != null);

  void _onLike() {
    HapticFeedback.lightImpact();
    _heartCtrl.forward(from: 0.85).then((_) => _heartCtrl.reverse());
    widget.onLikeToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final avatarUrl = _mediaUrl(post.user.profilePicture);
    final mediaUrl = _mediaUrl(post.mediaUrl);
    final isShared = (post.sourcePostId ?? '').isNotEmpty;
    final showStats = post.likeCount > 0 || post.commentCount > 0;

    // Sharer note only — strip duplicated original text from older merged shares.
    var caption = post.content;
    final sourceContent = (post.sourcePost?.content ?? '').trim();
    if (isShared && sourceContent.isNotEmpty) {
      final trimmed = caption.trim();
      if (trimmed == sourceContent) {
        caption = '';
      } else if (trimmed.endsWith(sourceContent)) {
        caption = trimmed.substring(0, trimmed.length - sourceContent.length).trim();
        if (caption.endsWith('\n\n')) caption = caption.trim();
      }
    }

    final metaParts = <String>[
      _timeAgo(post.createdAt),
      if (post.circleName != null && post.circleName!.isNotEmpty) post.circleName!,
      if (post.city != null && post.city!.isNotEmpty) post.city!,
    ];

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(
              bottom: BorderSide(color: AppColors.mutedBorder.withOpacity(0.9)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (FB: avatar · name · meta · overflow) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: widget.onAuthorTap,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.chipIdle,
                        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                post.user.fullName.isNotEmpty ? post.user.fullName[0].toUpperCase() : '?',
                                style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: widget.onAuthorTap,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: post.user.fullName,
                                    style: AppTextStyles.ui(size: 15, weight: FontWeight.w800, color: AppColors.ink),
                                  ),
                                  if (isShared) ...[
                                    TextSpan(
                                      text: ' shared a post',
                                      style: AppTextStyles.ui(size: 15, weight: FontWeight.w500, color: AppColors.body),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: post.circleName != null ? widget.onCircleTap : null,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    metaParts.join(' · '),
                                    style: AppTextStyles.ui(size: 12, color: AppColors.body),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.public, size: 12, color: AppColors.body.withOpacity(0.85)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_hasOverflowMenu)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        offset: const Offset(0, 40),
                        position: PopupMenuPosition.under,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        color: AppColors.card,
                        elevation: 8,
                        padding: EdgeInsets.zero,
                        icon: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.chipIdle,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.more_horiz, color: AppColors.ink, size: 22),
                        ),
                        onSelected: (v) {
                          if (v == 'edit') widget.onEdit?.call();
                          if (v == 'delete') widget.onDelete?.call();
                          if (v == 'report') widget.onReport?.call();
                        },
                        itemBuilder: (_) {
                          if (widget.isOwnPost) {
                            return [
                              if (widget.onEdit != null)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_outlined, size: 20, color: AppColors.body),
                                      const SizedBox(width: 12),
                                      Text('Edit post', style: AppTextStyles.ui(weight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              if (widget.onDelete != null)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                                      const SizedBox(width: 12),
                                      Text('Delete post', style: AppTextStyles.ui(weight: FontWeight.w600, color: AppColors.danger)),
                                    ],
                                  ),
                                ),
                            ];
                          }
                          return [
                            PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  const Icon(Icons.flag_outlined, size: 20, color: AppColors.body),
                                  const SizedBox(width: 12),
                                  Text('Report post', style: AppTextStyles.ui(weight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                  ],
                ),
              ),

              // ── Caption (sharer note when shared) ──
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _ExpandableCaption(
                    text: caption,
                    expanded: _expandedCaption,
                    onToggle: () => setState(() => _expandedCaption = !_expandedCaption),
                  ),
                ),

              // ── Shared original (nested FB-style post card) ──
              if (isShared)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _SharedPostPreview(
                    post: post,
                    mediaUrlResolver: _mediaUrl,
                    timeAgo: _timeAgo,
                    onTap: widget.onOpenSourcePost,
                  ),
                ),

              // ── Media (edge-to-edge) — skip on shared; media lives in nested original ──
              if (!isShared && mediaUrl.isNotEmpty && post.mediaType == 'image')
                GestureDetector(
                  onTap: () => openFullscreenImage(context, mediaUrl),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      mediaUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      cacheWidth: (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(320, 1600),
                      frameBuilder: (context, child, frame, wasSync) {
                        if (wasSync || frame != null) return child;
                        return Container(color: AppColors.chipIdle);
                      },
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppColors.chipIdle,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary.withOpacity(0.5),
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.chipIdle,
                        child: const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.body)),
                      ),
                    ),
                  ),
                ),
              if (!isShared && mediaUrl.isNotEmpty && post.mediaType == 'video')
                PostVideoPlayer(videoUrl: mediaUrl),

              // ── Reaction / comment summary ──
              if (showStats)
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
                        GestureDetector(
                          onTap: widget.onCommentTap,
                          child: Text(
                            post.commentCount == 1 ? '1 comment' : '${post.commentCount} comments',
                            style: AppTextStyles.ui(size: 13, color: AppColors.body),
                          ),
                        ),
                    ],
                  ),
                ),

              // ── Divider + Like / Comment / Share ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Divider(height: 1, thickness: 1, color: AppColors.mutedBorder.withOpacity(0.85)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: ScaleTransition(
                        scale: _heartCtrl,
                        child: _ActionButton(
                          icon: post.isLikedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          label: 'Like',
                          active: post.isLikedByMe,
                          onTap: _onLike,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Comment',
                        onTap: widget.onCommentTap,
                      ),
                    ),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: () => showSharePostSheet(context, post),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableCaption extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _ExpandableCaption({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  static const _collapseAt = 180;

  @override
  Widget build(BuildContext context) {
    final needsExpand = text.length > _collapseAt;
    final display = !needsExpand || expanded ? text : '${text.substring(0, _collapseAt).trimRight()}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(display, style: AppTextStyles.ui(size: 15, height: 1.4, color: AppColors.ink)),
        if (needsExpand)
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                expanded ? 'See less' : 'See more',
                style: AppTextStyles.ui(size: 14, weight: FontWeight.w700, color: AppColors.body),
              ),
            ),
          ),
      ],
    );
  }
}

class _SharedPostPreview extends StatelessWidget {
  final Post post;
  final String Function(String?) mediaUrlResolver;
  final String Function(DateTime) timeAgo;
  final VoidCallback? onTap;

  const _SharedPostPreview({
    required this.post,
    required this.mediaUrlResolver,
    required this.timeAgo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final source = post.sourcePost;
    final name = (source?.user.fullName ?? post.sourceAuthorName ?? '').trim();
    final avatarUrl = mediaUrlResolver(source?.user.profilePicture);
    final content = (source?.content ?? '').trim();
    // Older shares copied media onto the share row — fall back so nested still looks like the original.
    final mediaType = (source?.mediaType ?? post.mediaType);
    final mediaUrl = mediaUrlResolver(
      (source?.mediaUrl ?? '').isNotEmpty ? source!.mediaUrl : post.mediaUrl,
    );
    final metaParts = <String>[
      if (source?.createdAt != null) timeAgo(source!.createdAt!),
      if ((source?.circleName ?? '').isNotEmpty) source!.circleName!,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.mutedBorder),
            color: AppColors.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.chipIdle,
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: AppTextStyles.ui(size: 14, weight: FontWeight.w800, color: AppColors.primary),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              metaParts.join(' · '),
                              style: AppTextStyles.ui(size: 12, color: AppColors.body),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
                    style: AppTextStyles.ui(size: 14, height: 1.4, color: AppColors.ink),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (mediaUrl.isNotEmpty && mediaType == 'image')
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    mediaUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.chipIdle,
                      child: const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.body)),
                    ),
                  ),
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
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.ui(
                size: 13,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
