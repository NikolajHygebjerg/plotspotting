import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/routing/treasure_hunt_path_network.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/treasure_hunt_path_network.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_vertex.dart';
import '../../data/models/poi_media.dart';
import '../../data/models/treasure_hunt.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import 'widgets/treasure_hunt_post_editor_sheet.dart';
import 'widgets/treasure_hunt_post_overlay.dart';

enum _TreasureHuntEditorMode {
  posts,
  paths,
}

class TreasureHuntEditorScreen extends StatefulWidget {
  const TreasureHuntEditorScreen({
    super.key,
    required this.eventId,
    required this.mapData,
    required this.onSaved,
  });

  final String eventId;
  final EventMapData mapData;
  final ValueChanged<EventMapData> onSaved;

  @override
  State<TreasureHuntEditorScreen> createState() =>
      _TreasureHuntEditorScreenState();
}

class _TreasureHuntEditorScreenState extends State<TreasureHuntEditorScreen> {
  final _repository = EventRepository();
  final _uuid = const Uuid();
  final _overlayKey = GlobalKey<TreasureHuntPostOverlayState>();
  late final TextEditingController _standaloneTitleController;

  late EventMapData _mapData;
  late List<TreasureHuntConfig> _hunts;
  late String _selectedHuntId;
  late bool _enabled;
  late List<TreasureHuntPost> _posts;
  var _standaloneEnabled = false;
  PoiMedia? _coverImage;
  var _coverUploading = false;

  MapLibreMapController? _mapController;
  String? _selectedPostId;
  String? _movingPostId;
  var _addingPost = false;
  var _saving = false;
  String? _error;
  _TreasureHuntEditorMode _editorMode = _TreasureHuntEditorMode.posts;
  TreasureHuntPathDrawState _pathDrawState = const TreasureHuntPathDrawState(
    vertices: [],
    edges: [],
  );

  TreasureHuntConfig get _currentHunt =>
      _hunts.firstWhere((hunt) => hunt.id == _selectedHuntId);

  List<TreasureHuntPost> get _orderedPosts {
    final copy = List<TreasureHuntPost>.from(_posts);
    copy.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return copy;
  }

  @override
  void initState() {
    super.initState();
    _standaloneTitleController = TextEditingController();
    _mapData = widget.mapData;
    _hunts = List<TreasureHuntConfig>.from(_mapData.treasureHuntCatalog.hunts);
    if (_hunts.isEmpty) {
      _selectedHuntId = '';
      _enabled = false;
      _posts = [];
    } else {
      _selectedHuntId = _hunts.first.id;
      _loadSelectedHunt();
    }
  }

  @override
  void dispose() {
    _standaloneTitleController.dispose();
    super.dispose();
  }

  void _loadSelectedHunt() {
    final hunt = _currentHunt;
    _enabled = hunt.enabled;
    _posts = List<TreasureHuntPost>.from(hunt.posts);
    _standaloneEnabled = hunt.standaloneEnabled;
    _standaloneTitleController.text = hunt.standaloneTitle ?? '';
    _coverImage = hunt.coverImage;
    _pathDrawState = TreasureHuntPathDrawState(
      vertices: List<MapVertex>.from(hunt.pathNetwork.vertices),
      edges: List<MapEdge>.from(hunt.pathNetwork.edges),
    );
    _editorMode = _TreasureHuntEditorMode.posts;
    _selectedPostId = null;
    _movingPostId = null;
    _addingPost = false;
  }

  String? _resolveStandaloneSlug() {
    if (!_standaloneEnabled) return null;
    final title = _standaloneTitleController.text.trim();
    if (title.isEmpty) return _currentHunt.standaloneSlug;
    return TreasureHuntConfig.uniqueStandaloneSlug(
      title: title,
      huntId: _selectedHuntId,
      existingHunts: _hunts,
    );
  }

  void _persistCurrentHunt() {
    if (_selectedHuntId.isEmpty) return;
    final index = _hunts.indexWhere((hunt) => hunt.id == _selectedHuntId);
    if (index < 0) return;
    final standaloneTitle = _standaloneTitleController.text.trim();
    _hunts[index] = _currentHunt.copyWith(
      enabled: _enabled,
      posts: _posts,
      standaloneEnabled: _standaloneEnabled,
      standaloneTitle: standaloneTitle.isEmpty ? null : standaloneTitle,
      standaloneSlug: _resolveStandaloneSlug(),
      coverImage: _coverImage,
      pathNetwork: TreasureHuntPathNetwork(
        vertices: _pathDrawState.vertices,
        edges: _pathDrawState.edges,
      ),
    );
  }

