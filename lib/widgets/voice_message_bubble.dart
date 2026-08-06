import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../theme/app_colors.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String mediaUrl;
  final int? durationMs;
  final bool mine;

  const VoiceMessageBubble({
    super.key,
    required this.mediaUrl,
    this.durationMs,
    required this.mine,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null && widget.durationMs! > 0) {
      _duration = Duration(milliseconds: widget.durationMs!);
    }
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      if (d.inMilliseconds > 0) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _resolveUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return path.startsWith('/') ? '$base$path' : '$base/$path';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    final url = _resolveUrl(widget.mediaUrl);
    if (_position > Duration.zero && _position < _duration) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds > 0
        ? _duration
        : Duration(milliseconds: widget.durationMs ?? 0);
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final fg = widget.mine ? Colors.white : AppColors.primary;
    final track = widget.mine ? Colors.white38 : AppColors.primary.withOpacity(0.2);

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.mine ? Colors.white.withOpacity(0.2) : AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: track,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing || _position > Duration.zero
                      ? _fmt(_position)
                      : (total.inMilliseconds > 0 ? _fmt(total) : '0:00'),
                  style: TextStyle(
                    color: widget.mine ? Colors.white70 : Colors.black45,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
