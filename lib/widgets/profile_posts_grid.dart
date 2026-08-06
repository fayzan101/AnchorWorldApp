import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../screens/post_detail_screen.dart';

/// 3-col media grid of a user's posts (Instagram-style tight grid).
class ProfilePostsGrid extends StatefulWidget {
  final String userId;

  const ProfilePostsGrid({super.key, required this.userId});

  @override
  State<ProfilePostsGrid> createState() => _ProfilePostsGridState();
}

class _ProfilePostsGridState extends State<ProfilePostsGrid> {
  final _service = PostService();
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _service.getUserPosts(widget.userId, limit: 30);
      if (!mounted) return;
      setState(() {
        _posts = result.items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    if (path.startsWith('/')) return '$base$path';
    return '$base/$path';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Text('Posts', style: AppTextStyles.sectionTitle),
        ),
        if (_posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No posts yet', style: AppTextStyles.body),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Parent ListView pads 16px; SizedBox alone is still max-width constrained,
              // which left a gap on the right. OverflowBox unlocks true edge-to-edge.
              final screenW = MediaQuery.sizeOf(context).width;
              final bleed = ((screenW - constraints.maxWidth) / 2).clamp(0.0, 64.0);
              return Transform.translate(
                offset: Offset(-bleed, 0),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: screenW,
                  maxWidth: screenW,
                  child: SizedBox(
                    width: screenW,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _posts.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 1,
                        crossAxisSpacing: 1,
                      ),
                      itemBuilder: (context, i) {
                        final post = _posts[i];
                        final url = _mediaUrl(post.mediaUrl);
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
                              ),
                            );
                          },
                          child: Container(
                            color: AppColors.chipIdle,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (url.isNotEmpty && post.mediaType == 'image')
                                  Image.network(url, fit: BoxFit.cover)
                                else if (url.isNotEmpty && post.mediaType == 'video')
                                  Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                                        return const ColoredBox(
                                          color: AppColors.chipIdle,
                                          child: Icon(Icons.play_circle_outline, color: AppColors.primary),
                                        );
                                      }),
                                      const Align(
                                        alignment: Alignment.topRight,
                                        child: Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Text(
                                        post.content,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.ui(size: 11),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                if ((post.sourcePostId ?? '').isNotEmpty)
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      margin: const EdgeInsets.all(5),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.share_outlined, size: 12, color: Colors.white),
                                          SizedBox(width: 3),
                                          Text(
                                            'Shared',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
