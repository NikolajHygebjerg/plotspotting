import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import 'widgets/audio_tour_stop_record_sheet.dart';
import 'widgets/audio_tour_wander_record_sheet.dart';

class AudioTourWalkScreen extends StatefulWidget {
  const AudioTourWalkScreen({
    super.key,
    required this.eventId,
    required this.mapData,
    required this.tour,
    required this.onSaved,
  });

  final String eventId;
  final EventMapData mapData;
  final AudioTourConfig tour;
  final ValueChanged<EventMapData> onSaved;

  @override
  State<AudioTourWalkScreen> createState() => _AudioTourWalkScreenState();
}

class _AudioTourWalkScreenState extends State<AudioTourWalkScreen> {
  final _repository = EventRepository();
  final _uuid = const Uuid();

  late EventMapData _data;
  late List<AudioTourItem> _items;
  bool _enabled = true;
  bool _isRecording = false;
  bool _saving = false;
  String? _error;
  StreamSubscription<Position>? _positionSub;
  Position? _currentPosition;
  ll.LatLng? _mapCenter;
  String? _lastVertexId;

  @override
  void initState() {
    super.initState();
    _data = widget.mapData;
    _enabled = widget.tour.enabled || widget.tour.items.isEmpty;
    _items = List<AudioTourItem>.from(widget.tour.items);
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _ensureLocationPermission();
    await _startLocationStream();
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> _startLocationStream() async {
    if (!await _ensureLocationPermission()) return;

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      ),
    ).listen(_onGpsUpdate);

