import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/map_poi.dart';
import '../../../data/models/poi_occupant.dart';
import '../../../data/models/poi_topic.dart';
import '../../../data/repositories/event_repository.dart';
import 'poi_media_editor.dart';
import 'poi_topic_section.dart';

enum PoiEditorAction {
  cancel,
  save,
  delete,
  movePin,
  connectToPath,
}

class PoiEditorSheetResult {
  const PoiEditorSheetResult({
    required this.action,
    this.poi,
  });

  final PoiEditorAction action;
  final MapPoi? poi;
}

/// Bottom sheet til oprettelse/redigering af et sted — egen State uden StatefulBuilder.
class PoiEditorSheet extends StatefulWidget {
  const PoiEditorSheet({
    super.key,
    required this.eventId,
    required this.repository,
    required this.existing,
    required this.lat,
    required this.lng,
    required this.isNew,
    required this.mappingHint,
    required this.hasPaths,
    required this.hasActiveConnection,
  });

  final String eventId;
  final EventRepository repository;
  final MapPoi? existing;
  final double lat;
  final double lng;
  final bool isNew;
  final String? mappingHint;
  final bool hasPaths;
  final bool hasActiveConnection;

  static Future<PoiEditorSheetResult?> show(
    BuildContext context, {
    required String eventId,
    required EventRepository repository,
    required MapPoi? existing,
    required double lat,
    required double lng,
    required bool isNew,
    String? mappingHint,
    required bool hasPaths,
    required bool hasActiveConnection,
  }) {
    return showModalBottomSheet<PoiEditorSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: PoiEditorSheet(
            eventId: eventId,
            repository: repository,
            existing: existing,
            lat: lat,
            lng: lng,
            isNew: isNew,
            mappingHint: mappingHint,
            hasPaths: hasPaths,
            hasActiveConnection: hasActiveConnection,
          ),
        );
      },
    );
  }

  @override
  State<PoiEditorSheet> createState() => _PoiEditorSheetState();
}

class _PoiEditorSheetState extends State<PoiEditorSheet> {
  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _houseController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _keywordsController;
  late final List<TextEditingController> _occupantControllers;
  late final List<PoiOccupantKind> _occupantKinds;
  late final PoiMediaEditorController _mediaController;
  late final String _poiId;

