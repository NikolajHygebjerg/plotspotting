import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_poi.dart';
import '../../data/repositories/event_repository.dart';
import '../organizer/organizer_shell.dart';
import 'audio_tour_creation_method.dart';
import 'audio_tour_walk_screen.dart';
import 'widgets/poi_audio_picker_sheet.dart';

class AudioTourEditorScreen extends StatefulWidget {
  const AudioTourEditorScreen({
    super.key,
    required this.eventId,
    required this.mapData,
    required this.onSaved,
    this.useOrganizerShell = false,
  });

  final String eventId;
  final EventMapData mapData;
  final ValueChanged<EventMapData> onSaved;
  final bool useOrganizerShell;

  @override
  State<AudioTourEditorScreen> createState() => _AudioTourEditorScreenState();
}

class _AudioTourEditorScreenState extends State<AudioTourEditorScreen> {
  final _repository = EventRepository();
  final _uuid = const Uuid();

  late EventMapData _mapData;
  late List<AudioTourConfig> _tours;
  late String _selectedTourId;
  late bool _enabled;
  late List<AudioTourItem> _items;
  AudioTourCreationMethod? _creationMethod;
  bool _saving = false;
  String? _error;

  List<MapPoi> get _poisWithAudio =>
      _mapData.pois.where((poi) => poi.hasAudio).toList();

  AudioTourConfig get _currentTour =>
      _tours.firstWhere((tour) => tour.id == _selectedTourId);

  bool get _currentTourReadyForGuests =>
      _enabled &&
      _items.any((item) => item.kind == AudioTourItemKind.poi);

  String? get _guestReadinessHint {
    if (!_enabled) {
      return 'Slå «Aktivér dette tema» til for at vise lydvandringen for gæster.';
    }
    if (!_currentTourReadyForGuests) {
      return 'Tilføj mindst ét sted med lyd som startsted — kun vandrelyd er ikke nok.';
    }
    return 'Gæster kan vælge denne lydvandring når kortet er publiceret og gemt.';
  }

  @override
  void initState() {
    super.initState();
    _mapData = widget.mapData;
    _tours = List<AudioTourConfig>.from(_mapData.audioTourCatalog.tours);
    if (_tours.isEmpty) {
      _selectedTourId = '';
      _enabled = false;
      _items = [];
      _creationMethod = null;
    } else {
      _selectedTourId = _tours.first.id;
      _loadSelectedTour();
      _creationMethod = AudioTourCreationMethod.manual;
    }
  }

  void _loadSelectedTour() {
    final tour = _currentTour;
    _enabled = tour.enabled;
    _items = List<AudioTourItem>.from(tour.items);
  }

  void _persistCurrentTour() {
    if (_selectedTourId.isEmpty) return;
    final index = _tours.indexWhere((tour) => tour.id == _selectedTourId);
    if (index < 0) return;
    _tours[index] = _currentTour.copyWith(enabled: _enabled, items: _items);
  }

  Future<String?> _promptTourTitle({String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _TourTitleDialog(initial: initial),
    );
  }

  Future<void> _createTour({AudioTourCreationMethod? method}) async {
    final title = await _promptTourTitle();
    if (title == null || title.isEmpty || !mounted) return;

    _persistCurrentTour();
    final tour = AudioTourConfig(
      id: _uuid.v4(),
      title: title,
      enabled: true,
    );

    setState(() {
      _tours = [..._tours, tour];
      _selectedTourId = tour.id;
      _enabled = true;
      _items = [];
      _creationMethod = method ?? AudioTourCreationMethod.manual;
    });

    if (method == AudioTourCreationMethod.walk) {
      await _openWalkEditor();
    }
  }

  void _switchTour(String tourId) {
    if (tourId == _selectedTourId) return;
    _persistCurrentTour();
    setState(() {
      _selectedTourId = tourId;
      _loadSelectedTour();
    });
  }

  Future<void> _renameCurrentTour() async {
    final title = await _promptTourTitle(initial: _currentTour.title);
    if (title == null || title.isEmpty) return;
    _persistCurrentTour();
    setState(() {
      final index = _tours.indexWhere((tour) => tour.id == _selectedTourId);
      if (index >= 0) {
        _tours[index] = _tours[index].copyWith(title: title);
      }
    });
  }

