import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/comment.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class CommentTile extends StatelessWidget {
  final PostComment comment;
  final VoidCallback? onLongPress;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final bool isMine;
  final String? parentPreview;
  final int depth;

  const CommentTile({
    super.key,
    required this.comment,
    this.onLongPress,
    this.onAuthorTap,
    this.onReply,
    this.onLike,
    this.isMine = false,
    this.parentPreview,
    this.depth = 0,
  });

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
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _mediaUrl(comment.user.profilePicture);
    final isReply = depth > 0 || (comment.parentId != null && comment.parentId!.isNotEmpty);
    final indent = (depth > 0 ? depth : (isReply ? 1 : 0)) * 22.0;
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: indent),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.mutedBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isReply) ...[
                    Container(
                      width: 3,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: onAuthorTap,
                          child: CircleAvatar(
                            radius: isReply ? 16 : 20,
                            backgroundColor: AppColors.chipIdle,
                            backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    comment.user.fullName.isNotEmpty ? comment.user.fullName[0].toUpperCase() : '?',
                                    style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.primary, size: 14),
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
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: onAuthorTap,
                                      child: Text(
                                        comment.user.fullName,
                                        style: AppTextStyles.ui(size: 14, weight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _timeAgo(comment.createdAt),
                                    style: AppTextStyles.ui(size: 11, color: const Color(0xFF8A8184)),
                                  ),
                                ],
                              ),
                              if (!isReply && parentPreview != null && parentPreview!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Replying to: $parentPreview',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.ui(size: 12, color: AppColors.body),
                                ),
                              ],
                              if (isReply) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Reply',
                                  style: AppTextStyles.ui(size: 11, weight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                comment.content,
                                style: AppTextStyles.ui(size: 14, height: 1.45, color: AppColors.ink),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: onLike,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            comment.isLikedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                            size: 16,
                                            color: comment.isLikedByMe ? AppColors.primary : AppColors.body,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${comment.likeCount}',
                                            style: AppTextStyles.ui(size: 12, weight: FontWeight.w600, color: AppColors.body),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: onReply,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      child: Text(
                                        'Reply',
                                        style: AppTextStyles.ui(size: 12, weight: FontWeight.w700, color: AppColors.primary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
