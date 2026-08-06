import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

/// Only one feed/detail video may decode at a time.
class _ActivePostVideo {
  static _PostVideoPlayerState? current;

  static void claim(_PostVideoPlayerState next) {
    final prev = current;
    if (prev != null && !identical(prev, next)) {
      prev.pauseExternal();
    }
    current = next;
  }

  static void release(_PostVideoPlayerState owner) {
    if (identical(current, owner)) current = null;
  }
}

/// Tap-to-play inline video. Lazy-inits the decoder and keeps the [VideoPlayer]
/// subtree stable so Android MediaCodec is not constantly reconfigured.
class PostVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double aspectRatio;

  const PostVideoPlayer({
    super.key,
    required this.videoUrl,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _hasError = false;
  bool _wantsPlay = false;
  bool _playing = false;
  /// Locked after first successful init — changing AspectRatio mid-play causes
  /// MediaCodec `setParameters` / surface thrash on Qualcomm devices.
  double? _lockedAspect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PostVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _hasError = false;
      _wantsPlay = false;
      _initializing = false;
      _playing = false;
      _lockedAspect = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      pauseExternal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ActivePostVideo.release(this);
    _disposeController();
    super.dispose();
  }

  void pauseExternal() {
    _wantsPlay = false;
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      c.pause();
      _playing = false;
      if (mounted) setState(() {});
    }
  }

  void _onControllerTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final nowPlaying = c.value.isPlaying;
    if (nowPlaying != _playing) {
      setState(() => _playing = nowPlaying);
    }
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    _playing = false;
    if (c == null) return;
    c.removeListener(_onControllerTick);
    try {
      if (c.value.isInitialized) c.pause();
    } catch (_) {}
    c.dispose();
  }

  Future<void> _ensureControllerAndPlay() async {
    if (_hasError) return;

    _ActivePostVideo.claim(this);
    _wantsPlay = true;

    var controller = _controller;
    if (controller == null) {
      setState(() {
        _initializing = true;
        _hasError = false;
      });

      controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;

      try {
        await controller.initialize();
        if (!mounted || _controller != controller) {
          await controller.dispose();
          return;
        }
        // Prefer contain-friendly ratio; never change it again during playback.
        final ar = controller.value.aspectRatio;
        _lockedAspect = (ar > 0.1 && ar < 10) ? ar : widget.aspectRatio;
        await controller.setLooping(true);
        controller.addListener(_onControllerTick);
        if (mounted) setState(() => _initializing = false);
      } catch (_) {
        if (mounted && _controller == controller) {
          setState(() {
            _initializing = false;
            _hasError = true;
          });
        }
        try {
          await controller.dispose();
        } catch (_) {}
        if (_controller == controller) _controller = null;
        return;
      }
    }

    if (!_wantsPlay || !mounted || _controller != controller) return;
    if (!controller.value.isInitialized) return;

    await controller.play();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      _wantsPlay = false;
      await controller.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _ensureControllerAndPlay();
  }

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.of(context) && _playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !TickerMode.of(context)) pauseExternal();
      });
    }

    return AspectRatio(
      aspectRatio: _lockedAspect ?? widget.aspectRatio,
      child: Material(
        color: AppColors.ink.withOpacity(0.92),
        child: InkWell(
          onTap: _initializing ? null : _togglePlay,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Stable surface: only swaps in once after init; not rebuilt away.
              if (_controller != null && _controller!.value.isInitialized)
                _StableVideoSurface(controller: _controller!),
              if (_hasError)
                const Center(
                  child: Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 40),
                )
              else if (_initializing)
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              else if (!_playing)
                Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isolates [VideoPlayer] so play-overlay setState on the parent does not
/// recreate the texture / trigger MediaCodec surface reconfiguration.
class _StableVideoSurface extends StatefulWidget {
  final VideoPlayerController controller;

  const _StableVideoSurface({required this.controller});

  @override
  State<_StableVideoSurface> createState() => _StableVideoSurfaceState();
}

class _StableVideoSurfaceState extends State<_StableVideoSurface> {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: widget.controller.value.aspectRatio > 0
              ? widget.controller.value.aspectRatio
              : 16 / 9,
          child: VideoPlayer(widget.controller),
        ),
      ),
    );
  }
}