  Future<void> _openWalkEditor() async {
    if (_selectedTourId.isEmpty) {
      await _createTour(method: AudioTourCreationMethod.walk);
      return;
    }

    _persistCurrentTour();
    final tour = _currentTour;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AudioTourWalkScreen(
          eventId: widget.eventId,
          mapData: _mapData,
          tour: tour,
          onSaved: (updated) {
            widget.onSaved(updated);
            setState(() {
              _mapData = updated;
              _tours = List<AudioTourConfig>.from(updated.audioTourCatalog.tours);
              if (_tours.any((entry) => entry.id == tour.id)) {
                _selectedTourId = tour.id;
              } else if (_tours.isNotEmpty) {
                _selectedTourId = _tours.first.id;
              }
              _loadSelectedTour();
              _creationMethod = AudioTourCreationMethod.walk;
            });
          },
        ),
      ),
    );
  }

  Future<void> _selectCreationMethod(AudioTourCreationMethod method) async {
    if (method == AudioTourCreationMethod.walk) {
      await _createTour(method: method);
      return;
    }
    await _createTour(method: method);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    _persistCurrentTour();

    final incompleteEnabled = _tours.where((tour) => tour.enabled && !tour.isConfigured);
    if (incompleteEnabled.isNotEmpty) {
      setState(() {
        _saving = false;
        _error =
            'Aktiverede lydvandringer skal have mindst ét sted med lyd i ruten '
            '— tilføj et startsted og tryk Gem igen';
      });
      return;
    }

    final metadata = {
      ..._mapData.event.metadata,
      ...AudioTourCatalog(_tours).toEventMetadata(),
    };
    metadata.remove('audio_tour');

    try {
      await _repository.saveGraph(
        eventId: widget.eventId,
        vertices: _mapData.vertices,
        edges: _mapData.edges,
        pois: _mapData.pois,
        centerLat: _mapData.event.centerLat,
        centerLng: _mapData.event.centerLng,
      );
      await _repository.saveMetadata(
        eventId: widget.eventId,
        metadata: metadata,
      );
      if (!mounted) return;
      widget.onSaved(
        _mapData.copyWith(
          event: _mapData.event.copyWith(metadata: metadata),
        ),
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lydvandring gemt')),
      );
    } on Object catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPoiStop() async {
    final usedIds = _items
        .where((item) => item.kind == AudioTourItemKind.poi)
        .map((item) => item.poiId!)
        .toSet();
    final options = _poisWithAudio.where((poi) => !usedIds.contains(poi.id)).toList();

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingen flere steder med lyd — tilføj navngivne lydfiler på stederne først',
          ),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<MapPoi>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Vælg sted med lydfil',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final poi = options[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(poi.displayTitle),
                      subtitle: Text(
                        '${poi.audioClips.length} lydfil${poi.audioClips.length == 1 ? '' : 'er'}',
                      ),
                      onTap: () => Navigator.pop(context, poi),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    final audio = await pickPoiAudioClip(context, selected);
    if (audio == null || !mounted) return;

    setState(() {
      _items = [
        ..._items,
        AudioTourItem.poi(poiId: selected.id, audioId: audio.id),
      ];
      _enabled = true;
    });
  }

  Future<void> _addWanderClip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final wanderId = _uuid.v4();
    setState(() => _saving = true);
    try {
      final clip = await _repository.uploadWanderAudio(
        eventId: widget.eventId,
        wanderId: wanderId,
        bytes: Uint8List.fromList(bytes),
        fileName: file.name,
        title: file.name,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, AudioTourItem.wander(wander: clip)];
        _enabled = true;
      });
    } on Object catch (error) {
      setState(() => _error = 'Kunne ikke uploade vandrelyd: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeItem(int index) async {
    final item = _items[index];
    if (item.kind == AudioTourItemKind.wander && item.wander != null) {
      await _repository.deleteWanderAudio(item.wander!);
    }
    setState(() => _items = [..._items]..removeAt(index));
  }

  String _itemTitle(AudioTourItem item, int index) {
    if (item.kind == AudioTourItemKind.wander) {
      return item.wander?.title?.isNotEmpty == true
          ? item.wander!.title!
          : 'Vandrelyd';
    }
    final poi = _mapData.poiById(item.poiId!);
    final label = poi?.displayTitle ?? 'Sted';
    final audio = poi?.audioById(item.audioId);
    final audioLabel = audio != null && poi != null ? poi.audioLabel(audio) : null;
    final isFirstPoi =
        !_items.take(index).any((entry) => entry.kind == AudioTourItemKind.poi);
    final placeLabel = isFirstPoi ? 'Start: $label' : label;
    if (audioLabel != null) return '$placeLabel · $audioLabel';
    return placeLabel;
  }

  String _itemSubtitle(AudioTourItem item, int index) {
    if (item.kind == AudioTourItemKind.wander) {
      return 'Vandrelyd — afspilles mens gæsten går videre';
    }
    return index == 0 && item.kind == AudioTourItemKind.poi
        ? 'Startsted for lydvandringen'
        : 'Stop med lydfil';
  }

  IconData _itemIcon(AudioTourItem item) =>
      item.kind == AudioTourItemKind.wander ? Icons.directions_walk : Icons.place;

  @override
  Widget build(BuildContext context) {
    final hasStart = _items.any((item) => item.kind == AudioTourItemKind.poi);
    final editingTour = _selectedTourId.isNotEmpty;

    final shellActions = [
      if (_creationMethod == AudioTourCreationMethod.manual && editingTour)
        IconButton(
          tooltip: 'Gå ruten fysisk',
          onPressed: _openWalkEditor,
          icon: const Icon(Icons.directions_walk),
        ),
      if (_saving)
        const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else
        TextButton(onPressed: _creationMethod != null ? _save : null, child: const Text('Gem')),
    ];

    return Scaffold(
      appBar: widget.useOrganizerShell
          ? OrganizerShellAppBar(
              title: 'Lydvandring',
              actions: shellActions,
            )
          : AppBar(
              title: const Text('Lydvandring'),
              actions: shellActions,
            ),
      body: _creationMethod == null
          ? _CreationMethodPicker(onSelected: _selectCreationMethod)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedTourId,
                        decoration: const InputDecoration(
                          labelText: 'Tema',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final tour in _tours)
                            DropdownMenuItem(
                              value: tour.id,
                              child: Text(tour.displayTitle),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _switchTour(value);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Omdøb tema',
                      onPressed: _renameCurrentTour,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Nyt tema',
                      onPressed: () => _createTour(),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktivér dette tema'),
                  subtitle: const Text('Gæster kan vælge guidet lydvandring på kortet'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                if (_guestReadinessHint != null) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: _currentTourReadyForGuests
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(_guestReadinessHint!),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Byg ruten som en liste: vælg sted og hvilken lydfil der hører til '
                  'dette tema, plus vandrelyd imellem stop.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_poisWithAudio.isEmpty) ...[
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Tilføj navngivne lydfiler på stederne først '
                        '(rediger et sted → Lydfortællinger → Tilføj lydfil).',
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Tilføj et startsted med lyd for at begynde.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _items.removeAt(oldIndex);
                        _items.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        key: ValueKey(
                          '${item.kind}-${item.poiId ?? item.wander?.id}-${item.audioId}-$index',
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(_itemIcon(item)),
                          title: Text(_itemTitle(item, index)),
                          subtitle: Text(_itemSubtitle(item, index)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeItem(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (!hasStart && _items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Første sted i listen bliver startpunktet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
      floatingActionButton: _creationMethod == AudioTourCreationMethod.manual
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'wander',
                  onPressed: _saving ? null : _addWanderClip,
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Vandrelyd'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'poi',
                  onPressed: _saving ? null : _addPoiStop,
                  icon: const Icon(Icons.place),
                  label: Text(_items.isEmpty ? 'Startsted' : 'Tilføj sted'),
                ),
              ],
            )
          : null,
    );
  }
}

class _TourTitleDialog extends StatefulWidget {
  const _TourTitleDialog({this.initial});

  final String? initial;

  @override
  State<_TourTitleDialog> createState() => _TourTitleDialogState();
}

class _TourTitleDialogState extends State<_TourTitleDialog> {
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
      title: const Text('Navn på lydvandring'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Fx Historisk tur, Natur for børn',
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
          child: const Text('Opret'),
        ),
      ],
    );
  }
}

class _CreationMethodPicker extends StatelessWidget {
  const _CreationMethodPicker({required this.onSelected});

  final ValueChanged<AudioTourCreationMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hvordan vil du lave lydvandringen?',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Giv turen et tema og vælg om du går ruten fysisk eller bygger listen manuelt.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                for (final method in AudioTourCreationMethod.values) ...[
                  _MethodOptionCard(
                    icon: method == AudioTourCreationMethod.walk
                        ? Icons.directions_walk
                        : Icons.list_alt,
                    title: method.title,
                    subtitle: method.subtitle,
                    onTap: () => onSelected(method),
                  ),
                  if (method != AudioTourCreationMethod.values.last)
                    const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodOptionCard extends StatelessWidget {
  const _MethodOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
