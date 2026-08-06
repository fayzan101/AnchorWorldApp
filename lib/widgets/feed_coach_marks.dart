import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// First-run coach tips on Feed (SharedPreferences-gated).
class FeedCoachMarks extends StatefulWidget {
  final VoidCallback? onOpenCircles;
  final VoidCallback? onOpenPoints;

  const FeedCoachMarks({super.key, this.onOpenCircles, this.onOpenPoints});

  @override
  State<FeedCoachMarks> createState() => _FeedCoachMarksState();
}

class _FeedCoachMarksState extends State<FeedCoachMarks> {
  static const _prefKey = 'feed_coach_marks_seen_v1';
  int _step = 0;
  bool _visible = false;

  static const _tips = [
    (
      'Join circles',
      'Circles are topic communities. Join a few so your feed fills with conversations you care about.',
      Icons.workspaces_rounded,
    ),
    (
      'Earn points',
      'Posting, connecting, and daily activity earn Anchor Points that unlock discounts on Premium.',
      Icons.auto_awesome,
    ),
    (
      'Premium unlocks video',
      'Subscribe to Premium for video calls. Higher points = bigger subscription discount.',
      Icons.videocam_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _maybeShow();
  }

  Future<void> _maybeShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _visible = true);
    } catch (_) {}
  }

  Future<void> _finish() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }

  void _next() {
    if (_step >= _tips.length - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final tip = _tips[_step];
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.55),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: Container(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(0.12),
                            ),
                            child: Icon(tip.$3, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tip.$1,
                              style: AppTextStyles.ui(size: 18, weight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${_step + 1}/${_tips.length}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(tip.$2, style: AppTextStyles.body),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _finish,
                            child: Text('Skip', style: AppTextStyles.ui(weight: FontWeight.w600, color: AppColors.body)),
                          ),
                          const Spacer(),
                          if (_step == 0 && widget.onOpenCircles != null)
                            TextButton(
                              onPressed: () {
                                _finish();
                                widget.onOpenCircles!();
                              },
                              child: Text('Open Circles', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary)),
                            ),
                          if (_step == 1 && widget.onOpenPoints != null)
                            TextButton(
                              onPressed: () {
                                _finish();
                                widget.onOpenPoints!();
                              },
                              child: Text('Points', style: AppTextStyles.ui(weight: FontWeight.w700, color: AppColors.primary)),
                            ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _next,
                            child: Text(_step >= _tips.length - 1 ? 'Got it' : 'Next'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