  var _category = 'home';
  late final _PoiFormSnapshot _initialSnapshot;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _poiId = existing?.id ?? _uuid.v4();
    _nameController = TextEditingController(text: existing?.name ?? '');
    _houseController = TextEditingController(text: existing?.houseNumber ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _keywordsController = TextEditingController(text: existing?.searchKeywords ?? '');
    _category = existing?.category ?? 'home';
    _mediaController = PoiMediaEditorController(existing?.media ?? const []);

    _occupantControllers = [];
    _occupantKinds = [];
    if (existing != null && existing.occupants.isNotEmpty) {
      for (final occupant in existing.occupants) {
        _addOccupantRow(name: occupant.name, kind: occupant.kind);
      }
    } else {
      _addOccupantRow();
    }

    _initialSnapshot = _captureSnapshot();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _houseController.dispose();
    _descriptionController.dispose();
    _keywordsController.dispose();
    for (final controller in _occupantControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOccupantRow({String name = '', PoiOccupantKind kind = PoiOccupantKind.resident}) {
    _occupantControllers.add(TextEditingController(text: name));
    _occupantKinds.add(kind);
  }

  MapPoi _buildPoi() {
    final existing = widget.existing;
    final houseNumber = _houseController.text.trim();
    final description = _descriptionController.text.trim();
    final searchKeywords = _keywordsController.text.trim();
    final occupants = <PoiOccupant>[];

    for (var index = 0; index < _occupantControllers.length; index++) {
      final occupantName = _occupantControllers[index].text.trim();
      if (occupantName.isEmpty) continue;
      occupants.add(
        PoiOccupant(name: occupantName, kind: _occupantKinds[index]),
      );
    }

    var displayName = _nameController.text.trim();
    if (displayName.isEmpty) {
      final occupantNames = occupants.map((occupant) => occupant.name).toList();
      if (houseNumber.isNotEmpty && occupantNames.isNotEmpty) {
        displayName = occupantNames.length == 1
            ? '$houseNumber · ${occupantNames.first}'
            : '$houseNumber · ${occupantNames.join(', ')}';
      } else if (houseNumber.isNotEmpty) {
        displayName = houseNumber;
      } else if (occupantNames.isNotEmpty) {
        displayName = occupantNames.join(', ');
      } else {
        displayName = 'Sted';
      }
    }

    return MapPoi(
      id: _poiId,
      name: displayName,
      category: _category,
      lat: existing?.lat ?? widget.lat,
      lng: existing?.lng ?? widget.lng,
      description: description.isEmpty ? null : description,
      accessVertexId: existing?.accessVertexId,
      houseNumber: houseNumber.isEmpty ? null : houseNumber,
      occupants: occupants,
      searchKeywords: searchKeywords.isEmpty ? null : searchKeywords,
      media: _mediaController.media,
    );
  }

  _PoiFormSnapshot _captureSnapshot() {
    final occupants = <String>[];
    for (var index = 0; index < _occupantControllers.length; index++) {
      occupants.add(
        '${_occupantKinds[index].name}:${_occupantControllers[index].text.trim()}',
      );
    }

    return _PoiFormSnapshot(
      name: _nameController.text.trim(),
      houseNumber: _houseController.text.trim(),
      description: _descriptionController.text.trim(),
      searchKeywords: _keywordsController.text.trim(),
      category: _category,
      occupants: occupants,
      mediaIds: _mediaController.media.map((item) => item.id).toList()..sort(),
    );
  }

  bool _hasUnsavedChanges() => !_captureSnapshot().equals(_initialSnapshot);

  bool _validateForm() {
    final hasAddress = _houseController.text.trim().isNotEmpty;
    final hasOccupant =
        _occupantControllers.any((controller) => controller.text.trim().isNotEmpty);
    final hasNickname = _nameController.text.trim().isNotEmpty;
    if (hasAddress || hasOccupant || hasNickname) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Angiv mindst adresse, et navn eller kaldenavn'),
      ),
    );
    return false;
  }

  Future<void> _closeWithoutSaving() async {
    if (!mounted) return;
    Navigator.pop(
      context,
      const PoiEditorSheetResult(action: PoiEditorAction.cancel),
    );
  }

  Future<void> _saveAndClose() async {
    if (!_validateForm()) return;
    if (!mounted) return;
    Navigator.pop(
      context,
      PoiEditorSheetResult(
        action: PoiEditorAction.save,
        poi: _buildPoi(),
      ),
    );
  }

  void _connectToPath() {
    if (!widget.hasPaths) return;
    if (!_validateForm()) return;
    Navigator.pop(
      context,
      PoiEditorSheetResult(
        action: PoiEditorAction.connectToPath,
        poi: _buildPoi(),
      ),
    );
  }

