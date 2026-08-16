import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum AppAudioRecorderState { idle, recording, recorded }

class AppAudioRecorder extends StatefulWidget {
  const AppAudioRecorder({
    super.key,
    required this.onRecordingReady,
  });

  final ValueChanged<String> onRecordingReady;

  @override
  State<AppAudioRecorder> createState() => _AppAudioRecorderState();
}

class _AppAudioRecorderState extends State<AppAudioRecorder> {
  final _recorder = AudioRecorder();
  AppAudioRecorderState _state = AppAudioRecorderState.idle;
  String? _filePath;
  String? _error;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _error = 'Giv adgang til mikrofon for at optage');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/tour_${DateTime.now().millisecondsSinceEpoch}.m4a';

    setState(() {
      _error = null;
      _filePath = null;
      _state = AppAudioRecorderState.recording;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
    });

    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
    } on Object catch (error) {
      setState(() {
        _state = AppAudioRecorderState.idle;
        _error = 'Kunne ikke starte optagelse: $error';
      });
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (path == null || !mounted) return;

    setState(() {
      _filePath = path;
      _state = AppAudioRecorderState.recorded;
      _elapsed = _startedAt == null
          ? Duration.zero
          : DateTime.now().difference(_startedAt!);
    });
    widget.onRecordingReady(path);
  }

  Future<void> _discard() async {
    final path = _filePath;
    if (path != null) {
      try {
        await File(path).delete();
      } on Object {
        // Best-effort.
      }
    }
    setState(() {
      _filePath = null;
      _state = AppAudioRecorderState.idle;
      _elapsed = Duration.zero;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_state == AppAudioRecorderState.recording)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.fiber_manual_record, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Optager…',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (_state == AppAudioRecorderState.recorded) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Optagelse klar (${_formatDuration(_elapsed)})',
                    style: TextStyle(color: Colors.green.shade900),
                  ),
                ),
                TextButton(onPressed: _discard, child: const Text('Optag igen')),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _state == AppAudioRecorderState.recording
              ? _stopRecording
              : _state == AppAudioRecorderState.recorded
                  ? null
                  : _startRecording,
          icon: Icon(
            _state == AppAudioRecorderState.recording ? Icons.stop : Icons.mic,
          ),
          label: Text(
            _state == AppAudioRecorderState.recording
                ? 'Stop optagelse'
                : _state == AppAudioRecorderState.recorded
                    ? 'Optagelse gemt'
                    : 'Start optagelse',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: _state == AppAudioRecorderState.recording
                ? Colors.red.shade700
                : const Color(0xFF6A1B9A),
          ),
        ),
      ],
    );
  }
}
