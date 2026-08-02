import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Reproductor compacto de nota de voz en burbuja de chat.
class ChatNotaVozPlayer extends StatefulWidget {
  const ChatNotaVozPlayer({
    super.key,
    required this.url,
    this.onDarkBubble = false,
  });

  final String url;
  final bool onDarkBubble;

  @override
  State<ChatNotaVozPlayer> createState() => _ChatNotaVozPlayerState();
}

class _ChatNotaVozPlayerState extends State<ChatNotaVozPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  Color get _fg =>
      widget.onDarkBubble ? Colors.white : const Color(0xFFECEFF1);
  Color get _muted =>
      widget.onDarkBubble ? Colors.white70 : const Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _pos = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_pos > Duration.zero && _dur > Duration.zero && _pos < _dur) {
      await _player.resume();
      return;
    }
    await _player.play(UrlSource(widget.url));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _dur.inMilliseconds <= 0 ? 1 : _dur.inMilliseconds;
    final value = (_pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
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
                color: _fg.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: _fg,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    backgroundColor: _muted.withValues(alpha: 0.25),
                    color: _fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt(_pos)} / ${_fmt(_dur)}',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
