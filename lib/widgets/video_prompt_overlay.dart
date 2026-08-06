import 'dart:async';

import 'package:flutter/material.dart';

import '../data/video_prompts.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Glass-style rotating community prompt strip for active calls.
class VideoPromptOverlay extends StatefulWidget {
  final Duration rotateEvery;

  const VideoPromptOverlay({
    super.key,
    this.rotateEvery = const Duration(seconds: 45),
  });

  @override
  State<VideoPromptOverlay> createState() => _VideoPromptOverlayState();
}

class _VideoPromptOverlayState extends State<VideoPromptOverlay> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.rotateEvery, (_) {
      if (!mounted) return;
      setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = VideoPrompts.atIndex(_index);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      child: Container(
        key: ValueKey(_index),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Conversation spark',
              style: AppTextStyles.ui(size: 11, weight: FontWeight.w700, color: AppColors.accentGold),
            ),
            const SizedBox(height: 6),
            Text(
              prompt,
              style: AppTextStyles.ui(size: 15, weight: FontWeight.w600, color: AppColors.white, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
