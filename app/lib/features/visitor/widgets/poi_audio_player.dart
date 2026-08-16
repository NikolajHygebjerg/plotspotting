import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../data/models/poi_media.dart';

class PoiAudioPlayer extends StatefulWidget {
  const PoiAudioPlayer({
    super.key,
    required this.clip,
  });

  final PoiMedia clip;

  @override
  State<PoiAudioPlayer> createState() => _PoiAudioPlayerState();
}

class _PoiAudioPlayerState extends State<PoiAudioPlayer> {
  final _player = AudioPlayer();
  var _loading = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {});
    });
    _player.positionStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_failed) return;

    if (_player.playing) {
      await _player.pause();
      return;
    }

    if (_player.processingState == ProcessingState.idle) {
      setState(() {
        _loading = true;
        _failed = false;
      });
      try {
        await _player.setUrl(widget.clip.url);
      } on Object {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }

    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.clip.caption?.trim().isNotEmpty == true
        ? widget.clip.caption!.trim()
        : 'Lydfil';
    final duration = _player.duration;
    final position = _player.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            child: Icon(
              Icons.headphones_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(title),
          subtitle: _failed
              ? Text(
                  'Kunne ikke afspille lydfilen',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              : null,
          trailing: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton.filled(
                  onPressed: _failed ? null : _togglePlayback,
                  icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
                ),
        ),
        if (!_failed && duration != null && duration.inMilliseconds > 0)
          Slider(
            value: position.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toDouble(),
            max: duration.inMilliseconds.toDouble(),
            onChanged: _loading
                ? null
                : (value) => _player.seek(
                      Duration(milliseconds: value.round()),
                    ),
          ),
      ],
    );
  }
}
