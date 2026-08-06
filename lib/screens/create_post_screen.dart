import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/circle.dart';
import '../models/post.dart';
import '../network/api_client.dart' show ApiException;
import '../services/auth_service.dart';
import '../services/circle_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/custom_snackbar.dart';
import '../utils/points_toast.dart';
import '../utils/app_caches.dart';
import 'circles_screen.dart';

class CreatePostScreen extends StatefulWidget {
  final String? initialCircleId;
  /// When set, screen edits an existing post instead of creating.
  final Post? editPost;
  /// Called after a successful post (e.g. switch home tab to Feed).
  final VoidCallback? onPosted;
  /// Called when user cancels / taps close while embedded in a tab.
  final VoidCallback? onClose;
  /// Bump when Create tab is opened so joined circles reload without wiping draft.
  final int circlesRefreshToken;

  const CreatePostScreen({
    super.key,
    this.initialCircleId,
    this.editPost,
    this.onPosted,
    this.onClose,
    this.circlesRefreshToken = 0,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxCaptionChars = 5000;

  final _contentCtrl = TextEditingController();
  final _postService = PostService();
  final _circleService = CircleService();
  final _focus = FocusNode();

  List<Circle> _joined = [];
  String? _circleId;
  File? _media;
  bool _mediaIsVideo = false;
  bool _loadingCircles = true;
  bool _submitting = false;
  bool get _isEditing => widget.editPost != null;

  String _displayName = 'You';
  String _avatarUrl = '';

  @override
  void initState() {
    super.initState();
    final edit = widget.editPost;
    if (edit != null) {
      _contentCtrl.text = edit.content;
      final cid = (edit.circleId ?? '').trim();
      _circleId = cid.isEmpty ? null : cid;
    } else {
      _circleId = widget.initialCircleId;
    }
    _contentCtrl.addListener(() => setState(() {}));
    _loadMe();
    _loadCircles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isEditing) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant CreatePostScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.circlesRefreshToken != oldWidget.circlesRefreshToken) {
      _loadCircles();
    }
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _loadMe() {
    final apply = (Map<String, dynamic> cached) {
      final name = (cached['full_name'] ?? cached['name'] ?? cached['first_name'] ?? 'You').toString();
      final pic = (cached['profile_picture'] ??
              cached['profile_picture_url'] ??
              cached['imageUrl'] ??
              cached['picture'] ??
              cached['avatar'] ??
              '')
          .toString();
      if (!mounted) return;
      setState(() {
        _displayName = name.isEmpty ? 'You' : name;
        _avatarUrl = _resolveUrl(pic);
      });
    };

    final cached = AuthService().getCachedProfile();
    if (cached != null) apply(cached);

    AuthService().getProfile().then((data) {
      if (!mounted) return;
      apply(data);
    }).catchError((_) {});
  }

  String _resolveUrl(String? path) {
    if (path == null || path.isEmpty || path == 'null') return '';
    final r = path.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    if (r.contains('/uploads/')) {
      final m = RegExp(r'/uploads/(.+)').firstMatch(r);
      final filename = (m != null && m.groupCount >= 1) ? m.group(1)! : r.split('/').last;
      return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/$filename';
    }
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    if (r.startsWith('/')) return '$base$r';
    return '${ApiConfig.profilePicture.replaceAll(RegExp(r'/$'), '')}/${r.split('/').last}';
  }

  Future<void> _loadCircles() async {
    if (!mounted) return;
    setState(() => _loadingCircles = true);
    try {
      CirclesScreen.clearCache();
      final all = await _circleService.getCircles();
      if (!mounted) return;
      final joined = all.where((c) => c.isJoined).toList();
      setState(() {
        _joined = joined;
        _loadingCircles = false;
        if (_circleId != null && !joined.any((c) => c.id == _circleId)) {
          _circleId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCircles = false);
    }
  }

  void _resetForm() {
    _contentCtrl.clear();
    setState(() {
      _media = null;
      _mediaIsVideo = false;
      final initial = widget.initialCircleId;
      if (initial != null && _joined.any((c) => c.id == initial)) {
        _circleId = initial;
      } else {
        _circleId = null;
      }
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _handleClose() {
    _dismissKeyboard();
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (widget.onClose != null) {
        widget.onClose!();
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
      widget.onPosted?.call();
    });
  }

  Future<void> _pickPhoto() async {
    _dismissKeyboard();
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920);
    if (file == null) return;
    final length = await File(file.path).length();
    if (length > 5 * 1024 * 1024) {
      customSnackBar('Image too large', 'Max size is 5 MB.', type: SnackType.error);
      return;
    }
    setState(() {
      _media = File(file.path);
      _mediaIsVideo = false;
    });
  }

  Future<void> _pickVideo() async {
    _dismissKeyboard();
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final length = await File(file.path).length();
    if (length > 20 * 1024 * 1024) {
      customSnackBar('Video too large', 'Max size is 20 MB.', type: SnackType.error);
      return;
    }
    setState(() {
      _media = File(file.path);
      _mediaIsVideo = true;
    });
  }

  bool get _canPost {
    final text = _contentCtrl.text.trim();
    if (text.length > _maxCaptionChars) return false;
    final hasText = text.isNotEmpty;
    final hasMedia = _media != null;
    final hasExistingMedia = _isEditing &&
        (widget.editPost!.mediaUrl ?? '').isNotEmpty &&
        widget.editPost!.mediaType != 'none';
    return (hasText || hasMedia || hasExistingMedia) && !_submitting;
  }

  String get _audienceLabel {
    if (_circleId == null) return 'Personal feed';
    final match = _joined.where((c) => c.id == _circleId);
    if (match.isEmpty) return 'Circle';
    return match.first.name;
  }

  Future<void> _pickAudience() async {
    _dismissKeyboard();
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.mutedBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Post to', style: AppTextStyles.ui(size: 18, weight: FontWeight.w800)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                title: Text('Personal feed', style: AppTextStyles.ui(weight: FontWeight.w700)),
                subtitle: Text('Only on your profile', style: AppTextStyles.caption),
                trailing: _circleId == null
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              if (_loadingCircles)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else
                ..._joined.map(
                  (c) => ListTile(
                    leading: const Icon(Icons.workspaces_outlined, color: AppColors.primary),
                    title: Text(c.name, style: AppTextStyles.ui(weight: FontWeight.w700)),
                    subtitle: Text('Circle', style: AppTextStyles.caption),
                    trailing: _circleId == c.id
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    setState(() => _circleId = selected.isEmpty ? null : selected);
  }

  Future<void> _submit() async {
    _dismissKeyboard();
    final text = _contentCtrl.text.trim();
    if (text.length > _maxCaptionChars) {
      customSnackBar('Caption too long', 'Keep under $_maxCaptionChars characters.', type: SnackType.error);
      return;
    }
    final hasExistingMedia = _isEditing &&
        (widget.editPost!.mediaUrl ?? '').isNotEmpty &&
        widget.editPost!.mediaType != 'none';
    if (text.isEmpty && _media == null && !hasExistingMedia) {
      customSnackBar('Almost there', 'Write something or add media', type: SnackType.info);
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_isEditing) {
        final edit = widget.editPost!;
        final hadCircle = (edit.circleId ?? '').trim().isNotEmpty;
        final updated = await _postService.updatePost(
          id: edit.id,
          content: text,
          circleId: _circleId,
          clearCircle: _circleId == null && hadCircle,
          media: _media,
        );
        customSnackBar('Success', 'Post updated', type: SnackType.success);
        AppCaches.invalidateAfterPost();
        widget.onPosted?.call();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(updated);
        }
      } else {
        final result = await _postService.createPost(
          content: text,
          circleId: _circleId,
          media: _media,
        );
        final awarded = result['points_awarded'];
        if (awarded is int && awarded > 0) {
          showPointsToast(awarded, reason: 'Nice post!');
        } else {
          customSnackBar('Success', 'Post shared with your community', type: SnackType.success);
        }
        if (mounted) _resetForm();
        AppCaches.invalidateAfterPost();
        widget.onPosted?.call();
        if (widget.onClose != null) return;
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      customSnackBar(
        'Error',
        e is ApiException
            ? (e.message ?? (_isEditing ? 'Could not update post' : 'Could not create post'))
            : e.toString(),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _contentCtrl.text.characters.length;
    final overLimit = charCount > _maxCaptionChars;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final navClearance = widget.onClose != null ? 96.0 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.card,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: AppColors.ink,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleClose,
        ),
        title: Text(
          _isEditing ? 'Edit post' : 'Create post',
          style: AppTextStyles.ui(size: 18, weight: FontWeight.w800),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: TextButton(
              onPressed: _canPost ? _submit : null,
              style: TextButton.styleFrom(
                backgroundColor: _canPost ? AppColors.primary : AppColors.chipIdle,
                foregroundColor: _canPost ? Colors.white : AppColors.body,
                disabledForegroundColor: AppColors.body,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isEditing ? 'Save' : 'Post',
                      style: AppTextStyles.ui(
                        size: 14,
                        weight: FontWeight.w800,
                        color: _canPost ? AppColors.white : AppColors.body,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomInset + navClearance),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.chipIdle,
                backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                child: _avatarUrl.isEmpty
                    ? Text(
                        _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
                        style: AppTextStyles.ui(weight: FontWeight.w800, color: AppColors.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName, style: AppTextStyles.ui(size: 16, weight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickAudience,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.chipIdle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.mutedBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _circleId == null ? Icons.person_outline : Icons.workspaces_outlined,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _audienceLabel,
                                style: AppTextStyles.ui(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: AppColors.primaryDeep,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 200),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4E6EB)),
            ),
            child: TextField(
              controller: _contentCtrl,
              focusNode: _focus,
              maxLines: null,
              minLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: AppColors.primary,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxCaptionChars),
              ],
              style: AppTextStyles.ui(size: 17, height: 1.45, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: AppTextStyles.ui(size: 17, color: AppColors.body.withOpacity(0.45)),
                filled: true,
                fillColor: Colors.white,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                counterText: '',
              ),
            ),
          ),
          if (charCount > _maxCaptionChars - 200 || overLimit)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$charCount / $_maxCaptionChars',
                  style: AppTextStyles.ui(
                    size: 12,
                    color: overLimit ? AppColors.danger : AppColors.body,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.mutedBorder),
              color: AppColors.card,
            ),
            child: Row(
              children: [
                _ToolbarAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Photo',
                  color: const Color(0xFF45BD62),
                  onTap: _pickPhoto,
                ),
                Container(width: 1, height: 28, color: AppColors.mutedBorder),
                _ToolbarAction(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  color: AppColors.primary,
                  onTap: _pickVideo,
                ),
              ],
            ),
          ),
          if (_media != null) ...[
            const SizedBox(height: 14),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _mediaIsVideo
                        ? Container(
                            color: AppColors.ink.withOpacity(0.88),
                            child: const Center(
                              child: Icon(Icons.play_circle_outline, color: Colors.white, size: 56),
                            ),
                          )
                        : Image.file(_media!, fit: BoxFit.cover, width: double.infinity),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() {
                        _media = null;
                        _mediaIsVideo = false;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.ui(size: 13, weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
