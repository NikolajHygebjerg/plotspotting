import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/geo/geo_utils.dart';
import '../../../data/models/map_poi.dart';
import '../../../data/models/poi_media.dart';
import '../../../data/repositories/event_repository.dart';
import 'app_audio_recorder.dart';

class AudioTourStopRecordResult {
  const AudioTourStopRecordResult({
    required this.poi,
    required this.isNew,
    required this.audioId,
  });

  final MapPoi poi;
  final bool isNew;
  final String audioId;
}

enum _StopChoice { existing, newPlace }

class AudioTourStopRecordSheet extends StatefulWidget {
  const AudioTourStopRecordSheet({
    super.key,
    required this.eventId,
    required this.repository,
    required this.nearbyPois,
    required this.lat,
    required this.lng,
    this.accessVertexId,
    this.preselectedPoi,
  });

  final String eventId;
  final EventRepository repository;
  final List<MapPoi> nearbyPois;
  final double lat;
  final double lng;
  final String? accessVertexId;
  final MapPoi? preselectedPoi;

  static Future<AudioTourStopRecordResult?> show(
    BuildContext context, {
    required String eventId,
    required EventRepository repository,
    required List<MapPoi> allPois,
    required double lat,
    required double lng,
    String? accessVertexId,
    MapPoi? preselectedPoi,
  }) {
    final nearby = allPois
        .map((poi) => (
              poi,
              haversineMeters(lat, lng, poi.lat, poi.lng),
            ))
        .where((entry) => entry.$2 <= 80)
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    return showModalBottomSheet<AudioTourStopRecordResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AudioTourStopRecordSheet(
            eventId: eventId,
            repository: repository,
            nearbyPois: nearby.map((entry) => entry.$1).toList(),
            lat: lat,
            lng: lng,
            accessVertexId: accessVertexId,
            preselectedPoi: preselectedPoi,
          ),
        );
      },
    );
  }

  @override
  State<AudioTourStopRecordSheet> createState() =>
      _AudioTourStopRecordSheetState();
}

class _AudioTourStopRecordSheetState extends State<AudioTourStopRecordSheet> {
  static const _uuid = Uuid();

  late _StopChoice _choice;
  MapPoi? _selectedPoi;
  final _nameController = TextEditingController();
  final _audioTitleController = TextEditingController(text: 'Fortælling');
  String _category = 'info';
  String? _recordingPath;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedPoi != null) {
      _choice = _StopChoice.existing;
      _selectedPoi = widget.preselectedPoi;
    } else if (widget.nearbyPois.isNotEmpty) {
      _choice = _StopChoice.existing;
      _selectedPoi = widget.nearbyPois.first;
    } else {
      _choice = _StopChoice.newPlace;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _audioTitleController.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_recordingPath == null) return false;
    if (_audioTitleController.text.trim().isEmpty) return false;
    if (_choice == _StopChoice.existing) return _selectedPoi != null;
    return _nameController.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final bytes = await File(_recordingPath!).readAsBytes();
      final isNew = _choice == _StopChoice.newPlace;
      final poiId = isNew ? _uuid.v4() : _selectedPoi!.id;
      final audioTitle = _audioTitleController.text.trim();

      final uploaded = await widget.repository.uploadPoiMedia(
        eventId: widget.eventId,
        poiId: poiId,
        bytes: Uint8List.fromList(bytes),
        fileName: 'optagelse.m4a',
        kind: PoiMediaKind.audio,
        caption: audioTitle,
      );

      final baseMedia = isNew
          ? <PoiMedia>[uploaded]
          : [..._selectedPoi!.media, uploaded];

      final poi = isNew
          ? MapPoi(
              id: poiId,
              name: _nameController.text.trim(),
              category: _category,
              lat: widget.lat,
              lng: widget.lng,
              accessVertexId: widget.accessVertexId,
              media: baseMedia,
            )
          : _selectedPoi!.copyWith(
              lat: widget.lat,
              lng: widget.lng,
              accessVertexId: widget.accessVertexId ?? _selectedPoi!.accessVertexId,
              media: baseMedia,
            );

      if (!mounted) return;
      Navigator.pop(
        context,
        AudioTourStopRecordResult(
          poi: poi,
          isNew: isNew,
          audioId: uploaded.id,
        ),
      );
    } on Object catch (error) {
      setState(() {
        _saving = false;
        _error = 'Kunne ikke gemme: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              Text(
                'Fortælling her',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Vælg et eksisterende sted eller opret et nyt, og optag fortællingen.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SegmentedButton<_StopChoice>(
                segments: const [
                  ButtonSegment(
                    value: _StopChoice.existing,
                    label: Text('Eksisterende sted'),
                    icon: Icon(Icons.place_outlined),
                  ),
                  ButtonSegment(
                    value: _StopChoice.newPlace,
                    label: Text('Nyt sted'),
                    icon: Icon(Icons.add_location_alt_outlined),
                  ),
                ],
                selected: {_choice},
                onSelectionChanged: (selection) {
                  setState(() => _choice = selection.first);
                },
              ),
              const SizedBox(height: 16),
              if (_choice == _StopChoice.existing) ...[
                if (widget.nearbyPois.isEmpty)
                  const Text('Ingen steder i nærheden — opret et nyt sted.')
                else
                  ...widget.nearbyPois.map((poi) {
                    final selected = _selectedPoi?.id == poi.id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: const Icon(Icons.place),
                        title: Text(poi.displayTitle),
                        subtitle: Text(poi.displaySubtitle),
                        trailing: poi.audioClips.isNotEmpty
                            ? Text('${poi.audioClips.length} lyd')
                            : null,
                        onTap: () => setState(() => _selectedPoi = poi),
                      ),
                    );
                  }),
              ] else ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Navn på stedet',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'home', child: Text('Bolig')),
                    DropdownMenuItem(value: 'info', child: Text('Info')),
                    DropdownMenuItem(value: 'activity', child: Text('Aktivitet')),
                    DropdownMenuItem(value: 'food', child: Text('Mad')),
                    DropdownMenuItem(value: 'other', child: Text('Andet')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _audioTitleController,
                decoration: const InputDecoration(
                  labelText: 'Navn på fortællingen',
                  hintText: 'Fx Historie, Natur, Børn',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('Optag fortælling', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              AppAudioRecorder(
                onRecordingReady: (path) => setState(() => _recordingPath = path),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _canSave && !_saving ? _save : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Tilføj til lydvandring'),
              ),
            ],
          ),
        );
      },
    );
  }
}
