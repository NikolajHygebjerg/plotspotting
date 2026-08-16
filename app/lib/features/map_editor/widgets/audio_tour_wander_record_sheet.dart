import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/audio_tour.dart';
import '../../../data/repositories/event_repository.dart';
import 'app_audio_recorder.dart';

class AudioTourWanderRecordSheet extends StatefulWidget {
  const AudioTourWanderRecordSheet({
    super.key,
    required this.eventId,
    required this.repository,
  });

  final String eventId;
  final EventRepository repository;

  static Future<AudioTourWanderClip?> show(
    BuildContext context, {
    required String eventId,
    required EventRepository repository,
  }) {
    return showModalBottomSheet<AudioTourWanderClip>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AudioTourWanderRecordSheet(
            eventId: eventId,
            repository: repository,
          ),
        );
      },
    );
  }

  @override
  State<AudioTourWanderRecordSheet> createState() =>
      _AudioTourWanderRecordSheetState();
}

class _AudioTourWanderRecordSheetState extends State<AudioTourWanderRecordSheet> {
  static const _uuid = Uuid();

  final _titleController = TextEditingController();
  String? _recordingPath;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_recordingPath == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final bytes = await File(_recordingPath!).readAsBytes();
      final wanderId = _uuid.v4();
      final title = _titleController.text.trim();

      final clip = await widget.repository.uploadWanderAudio(
        eventId: widget.eventId,
        wanderId: wanderId,
        bytes: Uint8List.fromList(bytes),
        fileName: 'vandrelyd.m4a',
        title: title.isEmpty ? 'Vandrelyd' : title,
      );

      if (!mounted) return;
      Navigator.pop(context, clip);
    } on Object catch (error) {
      setState(() {
        _saving = false;
        _error = 'Kunne ikke gemme: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Vandrelyd', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Optag lyd der afspilles mens gæsten går til næste stop.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Titel (valgfri)',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          AppAudioRecorder(
            onRecordingReady: (path) => setState(() => _recordingPath = path),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _recordingPath != null && !_saving ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Tilføj vandrelyd'),
          ),
        ],
      ),
    );
  }
}
