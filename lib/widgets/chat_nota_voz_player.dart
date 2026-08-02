import 'dart:async';
import 'dart:io' show File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/chat_audio_cache_service.dart';

/// Reproductor compacto de nota de voz en burbuja de chat.
/// Usa caché en disco cuando hay archivo local (offline).
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
  bool _loading = false;
  bool _error = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  StreamSubscription<PlayerState>? _subState;
  StreamSubscription<Duration>? _subDur;
  StreamSubscription<Duration>? _subPos;
  StreamSubscription<void>? _subComplete;

  Color get _fg =>
      widget.onDarkBubble ? Colors.white : const Color(0xFFECEFF1);
  Color get _muted =>
      widget.onDarkBubble ? Colors.white70 : const Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
    if (!kIsWeb) {
      unawaited(_player.setPlayerMode(PlayerMode.mediaPlayer));
    }
    _subState = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _subDur = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
    });
    _subPos = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
    });
    _subComplete = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _pos = Duration.zero;
      });
    });
    // Prefetch en frío para offline.
    if (!kIsWeb && widget.url.startsWith('http')) {
      unawaited(ChatAudioCache.prefetch(widget.url));
    }
  }

  @override
  void dispose() {
    _subState?.cancel();
    _subDur?.cancel();
    _subPos?.cancel();
    _subComplete?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_pos > Duration.zero && _dur > Duration.zero && _pos < _dur) {
        await _player.resume();
        return;
      }

      setState(() {
        _loading = true;
        _error = false;
      });

      const mime = 'audio/mp4';
      Source source;
      if (!kIsWeb) {
        final local = await ChatAudioCache.ensureLocal(widget.url);
        if (local != null && await File(local).exists()) {
          source = DeviceFileSource(local, mimeType: mime);
        } else {
          source = UrlSource(widget.url, mimeType: mime);
        }
      } else {
        source = UrlSource(widget.url, mimeType: mime);
      }

      await _player.play(source);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _playing = false;
      });
    }
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
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _fg,
                      ),
                    )
                  : Icon(
                      _error
                          ? Icons.refresh_rounded
                          : (_playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
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
                    value: _error ? 0 : value,
                    minHeight: 3,
                    backgroundColor: _muted.withValues(alpha: 0.25),
                    color: _error ? const Color(0xFFDC2626) : _fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error
                      ? 'Toca para reintentar'
                      : 'Nota de voz  ${_fmt(_pos)} / ${_fmt(_dur)}',
                  style: TextStyle(
                    color: _error ? const Color(0xFFFFCDD2) : _muted,
                    fontSize: 11,
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