  Future<void> _pickCoverImage() async {
    if (_coverUploading || _selectedHuntId.isEmpty) return;

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _coverUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final uploaded = await _repository.uploadTreasureHuntCover(
        eventId: widget.eventId,
        huntId: _selectedHuntId,
        bytes: bytes,
        fileName: picked.name.isNotEmpty
            ? picked.name
            : picked.path.split('/').last,
      );
      if (!mounted) return;
      setState(() {
        _coverImage = uploaded;
        _coverUploading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _coverUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke uploade billede: $error')),
      );
    }
  }

  Future<void> _removeCoverImage() async {
    final cover = _coverImage;
    if (cover == null) return;
    await _repository.deletePoiMedia(cover);
    if (!mounted) return;
    setState(() => _coverImage = null);
  }

  void _copyStandaloneLink() {
    final slug = _mapData.event.publicSlug;
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publicér kortet først — så får skattejagten et link'),
        ),
      );
      return;
    }

    _persistCurrentHunt();
    final url = _currentHunt.publicUrlForEvent(slug);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Angiv overskrift og mindst én post først')),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link kopieret')),
    );
  }

  Future<String?> _promptHuntTitle({String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _HuntTitleDialog(initial: initial),
    );
  }

  Future<void> _createHunt() async {
    final title = await _promptHuntTitle();
    if (title == null || title.isEmpty || !mounted) return;

    _persistCurrentHunt();
    final hunt = TreasureHuntConfig(
      id: _uuid.v4(),
      title: title,
      enabled: true,
    );

    setState(() {
      _hunts = [..._hunts, hunt];
      _selectedHuntId = hunt.id;
      _enabled = true;
      _posts = [];
      _standaloneEnabled = false;
      _standaloneTitleController.clear();
      _coverImage = null;
      _selectedPostId = null;
      _movingPostId = null;
      _addingPost = false;
    });
  }

  void _switchHunt(String huntId) {
    if (huntId == _selectedHuntId) return;
    _persistCurrentHunt();
    setState(() {
      _selectedHuntId = huntId;
      _loadSelectedHunt();
    });
    _overlayKey.currentState?.updatePositions();
  }

  Future<void> _renameCurrentHunt() async {
    final title = await _promptHuntTitle(initial: _currentHunt.title);
    if (title == null || title.isEmpty) return;
    _persistCurrentHunt();
    setState(() {
      final index = _hunts.indexWhere((hunt) => hunt.id == _selectedHuntId);
      if (index >= 0) {
        _hunts[index] = _hunts[index].copyWith(title: title);
      }
    });
  }

  TreasureHuntPost? _findNearestPost(double lat, double lng) {
    TreasureHuntPost? nearest;
    var best = AppConstants.poiTapMaxMeters;
    for (final post in _posts) {
      final distance = haversineMeters(lat, lng, post.lat, post.lng);
      if (distance <= best) {
        best = distance;
        nearest = post;
      }
    }
    return nearest;
  }

  Future<void> _openPostEditor({
    required TreasureHuntPost? existing,
    required double lat,
    required double lng,
    required bool isNew,
  }) async {
    final result = await TreasureHuntPostEditorSheet.show(
      context,
      eventId: widget.eventId,
      repository: _repository,
      existing: existing,
      lat: lat,
      lng: lng,
      isNew: isNew,
      otherPosts: _posts.where((post) => post.id != existing?.id).toList(),
      sortOrder: existing?.sortOrder ?? _posts.length,
    );

    if (!mounted || result == null) return;

    switch (result.action) {
      case TreasureHuntPostEditorAction.cancel:
        return;
      case TreasureHuntPostEditorAction.movePin:
        if (existing != null) {
          setState(() {
            _movingPostId = existing.id;
            _selectedPostId = existing.id;
            _addingPost = false;
          });
        }
        return;
      case TreasureHuntPostEditorAction.delete:
        if (existing != null) {
          setState(() {
            _posts = _posts.where((post) => post.id != existing.id).toList();
            for (final post in _posts) {
              if (post.nextPostId == existing.id) {
                final index = _posts.indexWhere((entry) => entry.id == post.id);
                if (index >= 0) {
                  _posts[index] = post.copyWith(clearNextPostId: true);
                }
              }
            }
            _selectedPostId = null;
            _movingPostId = null;
          });
          _overlayKey.currentState?.updatePositions();
        }
        return;
      case TreasureHuntPostEditorAction.save:
        final post = result.post;
        if (post == null) return;
        setState(() {
          final index = _posts.indexWhere((entry) => entry.id == post.id);
          if (index >= 0) {
            _posts[index] = post;
          } else {
            _posts = [..._posts, post];
          }
          _selectedPostId = post.id;
          _movingPostId = null;
          _addingPost = false;
        });
        _overlayKey.currentState?.updatePositions();
        return;
    }
  }

  void _handleMapTap(LatLng coordinate) {
    if (_editorMode == _TreasureHuntEditorMode.paths) {
      setState(() {
        _pathDrawState = addTreasureHuntPathPoint(
          state: _pathDrawState,
          lat: coordinate.latitude,
          lng: coordinate.longitude,
          officialVertices: _mapData.vertices,
          newVertexId: () => 'hv-${_uuid.v4()}',
          newEdgeId: () => 'he-${_uuid.v4()}',
        );
      });
      return;
    }

    unawaited(_handleMapTapAsync(coordinate));
  }

  Future<void> _handleMapTapAsync(LatLng coordinate) async {
    if (_editorMode != _TreasureHuntEditorMode.posts) return;
    final lat = coordinate.latitude;
    final lng = coordinate.longitude;
    if (_selectedHuntId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opret en skattejagt først')),
      );
      return;
    }

    if (_movingPostId != null) {
      final index = _posts.indexWhere((post) => post.id == _movingPostId);
      if (index >= 0) {
        setState(() {
          _posts[index] = _posts[index].copyWith(lat: lat, lng: lng);
          _movingPostId = null;
        });
        _overlayKey.currentState?.updatePositions();
      }
      return;
    }

    final tapped = _findNearestPost(lat, lng);
    if (tapped != null && !_addingPost) {
      await _openPostEditor(
        existing: tapped,
        lat: tapped.lat,
        lng: tapped.lng,
        isNew: false,
      );
      return;
    }

    if (_addingPost) {
      await _openPostEditor(
        existing: null,
        lat: lat,
        lng: lng,
        isNew: true,
      );
    }
  }

  void _handlePostTapped(TreasureHuntPost post) {
    unawaited(
      _openPostEditor(
        existing: post,
        lat: post.lat,
        lng: post.lng,
        isNew: false,
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedHuntId.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    _persistCurrentHunt();
    final metadata = {
      ..._mapData.event.metadata,
      ...TreasureHuntCatalog(_hunts).toEventMetadata(),
    };

    try {
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
        const SnackBar(content: Text('Skattejagt gemt')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hunts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Skattejagt')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Opret en skattejagt',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Placer poster på kortet med tekst, billeder, video og lyd — og vælg næste post når du er klar.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _createHunt,
                  icon: const Icon(Icons.add),
                  label: const Text('Ny skattejagt'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final orderedPosts = _orderedPosts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skattejagt'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Gem')),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text('Kunne ikke gemme: $_error'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Luk'),
                ),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                EventMapWidget(
                  data: _mapData,
                  showIllustratedBasemap: true,
                  showEventPaths: true,
                  showPathVertices: _editorMode == _TreasureHuntEditorMode.paths,
                  showPoiMarkers: false,
                  overlayEdges: _pathDrawState.edges,
                  onMapTap: _handleMapTap,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    setState(() {});
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _overlayKey.currentState?.updatePositions();
                    });
                  },
                ),
                if (_mapController != null &&
                    _editorMode == _TreasureHuntEditorMode.posts)
                  TreasureHuntPostOverlay(
                    key: _overlayKey,
                    controller: _mapController!,
                    posts: orderedPosts,
                    selectedPostId: _selectedPostId,
                    onPostTapped: _handlePostTapped,
                  ),
                if (_addingPost || _movingPostId != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.amber.shade800,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          _movingPostId != null
                              ? 'Tryk hvor posten skal stå'
                              : 'Tryk på kortet for at placere en ny post',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                      ),
                    ),
                  ),
                if (_editorMode == _TreasureHuntEditorMode.paths)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFF9A825),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Tegn jagtstier (gule) — de bruges kun i skattejagten',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.black87,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.48,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_selectedHuntId),
                          initialValue: _selectedHuntId,
                          decoration: const InputDecoration(
                            labelText: 'Skattejagt',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items: [
                            for (final hunt in _hunts)
                              DropdownMenuItem(
                                value: hunt.id,
                                child: Text(hunt.displayTitle),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) _switchHunt(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Omdøb',
                        onPressed: _renameCurrentHunt,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Ny skattejagt',
                        onPressed: _createHunt,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_TreasureHuntEditorMode>(
                    segments: const [
                      ButtonSegment(
                        value: _TreasureHuntEditorMode.posts,
                        icon: Icon(Icons.flag_outlined),
                        label: Text('Poster'),
                      ),
                      ButtonSegment(
                        value: _TreasureHuntEditorMode.paths,
                        icon: Icon(Icons.route_outlined),
                        label: Text('Jagtstier'),
                      ),
                    ],
                    selected: {_editorMode},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _editorMode = selection.first;
                        _addingPost = false;
                        _movingPostId = null;
                      });
                    },
                  ),
                  if (_editorMode == _TreasureHuntEditorMode.paths) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_pathDrawState.edges.length} jagtsti${_pathDrawState.edges.length == 1 ? '' : 'er'} · officielle stier vises i blå/orange',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final undone = undoTreasureHuntPathPoint(_pathDrawState);
                            if (undone == null) return;
                            setState(() => _pathDrawState = undone);
                          },
                          icon: const Icon(Icons.undo),
                          label: const Text('Fortryd'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktiv for gæster'),
                    subtitle: Text(
                      _enabled
                          ? '${orderedPosts.length} post${orderedPosts.length == 1 ? '' : 'er'} på kortet'
                          : 'Skattejagten er skjult indtil den aktiveres',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Del som selvstændig hjemmeside'),
                    subtitle: const Text(
                      'Egen side med overskrift og billede — uafhængigt af kortet',
                    ),
                    value: _standaloneEnabled,
                    onChanged: (value) => setState(() => _standaloneEnabled = value),
                  ),
                  if (_standaloneEnabled) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _standaloneTitleController,
                      decoration: const InputDecoration(
                        labelText: 'Overskrift',
                        hintText: 'Fx «Familiens skattejagt»',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Illustrationsbillede',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_coverImage != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Image.network(
                            _coverImage!.url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        child: const Center(
                          child: Icon(Icons.image_outlined, size: 40),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _coverUploading ? null : _pickCoverImage,
                            icon: _coverUploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_outlined),
                            label: Text(_coverImage == null ? 'Upload billede' : 'Skift billede'),
                          ),
                        ),
                        if (_coverImage != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Fjern billede',
                            onPressed: _removeCoverImage,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_mapData.event.publicSlug != null &&
                        _standaloneTitleController.text.trim().isNotEmpty)
                      SelectableText(
                        AppConstants.treasureHuntPublicUrl(
                          eventSlug: _mapData.event.publicSlug!,
                          huntSlug: _resolveStandaloneSlug() ?? _selectedHuntId,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      Text(
                        'Publicér kortet for at få et delbart link',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _copyStandaloneLink,
                      icon: const Icon(Icons.link),
                      label: const Text('Kopiér link'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _editorMode == _TreasureHuntEditorMode.paths
                              ? null
                              : () => setState(() {
                                    _addingPost = !_addingPost;
                                    _movingPostId = null;
                                  }),
                          icon: Icon(
                            _addingPost ? Icons.close : Icons.add_location_alt,
                          ),
                          label: Text(
                            _addingPost ? 'Annuller placering' : 'Tilføj post',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (orderedPosts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Poster',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: orderedPosts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final post = orderedPosts[index];
                          final selected = post.id == _selectedPostId;
                          return SizedBox(
                            width: 180,
                            child: Card(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.45)
                                  : null,
                              child: InkWell(
                                onTap: () => _handlePostTapped(post),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${index + 1}. ${post.displayTitle}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const Spacer(),
                                      if (post.hasNextPost)
                                        Text(
                                          'Næste: ${_currentHunt.postById(post.nextPostId!)?.displayTitle ?? '…'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        )
                                      else
                                        Text(
                                          'Næste post: vælg senere',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _HuntTitleDialog extends StatefulWidget {
  const _HuntTitleDialog({this.initial});

  final String? initial;

  @override
  State<_HuntTitleDialog> createState() => _HuntTitleDialogState();
}

class _HuntTitleDialogState extends State<_HuntTitleDialog> {
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
      title: const Text('Navn på skattejagt'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Fx «Familie skattejagt»',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