  Future<void> _requestClose() async {
    if (!_hasUnsavedChanges()) {
      await _closeWithoutSaving();
      return;
    }

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gem ændringer?'),
        content: const Text('Du har ændringer der ikke er gemt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuller'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Gem ikke'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gem'),
          ),
        ],
      ),
    );

    if (!mounted || save == null) return;
    if (save) {
      await _saveAndClose();
    } else {
      await _closeWithoutSaving();
    }
  }

  Future<void> _deletePoi() async {
    final existing = widget.existing;
    if (existing == null) return;

    for (final item in existing.media) {
      await widget.repository.deletePoiMedia(item);
    }
    for (final item in _mediaController.media) {
      if (existing.media.any((entry) => entry.id == item.id)) continue;
      await widget.repository.deletePoiMedia(item);
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      const PoiEditorSheetResult(action: PoiEditorAction.delete),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestClose();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isNew ? 'Nyt sted' : 'Rediger sted',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Luk',
                  onPressed: _requestClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          if (widget.mappingHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.mappingHint!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          PoiTopicSection(
            topic: PoiTopic.address,
            subtitle: 'Vises når besøgende vælger emnet Adresse',
            child: TextField(
              controller: _houseController,
              decoration: const InputDecoration(
                labelText: 'Adresse',
                hintText: 'fx Friland 36',
              ),
            ),
          ),
          PoiTopicSection(
            topic: PoiTopic.name,
            subtitle: 'Beboere, virksomheder og kaldenavn',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < _occupantControllers.length; index++) ...[
                  TextField(
                    controller: _occupantControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Navn ${index + 1}',
                      hintText: _occupantKinds[index] == PoiOccupantKind.business
                          ? 'fx Solcelle ApS'
                          : 'fx Anna Jensen',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          children: PoiOccupantKind.values.map((kind) {
                            return ChoiceChip(
                              label: Text(kind.label),
                              selected: _occupantKinds[index] == kind,
                              onSelected: (_) {
                                setState(() => _occupantKinds[index] = kind);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      if (_occupantControllers.length > 1)
                        IconButton(
                          tooltip: 'Fjern navn',
                          onPressed: () {
                            setState(() {
                              _occupantControllers[index].dispose();
                              _occupantControllers.removeAt(index);
                              _occupantKinds.removeAt(index);
                            });
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _addOccupantRow());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Tilføj beboer eller virksomhed'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Kaldenavn (valgfri)',
                    hintText: 'fx Hytten',
                  ),
                ),
              ],
            ),
          ),
          PoiTopicSection(
            topic: PoiTopic.info,
            subtitle: 'Beskrivelse, billeder og video',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beskrivelse',
                    hintText: 'fx Blå dør, ring på',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                PoiMediaEditor(
                  eventId: widget.eventId,
                  poiId: _poiId,
                  repository: widget.repository,
                  controller: _mediaController,
                  showAudio: false,
                ),
              ],
            ),
          ),
          PoiTopicSection(
            topic: PoiTopic.audio,
            subtitle: 'Lydfiler som besøgende kan afspille',
            child: PoiMediaEditor(
              eventId: widget.eventId,
              poiId: _poiId,
              repository: widget.repository,
              controller: _mediaController,
              showVisual: false,
            ),
          ),
          TextField(
            controller: _keywordsController,
            decoration: const InputDecoration(
              labelText: 'Ekstra søgeord (valgfrit)',
              hintText: 'fx værksted, gæst, åbningstider',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MapPoi.categories.map((value) {
              return ChoiceChip(
                label: Text(value),
                selected: _category == value,
                onSelected: (_) => setState(() => _category = value),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saveAndClose,
            child: const Text('Gem sted'),
          ),
          if (widget.hasPaths && !widget.hasActiveConnection) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _connectToPath,
              icon: const Icon(Icons.link),
              label: const Text('Kobl til sti'),
            ),
          ],
          if (existing != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  PoiEditorSheetResult(
                    action: PoiEditorAction.movePin,
                    poi: _buildPoi(),
                  ),
                );
              },
              icon: const Icon(Icons.open_with),
              label: const Text('Flyt pin på kortet'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _deletePoi,
              child: const Text('Slet sted'),
            ),
          ],
        ],
      ),
    ),
    );
  }
}

class _PoiFormSnapshot {
  const _PoiFormSnapshot({
    required this.name,
    required this.houseNumber,
    required this.description,
    required this.searchKeywords,
    required this.category,
    required this.occupants,
    required this.mediaIds,
  });

  final String name;
  final String houseNumber;
  final String description;
  final String searchKeywords;
  final String category;
  final List<String> occupants;
  final List<String> mediaIds;

  bool equals(_PoiFormSnapshot other) {
    return name == other.name &&
        houseNumber == other.houseNumber &&
        description == other.description &&
        searchKeywords == other.searchKeywords &&
        category == other.category &&
        _listEquals(occupants, other.occupants) &&
        _listEquals(mediaIds, other.mediaIds);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