    final current = await Geolocator.getCurrentPosition();
    _onGpsUpdate(current);
  }

  void _onGpsUpdate(Position position) {
    _currentPosition = position;
    _mapCenter = ll.LatLng(position.latitude, position.longitude);

    if (!_isRecording) {
      if (mounted) setState(() {});
      return;
    }

    if (_lastVertexId == null) {
      _addPathPoint(position.latitude, position.longitude);
      if (mounted) setState(() {});
      return;
    }

    final lastIndex = _data.vertices.indexWhere((v) => v.id == _lastVertexId);
    if (lastIndex < 0) {
      _lastVertexId = null;
      _addPathPoint(position.latitude, position.longitude);
      if (mounted) setState(() {});
      return;
    }
    final last = _data.vertices[lastIndex];
    final dist = haversineMeters(
      position.latitude,
      position.longitude,
      last.lat,
      last.lng,
    );
    if (dist >= AppConstants.recordingMinStepMeters) {
      _addPathPoint(position.latitude, position.longitude);
      if (mounted) setState(() {});
    }
  }

  void _addPathPoint(double lat, double lng) {
    final vertices = List<MapVertex>.from(_data.vertices);
    final edges = List<MapEdge>.from(_data.edges);

    final snapped = findNearestVertex(
      lat: lat,
      lng: lng,
      vertices: vertices,
      maxDistanceMeters: AppConstants.pathDrawSnapMeters,
    );
    final vertex = snapped ??
        MapVertex(
          id: _uuid.v4(),
          lat: lat,
          lng: lng,
        );

    if (snapped == null) {
      vertices.add(vertex);
    }

    if (_lastVertexId != null && _lastVertexId != vertex.id) {
      final fromIndex = vertices.indexWhere((v) => v.id == _lastVertexId);
      if (fromIndex < 0) {
        _lastVertexId = vertex.id;
        if (mounted) setState(() {});
        return;
      }
      final from = vertices[fromIndex];
      final geometry = [
        ll.LatLng(from.lat, from.lng),
        ll.LatLng(vertex.lat, vertex.lng),
      ];
      edges.add(
        MapEdge(
          id: _uuid.v4(),
          fromId: _lastVertexId!,
          toId: vertex.id,
          geometry: geometry,
          lengthMeters: polylineLengthMeters(geometry),
        ),
      );
    }

    _lastVertexId = vertex.id;
    _data = _data.copyWith(vertices: vertices, edges: edges);
  }

  String _ensurePathVertexAt(double lat, double lng) {
    if (_lastVertexId != null) {
      final lastIndex = _data.vertices.indexWhere((v) => v.id == _lastVertexId);
      if (lastIndex < 0) {
        _lastVertexId = null;
        _addPathPoint(lat, lng);
        return _lastVertexId!;
      }
      final last = _data.vertices[lastIndex];
      final dist = haversineMeters(lat, lng, last.lat, last.lng);
      if (dist >= 2) {
        _addPathPoint(lat, lng);
      }
      return _lastVertexId!;
    }

    _addPathPoint(lat, lng);
    return _lastVertexId!;
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() => _isRecording = false);
      return;
    }

    if (!await _ensureLocationPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giv adgang til GPS for at optage stien')),
      );
      return;
    }

    setState(() => _isRecording = true);

    final pos = _currentPosition ?? await Geolocator.getCurrentPosition();
    if (_lastVertexId == null) {
      _addPathPoint(pos.latitude, pos.longitude);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addStopAtPoi(MapPoi poi) async {
    final accessVertexId = findNearestVertexId(
      lat: poi.lat,
      lng: poi.lng,
      vertices: _data.vertices,
      maxDistanceMeters: AppConstants.routingSnapMaxMeters,
    );

    final result = await AudioTourStopRecordSheet.show(
      context,
      eventId: widget.eventId,
      repository: _repository,
      allPois: _data.pois,
      lat: poi.lat,
      lng: poi.lng,
      accessVertexId: accessVertexId,
      preselectedPoi: poi,
    );

    if (result == null || !mounted) return;
    _applyStopResult(result);
  }

  Future<void> _addStopAtCurrentLocation() async {
    final pos = _currentPosition;
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venter på GPS-signal…')),
      );
      return;
    }

    final accessVertexId = _ensurePathVertexAt(pos.latitude, pos.longitude);
    if (mounted) setState(() {});

    final result = await AudioTourStopRecordSheet.show(
      context,
      eventId: widget.eventId,
      repository: _repository,
      allPois: _data.pois,
      lat: pos.latitude,
      lng: pos.longitude,
      accessVertexId: accessVertexId,
    );

    if (result == null || !mounted) return;
    _applyStopResult(result);
  }

  void _applyStopResult(AudioTourStopRecordResult result) {
    final pois = List<MapPoi>.from(_data.pois);
    if (result.isNew) {
      pois.add(result.poi);
    } else {
      final index = pois.indexWhere((p) => p.id == result.poi.id);
      if (index >= 0) {
        pois[index] = result.poi;
      } else {
        pois.add(result.poi);
      }
    }

    setState(() {
      _data = _data.copyWith(pois: pois);
      _items = [
        ..._items,
        AudioTourItem.poi(poiId: result.poi.id, audioId: result.audioId),
      ];
      _enabled = true;
    });
  }

  Future<void> _addWanderClip() async {
    final clip = await AudioTourWanderRecordSheet.show(
      context,
      eventId: widget.eventId,
      repository: _repository,
    );

    if (clip == null || !mounted) return;
    setState(() {
      _items = [..._items, AudioTourItem.wander(wander: clip)];
      _enabled = true;
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tilføj mindst ét stop med fortælling')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final updatedTour = AudioTourConfig(
      id: widget.tour.id,
      title: widget.tour.title,
      enabled: _enabled,
      items: _items,
    );
    final catalog = AudioTourCatalog.fromEventMetadata(_data.event.metadata);
    final tours = [
      for (final tour in catalog.tours)
        if (tour.id == updatedTour.id) updatedTour else tour,
    ];
    if (!tours.any((tour) => tour.id == updatedTour.id)) {
      tours.add(updatedTour);
    }
    final metadata = {
      ..._data.event.metadata,
      ...AudioTourCatalog(tours).toEventMetadata(),
    };
    metadata.remove('audio_tour');

    try {
      await _repository.saveGraph(
        eventId: widget.eventId,
        vertices: _data.vertices,
        edges: _data.edges,
        pois: _data.pois,
        centerLat: _mapCenter?.latitude ?? _data.event.centerLat,
        centerLng: _mapCenter?.longitude ?? _data.event.centerLng,
      );
      await _repository.saveMetadata(
        eventId: widget.eventId,
        metadata: metadata,
      );

      if (!mounted) return;
      final updated = _data.copyWith(
        event: _data.event.copyWith(metadata: metadata),
      );
      widget.onSaved(updated);
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

  String _itemLabel(AudioTourItem item, int index) {
    if (item.kind == AudioTourItemKind.wander) {
      return item.wander?.title ?? 'Vandrelyd';
    }
    final poi = _data.poiById(item.poiId!);
    final label = poi?.displayTitle ?? 'Sted';
    final isFirstPoi =
        !_items.take(index).any((entry) => entry.kind == AudioTourItemKind.poi);
    return isFirstPoi ? 'Start: $label' : label;
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isRecording
        ? 'Optager sti… gå ruten og tryk «Fortælling her» ved hvert stop'
        : 'Tryk «Start gåtur» og gå ruten fysisk';

    return Scaffold(
      appBar: AppBar(
        title: Text('Lydvandring — ${widget.tour.displayTitle}'),
        actions: [
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
            TextButton(onPressed: _save, child: const Text('Gem')),
        ],
      ),
      body: Stack(
        children: [
          EventMapWidget(
            data: _data,
            initialCenter: _mapCenter,
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.tracking,
            showIllustratedBasemap: _data.event.hasIllustratedBasemap,
            onPoiTapped: (poi) => _addStopAtPoi(poi),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(statusText, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
          ),
          if (_items.isNotEmpty)
            Positioned(
              top: 72,
              right: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.headphones, size: 18, color: Colors.purple.shade700),
                      const SizedBox(width: 6),
                      Text('${_items.length} elementer'),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              top: 72,
              left: 12,
              right: 12,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_items.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Chip(
                                avatar: Icon(
                                  item.kind == AudioTourItemKind.wander
                                      ? Icons.directions_walk
                                      : Icons.place,
                                  size: 18,
                                ),
                                label: Text(_itemLabel(item, index)),
                              );
                            },
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _toggleRecording,
                            icon: Icon(_isRecording ? Icons.stop : Icons.directions_walk),
                            label: Text(_isRecording ? 'Stop gåtur' : 'Start gåtur'),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  _isRecording ? Colors.red.shade700 : null,
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addStopAtCurrentLocation,
                            icon: const Icon(Icons.mic),
                            label: const Text('Fortælling'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _addWanderClip,
                        icon: const Icon(Icons.directions_walk),
                        label: const Text('Vandrelyd imellem stop'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      ),
                    ),
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
