import 'package:flutter/material.dart';

import '../models/circle.dart';
import '../models/post.dart';
import '../network/api_client.dart' show ApiException;
import '../services/circle_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_caches.dart';
import '../utils/circle_cover.dart';
import '../utils/custom_snackbar.dart';

/// Share a post to another joined circle (in-app only).
Future<bool> showSharePostSheet(BuildContext context, Post post) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SharePostSheet(post: post),
  );
  return result == true;
}

class _SharePostSheet extends StatefulWidget {
  final Post post;

  const _SharePostSheet({required this.post});

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  final _commentCtrl = TextEditingController();
  final _circleService = CircleService();
  final _postService = PostService();

  List<Circle> _circles = [];
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  String? _selectedCircleId;

  @override
  void initState() {
    super.initState();
    _loadCircles();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCircles() async {
    try {
      final all = await _circleService.getCircles();
      if (!mounted) return;
      final joined = all
          .where((c) => c.isJoined && c.id != widget.post.circleId)
          .toList();
      setState(() {
        _circles = joined;
        _loading = false;
        _error = joined.isEmpty ? 'Join another circle to share posts there.' : null;
        if (joined.length == 1) _selectedCircleId = joined.first.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? (e.message ?? 'Could not load circles') : e.toString();
      });
    }
  }

  Circle? get _selected {
    final id = _selectedCircleId;
    if (id == null) return null;
    for (final c in _circles) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _share() async {
    final circle = _selected;
    if (circle == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await _postService.sharePost(
        widget.post.id,
        circleId: circle.id,
        comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      );
      AppCaches.invalidateAfterPost();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      customSnackBar(
        'Shared',
        'Post shared to ${circle.name}',
        type: SnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      customSnackBar(
        'Error',
        e is ApiException ? (e.message ?? 'Could not share post') : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final selected = _selected;
    final canShare = selected != null && !_sharing && !_loading && _error == null;
    final maxH = MediaQuery.sizeOf(context).height * 0.82;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCCD0D5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _sharing ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, color: AppColors.ink),
                  ),
                  Expanded(
                    child: Text(
                      'Share post',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.ui(size: 17, weight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: canShare ? _share : null,
                    style: TextButton.styleFrom(
                      backgroundColor: canShare ? AppColors.primary : AppColors.chipIdle,
                      foregroundColor: canShare ? Colors.white : AppColors.body,
                      disabledForegroundColor: AppColors.body,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Share',
                            style: AppTextStyles.ui(
                              size: 14,
                              weight: FontWeight.w800,
                              color: canShare ? Colors.white : AppColors.body,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE4E6EB)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add a note (optional)',
                      style: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.body),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentCtrl,
                      maxLines: 3,
                      minLines: 2,
                      maxLength: 500,
                      onChanged: (_) => setState(() {}),
                      style: AppTextStyles.ui(size: 15, height: 1.35),
                      decoration: InputDecoration(
                        hintText: 'Say something about this…',
                        hintStyle: AppTextStyles.ui(size: 15, color: AppColors.body.withOpacity(0.45)),
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE4E6EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE4E6EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Share to',
                      style: AppTextStyles.ui(size: 13, weight: FontWeight.w700, color: AppColors.body),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      )
                    else if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.chipIdle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.body,
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._circles.map((circle) {
                        final selectedId = _selectedCircleId == circle.id;
                        final cover = CircleCover.resolve(
                          iconUrl: circle.iconUrl,
                          slug: circle.slug,
                          name: circle.name,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: selectedId ? AppColors.primary.withOpacity(0.06) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: _sharing
                                  ? null
                                  : () => setState(() => _selectedCircleId = circle.id),
                              borderRadius: BorderRadius.circular(14),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selectedId ? AppColors.primary : const Color(0xFFE4E6EB),
                                    width: selectedId ? 1.6 : 1,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        cover,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 44,
                                          height: 44,
                                          color: AppColors.chipIdle,
                                          child: const Icon(Icons.groups_rounded, color: AppColors.primary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            circle.name,
                                            style: AppTextStyles.ui(size: 15, weight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${circle.memberCount} members · Circle',
                                            style: AppTextStyles.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      selectedId ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: selectedId ? AppColors.primary : AppColors.body.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    if (selected != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Will share to ${selected.name}',
                        style: AppTextStyles.ui(size: 12, color: AppColors.body),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
