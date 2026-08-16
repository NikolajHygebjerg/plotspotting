import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/poi_media.dart';
import '../../../data/repositories/event_repository.dart';

/// Holder POI-medier uden for widget-rebuilds.
class PoiMediaEditorController {
  PoiMediaEditorController(List<PoiMedia> initial)
      : _media = List<PoiMedia>.from(initial);

  List<PoiMedia> _media;

  List<PoiMedia> get media => List<PoiMedia>.unmodifiable(_media);

  void _replace(List<PoiMedia> next) {
    _media = List<PoiMedia>.from(next);
  }
}

class PoiMediaEditor extends StatefulWidget {
  const PoiMediaEditor({
    super.key,
    required this.eventId,
    required this.poiId,
    required this.repository,
    required this.controller,
    this.showAudio = true,
    this.showVisual = true,
  });

  final String eventId;
  final String poiId;
  final EventRepository repository;
  final PoiMediaEditorController controller;
  final bool showAudio;
  final bool showVisual;

  @override
  State<PoiMediaEditor> createState() => _PoiMediaEditorState();
}

class _PoiMediaEditorState extends State<PoiMediaEditor> {
  late List<PoiMedia> _media;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _media = List<PoiMedia>.from(widget.controller.media);
  }

  void _syncController() {
    widget.controller._replace(_media);
  }

  List<PoiMedia> get _visualMedia =>
      _media.where((item) => item.kind != PoiMediaKind.audio).toList();

  List<PoiMedia> get _audioClips =>
      _media.where((item) => item.kind == PoiMediaKind.audio).toList();

  Future<String?> _promptAudioName({String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _AudioNameDialog(initial: initial),
    );
  }

  Future<void> _pickAndUpload(PoiMediaKind kind) async {
    if (_uploading) return;

    final picked = kind == PoiMediaKind.image
        ? await ImagePicker().pickImage(source: ImageSource.gallery)
        : await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    await _uploadBytes(
      bytes: await picked.readAsBytes(),
      fileName: picked.name.isNotEmpty ? picked.name : picked.path.split('/').last,
      kind: kind,
    );
  }

  Future<void> _pickAudioAndUpload() async {
    if (_uploading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final name = await _promptAudioName();
    if (name == null || !mounted) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giv lydfilen et navn')),
      );
      return;
    }

    await _uploadBytes(
      bytes: bytes,
      fileName: file.name,
      kind: PoiMediaKind.audio,
      caption: name,
    );
  }

  Future<void> _renameAudio(PoiMedia clip) async {
    final name = await _promptAudioName(initial: clip.caption);
    if (name == null || name.isEmpty || !mounted) return;

    setState(() {
      _media = _media
          .map(
            (item) => item.id == clip.id ? item.copyWith(caption: name) : item,
          )
          .toList();
    });
    _syncController();
  }

  Future<void> _uploadBytes({
    required List<int> bytes,
    required String fileName,
    required PoiMediaKind kind,
    String? caption,
  }) async {
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final uploaded = await widget.repository.uploadPoiMedia(
        eventId: widget.eventId,
        poiId: widget.poiId,
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fileName: fileName,
        kind: kind,
        caption: caption,
      );

      if (!mounted) return;
      setState(() {
        _media = [..._media, uploaded];
        _uploading = false;
      });
      _syncController();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Kunne ikke uploade: $error';
      });
    }
  }

  Future<void> _removeMedia(PoiMedia item) async {
    await widget.repository.deletePoiMedia(item);
    if (!mounted) return;
    setState(() {
      _media = _media.where((entry) => entry.id != item.id).toList();
    });
    _syncController();
  }

  @override
  Widget build(BuildContext context) {
    final audioClips = _audioClips;
    final visual = _visualMedia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showAudio) ...[
          Text('Lydfortællinger', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Upload flere lydfiler med navn — brug dem i forskellige tematiske lydvandringer',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final audio in audioClips)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6A1B9A).withValues(alpha: 0.12),
                child: const Icon(Icons.audiotrack, color: Color(0xFF6A1B9A)),
              ),
              title: Text(
                audio.caption?.isNotEmpty == true ? audio.caption! : 'Lydfil',
              ),
              subtitle: const Text('Klar til lydvandring'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Omdøb',
                    onPressed: _uploading ? null : () => _renameAudio(audio),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: _uploading ? null : () => _removeMedia(audio),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickAudioAndUpload,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Tilføj lydfil'),
          ),
          if (widget.showVisual) const SizedBox(height: 20),
        ],
        if (widget.showVisual) ...[
          Text('Billeder og video', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Vises når besøgende trykker på stedet i «Find et sted» og «Gå på opdagelse»',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (visual.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visual.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = visual[index];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: _mediaPlaceholder(item),
                        ),
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: _uploading ? null : () => _removeMedia(item),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (_uploading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickAndUpload(PoiMediaKind.image),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Tilføj billede'),
              ),
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickAndUpload(PoiMediaKind.video),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Tilføj video'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _mediaPlaceholder(PoiMedia item) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          item.kind == PoiMediaKind.video
              ? Icons.play_circle_outline
              : Icons.image_outlined,
          size: 36,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _AudioNameDialog extends StatefulWidget {
  const _AudioNameDialog({this.initial});

  final String? initial;

  @override
  State<_AudioNameDialog> createState() => _AudioNameDialogState();
}

class _AudioNameDialogState extends State<_AudioNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Navn på lydfil'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Fx Historie, Natur, Børn',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Gem'),
        ),
      ],
    );
  }
}
