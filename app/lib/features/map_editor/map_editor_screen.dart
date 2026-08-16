import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../map_setup/basemap_alignment_screen.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/storage/organizer_session_persistence.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_bounds.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import '../area_setup/area_setup_screen.dart';
import '../publish/publish_screen.dart';
import 'audio_tour_editor_screen.dart';
import 'treasure_hunt_editor_screen.dart';
import 'mapping_method.dart';
import 'poi_path_connection.dart';
import 'widgets/poi_connections_panel.dart';
import 'widgets/poi_editor_sheet.dart';

class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.initialData,
  });

  final String eventId;
  final String eventName;
  final EventMapData? initialData;

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final _repository = EventRepository();
  final _uuid = const Uuid();

  late EventMapData _data;
  MappingMethod? _mappingMethod;
  EditorMode _mode = EditorMode.drawPath;
  bool _isRecording = false;
  StreamSubscription<Position>? _positionSub;
  Position? _currentPosition;
  String? _lastVertexId;
  final List<String> _pathStrokeVertexIds = [];
  String? _selectedPoiId;
  String? _selectedVertexId;
  String? _movingPoiId;
  String? _movingVertexId;
  String? _pendingConnectFromId;
  bool _suppressNextMapTap = false;
  bool _loading = true;
  bool _saving = false;
  bool _showIllustratedBasemap = true;
  bool _previewIllustratedWhileDrawing = false;
  String? _error;
  ll.LatLng? _mapCenter;
  PoiPathConnectionDraft? _poiConnectionDraft;
  BulkPoiPathConnectionPlan? _bulkConnectionPlan;
  EditorSection _section = EditorSection.routes;

  bool get _inConnectionsFlow =>
      _mode == EditorMode.editConnections ||
      _mode == EditorMode.connectPoiToPath;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ??
        EventMapData(
          event: EventMeta(
            id: widget.eventId,
            name: widget.eventName,
          ),
        );
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.initialData == null) {
        _data = await _repository.loadForEdit(eventId: widget.eventId);
        await persistOrganizerSession(
          eventId: widget.eventId,
          eventName: _data.event.name,
          publicSlug: _data.event.publicSlug,
        );
      }
      _data = _repairMapConnections(_data);
      if (_data.vertices.isEmpty && _data.pois.isEmpty) {
        _mappingMethod = null;
      } else {
        _mappingMethod = MappingMethod.draw;
        _previewIllustratedWhileDrawing = false;
      }
      await _ensureLocationPermission();
      if (_mappingMethod == MappingMethod.walk) {
        await _startLocationStream();
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      _mapCenter = ll.LatLng(position.latitude, position.longitude);
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

    setState(() {
      _mode = EditorMode.drawPath;
      _isRecording = true;
      _movingPoiId = null;
    });

    final pos = _currentPosition ?? await Geolocator.getCurrentPosition();
    if (_lastVertexId == null) {
      _addPathPoint(pos.latitude, pos.longitude);
      if (mounted) setState(() {});
    }
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      await _repository.saveGraph(
        eventId: widget.eventId,
        vertices: _data.vertices,
        edges: _data.edges,
        pois: _data.pois,
        centerLat: _mapCenter?.latitude ?? _data.event.centerLat,
        centerLng: _mapCenter?.longitude ?? _data.event.centerLng,
      );
      await persistOrganizerSession(
        eventId: widget.eventId,
        eventName: _data.event.name,
        publicSlug: _data.event.publicSlug,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kort gemt')),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke gemme: $error')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finishPath() {
    setState(() {
      _lastVertexId = null;
      _pathStrokeVertexIds.clear();
      _selectedVertexId = null;
      _movingVertexId = null;
      _pendingConnectFromId = null;
    });
  }

  bool get _canUndoPathPoint =>
      _mode == EditorMode.drawPath &&
      (_pathStrokeVertexIds.isNotEmpty || _lastVertexId != null);

  void _undo() {
    if (_canUndoPathPoint) {
      _undoLastPathPoint();
      return;
    }

    setState(() {
      if (_data.pois.isNotEmpty) {
        final pois = List<MapPoi>.from(_data.pois)..removeLast();
        final removed = _data.pois.last;
        _data = _data.copyWith(pois: pois);
        if (_selectedPoiId == removed.id) {
          _selectedPoiId = null;
        }
      }
    });
  }

  void _undoLastPathPoint() {
    if (!_canUndoPathPoint) return;

    setState(() {
      final removedId = _pathStrokeVertexIds.isNotEmpty
          ? _pathStrokeVertexIds.removeLast()
          : _lastVertexId;
      if (removedId == null) return;

      final previousId =
          _pathStrokeVertexIds.isNotEmpty ? _pathStrokeVertexIds.last : null;

      var edges = List<MapEdge>.from(_data.edges);
      if (previousId != null) {
        edges.removeWhere((edge) => edge.fromId == previousId && edge.toId == removedId);
      } else {
        edges.removeWhere((edge) => edge.toId == removedId || edge.fromId == removedId);
      }

      var vertices = List<MapVertex>.from(_data.vertices);
      final stillConnected = edges.any(
        (edge) => edge.fromId == removedId || edge.toId == removedId,
      );
      if (!stillConnected) {
        vertices.removeWhere((vertex) => vertex.id == removedId);
      }

      final pois = _data.pois.map((poi) {
        if (poi.accessVertexId != removedId) {
          final poiVertexId = findPoiVertexId(poi: poi, vertices: vertices);
          if (poiVertexId != removedId) return poi;
        }
        return poi.copyWith(clearAccessVertexId: true);
      }).toList();

      _lastVertexId = previousId;
      if (_selectedVertexId == removedId) {
        _selectedVertexId = null;
      }
      if (_movingVertexId == removedId) {
        _movingVertexId = null;
      }

      _data = _data.copyWith(vertices: vertices, edges: edges, pois: pois);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sidste punkt fjernet')),
    );
  }

  void _handleMapTap(LatLng coordinate) {
    if (_suppressNextMapTap) {
      _suppressNextMapTap = false;
      return;
    }

    final lat = coordinate.latitude;
    final lng = coordinate.longitude;
    _mapCenter = ll.LatLng(lat, lng);

    if (_movingVertexId != null) {
      _moveVertex(_movingVertexId!, lat, lng);
      setState(() {
        _movingVertexId = null;
      });
      return;
    }

    if (_movingPoiId != null) {
      _movePoi(_movingPoiId!, lat, lng);
      setState(() {
        _movingPoiId = null;
      });
      return;
    }

    if (_section == EditorSection.map ||
        _section == EditorSection.audioTour ||
        _section == EditorSection.treasureHunt) {
      return;
    }

    switch (_mode) {
      case EditorMode.connectPoiToPath:
        _adjustPoiConnectionAt(lat, lng);
        setState(() {});
        return;
      case EditorMode.drawPath:
        if (_section != EditorSection.routes) return;
        final tappedVertex = findNearestVertex(
          lat: lat,
          lng: lng,
          vertices: _data.vertices,
          maxDistanceMeters: AppConstants.vertexTapMaxMeters,
        );
        if (tappedVertex != null) {
          _handleVertexTapInDrawMode(tappedVertex);
          return;
        }
        _selectedVertexId = null;
        _movingVertexId = null;
        _addPathPoint(lat, lng);
        setState(() {});
        return;
      case EditorMode.addPlace:
        if (_section != EditorSection.places) return;
        _addPlaceAtMapLocation(lat, lng);
        return;
      case EditorMode.editPlace:
        if (_section != EditorSection.places) return;
        final poi = findNearestPoi(lat: lat, lng: lng, pois: _data.pois);
        if (poi != null) {
          _selectPoi(poi);
        }
        setState(() {});
        return;
      case EditorMode.editConnections:
        if (_section != EditorSection.routes) return;
        final spurHit = findPoiSpurNearTap(
          lat: lat,
          lng: lng,
          pois: _data.pois,
          vertices: _data.vertices,
          edges: _data.edges,
        );
        if (spurHit != null) {
          unawaited(_offerMovePoiConnection(spurHit.poi));
          return;
        }
        final connectionPoi = findNearestPoi(lat: lat, lng: lng, pois: _data.pois);
        if (connectionPoi != null) {
          unawaited(_handlePoiConnectionTap(connectionPoi));
        }
        setState(() {});
        return;
    }
  }

  void _continuePathFromVertex(MapVertex vertex) {
    setState(() {
      _selectedVertexId = vertex.id;
      _selectedPoiId = null;
      _movingVertexId = null;
      _pendingConnectFromId = null;
      _lastVertexId = vertex.id;
      if (!_pathStrokeVertexIds.contains(vertex.id)) {
        _pathStrokeVertexIds.add(vertex.id);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tegner videre fra punkt — tryk på kortet for næste punkt. '
          'Tryk på punktet igen for at flytte eller slette.',
        ),
      ),
    );
  }

  void _handleVertexTapInDrawMode(MapVertex vertex) {
    _showVertexEditSheet(vertex);
  }

  bool _canClosePathAt(MapVertex vertex) => _shouldClosePathAtStart(vertex);

  bool _canConnectToVertex(MapVertex vertex) {
    if (_lastVertexId != null && _lastVertexId != vertex.id) return true;
    if (_pendingConnectFromId != null && _pendingConnectFromId != vertex.id) {
      return true;
    }
    return false;
  }

  String _connectActionLabel(MapVertex vertex) {
    if (_lastVertexId != null && _lastVertexId != vertex.id) {
      return 'Kobl til aktiv sti';
    }
    if (_pendingConnectFromId != null && _pendingConnectFromId != vertex.id) {
      return 'Kobl til valgt punkt';
    }
    return 'Vælg som udgangspunkt for kobling';
  }

  void _connectVertices(String fromId, String toId, {bool continueFromTarget = true}) {
    if (fromId == toId) return;

    setState(() {
      final alreadyConnected = _data.edges.any(
        (edge) =>
            (edge.fromId == fromId && edge.toId == toId) ||
            (edge.fromId == toId && edge.toId == fromId),
      );

      if (!alreadyConnected) {
        final from = _data.vertices.firstWhere((vertex) => vertex.id == fromId);
        final to = _data.vertices.firstWhere((vertex) => vertex.id == toId);
        final geometry = [
          ll.LatLng(from.lat, from.lng),
          ll.LatLng(to.lat, to.lng),
        ];
        final edges = List<MapEdge>.from(_data.edges)
          ..add(
            MapEdge(
              id: _uuid.v4(),
              fromId: fromId,
              toId: toId,
              geometry: geometry,
              lengthMeters: polylineLengthMeters(geometry),
            ),
          );
        _data = _data.copyWith(edges: edges);
      }

      _pendingConnectFromId = null;
      if (continueFromTarget) {
        _lastVertexId = toId;
        _selectedVertexId = toId;
        if (!_pathStrokeVertexIds.contains(fromId)) {
          _pathStrokeVertexIds.add(fromId);
        }
        if (!_pathStrokeVertexIds.contains(toId)) {
          _pathStrokeVertexIds.add(toId);
        }
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Punkter koblet sammen')),
    );
  }

  void _handleConnectAction(MapVertex vertex) {
    if (_lastVertexId != null && _lastVertexId != vertex.id) {
      _connectVertices(_lastVertexId!, vertex.id);
      return;
    }

    if (_pendingConnectFromId != null && _pendingConnectFromId != vertex.id) {
      _connectVertices(_pendingConnectFromId!, vertex.id);
      return;
    }

    setState(() {
      _pendingConnectFromId = vertex.id;
      _selectedVertexId = vertex.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tryk på et andet punkt og vælg «Kobl til valgt punkt»'),
      ),
    );
  }

  bool _shouldClosePathAtStart(MapVertex vertex) {
    if (_lastVertexId == null || _pathStrokeVertexIds.length < 2) {
      return false;
    }
    final startId = _pathStrokeVertexIds.first;
    return vertex.id == startId && _lastVertexId != startId;
  }

  void _closePathLoop() {
    final startId = _pathStrokeVertexIds.first;
    final lastId = _lastVertexId;
    if (lastId == null || lastId == startId || _pathStrokeVertexIds.length < 2) {
      return;
    }

    setState(() {
      final alreadyConnected = _data.edges.any(
        (edge) =>
            (edge.fromId == lastId && edge.toId == startId) ||
            (edge.fromId == startId && edge.toId == lastId),
      );

      if (!alreadyConnected) {
        final from = _data.vertices.firstWhere((vertex) => vertex.id == lastId);
        final to = _data.vertices.firstWhere((vertex) => vertex.id == startId);
        final geometry = [
          ll.LatLng(from.lat, from.lng),
          ll.LatLng(to.lat, to.lng),
        ];
        final edges = List<MapEdge>.from(_data.edges)
          ..add(
            MapEdge(
              id: _uuid.v4(),
              fromId: lastId,
              toId: startId,
              geometry: geometry,
              lengthMeters: polylineLengthMeters(geometry),
            ),
          );
        _data = _data.copyWith(edges: edges);
      }

      _lastVertexId = null;
      _pathStrokeVertexIds.clear();
      _selectedVertexId = null;
      _movingVertexId = null;
      _pendingConnectFromId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rute lukket — tryk på et punkt for at tegne videre'),
      ),
    );
  }

  void _showVertexEditSheet(MapVertex vertex) {
    setState(() {
      _selectedVertexId = vertex.id;
      _selectedPoiId = null;
      _movingVertexId = null;
    });
    _showVertexSheet(vertex);
  }

  Future<void> _showVertexSheet(MapVertex vertex) async {
    final canConnect = _canConnectToVertex(vertex);
    final canClose = _canClosePathAt(vertex);
    final isPendingConnectSource = _pendingConnectFromId == vertex.id;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Stipunkt'),
                subtitle: Text(
                  isPendingConnectSource
                      ? 'Valgt som udgangspunkt — tryk på et andet punkt'
                      : vertex.label?.isNotEmpty == true
                          ? vertex.label!
                          : '${vertex.lat.toStringAsFixed(5)}, ${vertex.lng.toStringAsFixed(5)}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(_connectActionLabel(vertex)),
                subtitle: Text(
                  canConnect
                      ? 'Opret sti mellem punkterne'
                      : 'Vælg dette punkt først, tryk derefter på et andet',
                ),
                onTap: () => Navigator.pop(context, 'connect'),
              ),
              if (canClose)
                ListTile(
                  leading: const Icon(Icons.all_inclusive),
                  title: const Text('Luk rute'),
                  subtitle: const Text('Forbind tilbage til startpunktet'),
                  onTap: () => Navigator.pop(context, 'close'),
                ),
              ListTile(
                leading: const Icon(Icons.timeline),
                title: const Text('Tegn videre herfra'),
                subtitle: const Text('Næste tryk på kortet fortsætter stien fra dette punkt'),
                onTap: () => Navigator.pop(context, 'continue'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_with),
                title: const Text('Flyt punkt'),
                onTap: () => Navigator.pop(context, 'move'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Slet punkt', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    switch (action) {
      case 'connect':
        _handleConnectAction(vertex);
      case 'close':
        _closePathLoop();
      case 'continue':
        _continuePathFromVertex(vertex);
      case 'move':
        setState(() {
          _selectedVertexId = vertex.id;
          _movingVertexId = vertex.id;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Træk punktet eller tryk på kortet hvor det skal flyttes hen'),
          ),
        );
      case 'delete':
        setState(() => _deleteVertex(vertex.id));
    }
  }

  void _deleteVertex(String vertexId) {
    final vertices =
        _data.vertices.where((vertex) => vertex.id != vertexId).toList();
    final edges = _data.edges
        .where((edge) => edge.fromId != vertexId && edge.toId != vertexId)
        .toList();
    final pois = _data.pois.map((poi) {
      if (poi.accessVertexId != vertexId) {
        final poiVertexId = findPoiVertexId(poi: poi, vertices: vertices);
        if (poiVertexId != vertexId) return poi;
      }
      return poi.copyWith(clearAccessVertexId: true);
    }).toList();

    if (_lastVertexId == vertexId) {
      _lastVertexId =
          _pathStrokeVertexIds.isNotEmpty ? _pathStrokeVertexIds.last : null;
    }
    _pathStrokeVertexIds.remove(vertexId);
    if (_selectedVertexId == vertexId) {
      _selectedVertexId = null;
    }
    if (_movingVertexId == vertexId) {
      _movingVertexId = null;
    }
    if (_pendingConnectFromId == vertexId) {
      _pendingConnectFromId = null;
    }

    _data = _data.copyWith(vertices: vertices, edges: edges, pois: pois);
  }

  void _moveVertex(String vertexId, double lat, double lng) {
    final vertices = List<MapVertex>.from(_data.vertices);
    final index = vertices.indexWhere((vertex) => vertex.id == vertexId);
    if (index < 0) return;

    vertices[index] = vertices[index].copyWith(lat: lat, lng: lng);

    final edges = _data.edges.map((edge) {
      if (edge.fromId != vertexId && edge.toId != vertexId) return edge;
      final from = vertices.firstWhere((vertex) => vertex.id == edge.fromId);
      final to = vertices.firstWhere((vertex) => vertex.id == edge.toId);
      final geometry = [
        ll.LatLng(from.lat, from.lng),
        ll.LatLng(to.lat, to.lng),
      ];
      return MapEdge(
        id: edge.id,
        fromId: edge.fromId,
        toId: edge.toId,
        geometry: geometry,
        lengthMeters: polylineLengthMeters(geometry),
        bidirectional: edge.bidirectional,
      );
    }).toList();

    _data = _data.copyWith(vertices: vertices, edges: edges);
  }

  void _handleVertexTapped(MapVertex vertex) {
    _suppressNextMapTap = true;
    if (_section == EditorSection.routes && _mode == EditorMode.drawPath) {
      _handleVertexTapInDrawMode(vertex);
      return;
    }
    if (_section == EditorSection.routes &&
        (_mode == EditorMode.editConnections ||
            _mode == EditorMode.connectPoiToPath)) {
      final linkedPoi = findPoiForAccessVertex(
        vertexId: vertex.id,
        pois: _data.pois,
      );
      if (linkedPoi != null &&
          poiHasActiveConnection(
            poi: linkedPoi,
            vertices: _data.vertices,
            edges: _data.edges,
          )) {
        unawaited(_offerMovePoiConnection(linkedPoi));
        return;
      }
    }
    _showVertexEditSheet(vertex);
  }

  void _handleVertexMoved(MapVertex vertex, LatLng coordinate) {
    _moveVertex(vertex.id, coordinate.latitude, coordinate.longitude);
    setState(() {
      _movingVertexId = null;
    });
  }

  void _handlePoiTapped(MapPoi poi) {
    _suppressNextMapTap = true;
    if (_section == EditorSection.places) {
      _selectPoi(poi);
      return;
    }
    if (_section != EditorSection.routes) {
      return;
    }
    if (_mode == EditorMode.connectPoiToPath) {
      return;
    }
    if (_mode == EditorMode.drawPath) {
      unawaited(_offerConnectPathToPoi(poi));
      return;
    }
    if (_mode == EditorMode.editConnections) {
      unawaited(_handlePoiConnectionTap(poi));
      return;
    }
  }

  String? _vertexIdForPoiConnection(MapPoi poi) {
    if (_lastVertexId != null) {
      for (final vertex in _data.vertices) {
        if (vertex.id == _lastVertexId) {
          final distance = haversineMeters(
            poi.lat,
            poi.lng,
            vertex.lat,
            vertex.lng,
          );
          if (distance <= AppConstants.routingSnapMaxMeters) {
            return _lastVertexId;
          }
          break;
        }
      }
    }

    return findNearestVertexId(
      lat: poi.lat,
      lng: poi.lng,
      vertices: _data.vertices,
      maxDistanceMeters: AppConstants.routingSnapMaxMeters,
    );
  }

  Future<void> _offerConnectPathToPoi(MapPoi poi) async {
    final vertexId = _vertexIdForPoiConnection(poi);
    if (vertexId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tegn stien tættere på ${poi.displayTitle} før du kobler',
          ),
        ),
      );
      return;
    }

    if (poi.accessVertexId == vertexId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stien er allerede koblet til ${poi.displayTitle}')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kobl sti til sted?'),
        content: Text(
          'Skal stien kobles til «${poi.displayTitle}»?\n\n'
          'Besøgende kan så navigere langs stien til stedet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nej'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, kobl sti'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      final pois = _data.pois.map((candidate) {
        if (candidate.id != poi.id) return candidate;
        return candidate.copyWith(accessVertexId: vertexId);
      }).toList();
      _data = _data.copyWith(pois: pois);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sti koblet til ${poi.displayTitle}')),
    );
  }

  void _adjustPoiConnectionAt(double lat, double lng) {
    final draft = _poiConnectionDraft;
    if (draft == null) return;

    final snap = snapNearMapTap(
      lat: lat,
      lng: lng,
      vertices: _data.vertices,
      edges: _data.edges,
      pois: _data.pois,
    );
    if (snap == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tryk tættere på en officiel sti'),
        ),
      );
      return;
    }

    _poiConnectionDraft = PoiPathConnectionDraft(
      poi: draft.poi,
      snap: snap,
      isNew: draft.isNew,
    );
  }

  EventMapData _repairMapConnections(EventMapData data) {
    final repairedPois = repairBrokenPoiConnections(
      pois: data.pois,
      vertices: data.vertices,
      edges: data.edges,
    );
    if (identical(repairedPois, data.pois)) return data;
    return data.copyWith(pois: repairedPois);
  }

  void _applyClearPoiConnection(MapPoi poi) {
    final cleared = clearPoiConnection(
      poi: poi,
      vertices: _data.vertices,
      edges: _data.edges,
    );
    final pois = List<MapPoi>.from(_data.pois);
    final index = pois.indexWhere((candidate) => candidate.id == cleared.poi.id);
    if (index >= 0) {
      pois[index] = cleared.poi;
    }
    _data = _data.copyWith(
      vertices: cleared.vertices,
      edges: cleared.edges,
      pois: pois,
    );
  }

  Future<void> _offerMovePoiConnection(MapPoi poi) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flyt kobling?'),
        content: Text(
          'Tryk på stien hvor «${poi.displayTitle}» skal kobles til.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nej'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, flyt kobling'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _applyClearPoiConnection(poi));
    final refreshed = _data.pois.firstWhere(
      (candidate) => candidate.id == poi.id,
      orElse: () => poi.copyWith(clearAccessVertexId: true),
    );
    await _beginPoiPathConnection(refreshed, isNew: false);
  }

  Future<void> _beginPoiPathConnection(MapPoi poi, {required bool isNew}) async {
    if (_data.edges.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tegn mindst én officiel sti først')),
      );
      return;
    }

    final snap = suggestPoiPathConnection(
      poi: poi,
      vertices: _data.vertices,
      edges: _data.edges,
      pois: _data.pois,
    );

    if (snap == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ingen sti inden for ${AppConstants.poiPathAccessMaxMeters.toInt()} m — '
            'tegn en sti tættere på stedet',
          ),
        ),
      );
      return;
    }

    setState(() {
      _poiConnectionDraft = PoiPathConnectionDraft(
        poi: poi,
        snap: snap,
        isNew: isNew,
      );
      _mode = EditorMode.connectPoiToPath;
      _selectedPoiId = poi.id;
      _selectedVertexId = null;
      _movingPoiId = null;
      _movingVertexId = null;
      _pendingConnectFromId = null;
    });
  }

  void _confirmPoiPathConnection() {
    final draft = _poiConnectionDraft;
    if (draft == null) return;

    final applied = applyPoiPathConnection(
      poi: draft.poi,
      snap: draft.snap,
      vertices: _data.vertices,
      edges: _data.edges,
      pois: _data.pois,
      uuid: _uuid,
    );
    final connectedPoi = draft.poi.copyWith(accessVertexId: applied.accessVertexId);

    setState(() {
      final pois = List<MapPoi>.from(_data.pois);
      if (draft.isNew) {
        pois.add(connectedPoi);
      } else {
        final index = pois.indexWhere((candidate) => candidate.id == connectedPoi.id);
        if (index >= 0) {
          pois[index] = connectedPoi;
        } else {
          pois.add(connectedPoi);
        }
      }

      _data = _data.copyWith(
        vertices: applied.vertices,
        edges: applied.edges,
        pois: pois,
      );
      _poiConnectionDraft = null;
      _selectedPoiId = connectedPoi.id;
      _mode = EditorMode.editConnections;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${connectedPoi.displayTitle} er koblet til stien')),
    );
  }

  void _cancelPoiPathConnection({MapPoi? resumePoi, required bool wasNew}) {
    setState(() {
      _poiConnectionDraft = null;
      _mode = _inConnectionsFlow
          ? EditorMode.editConnections
          : EditorMode.editPlace;
      _selectedPoiId = resumePoi?.id;
    });

    if (resumePoi != null && !_inConnectionsFlow) {
      unawaited(
        _showPoiSheet(
          lat: resumePoi.lat,
          lng: resumePoi.lng,
          existing: wasNew ? null : resumePoi,
        ),
      );
    }
  }

  List<ll.LatLng> get _poiConnectionPreviewPoints {
    final draft = _poiConnectionDraft;
    if (draft == null) return const [];
    return poiConnectionPreviewPoints(poi: draft.poi, snap: draft.snap);
  }

  ll.LatLng? get _poiConnectionPoint {
    final draft = _poiConnectionDraft;
    if (draft == null) return null;
    return draft.snap.point;
  }

  List<List<ll.LatLng>> get _mapPreviewLines {
    final bulkPlan = _bulkConnectionPlan;
    if (bulkPlan != null) {
      return bulkConnectionPreviewLines(bulkPlan);
    }
    final single = _poiConnectionPreviewPoints;
    if (single.length >= 2) return [single];
    return const [];
  }

  List<ll.LatLng> get _mapConnectionPoints {
    final bulkPlan = _bulkConnectionPlan;
    if (bulkPlan != null) {
      return bulkPlan.proposals.map((proposal) => proposal.snap.point).toList();
    }
    final point = _poiConnectionPoint;
    if (point == null) return const [];
    return [point];
  }

  Future<void> _enterConnectionsMode() async {
    if (_data.pois.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der er ingen steder at koble endnu')),
      );
      return;
    }

    setState(() {
      _section = EditorSection.routes;
      _mode = EditorMode.editConnections;
      _selectedPoiId = null;
      _selectedVertexId = null;
      _movingPoiId = null;
      _movingVertexId = null;
      _pendingConnectFromId = null;
      _poiConnectionDraft = null;
      _bulkConnectionPlan = null;
    });
  }

  void _exitConnectionsMode() {
    if (_mode == EditorMode.connectPoiToPath) {
      _cancelPoiPathConnection(resumePoi: null, wasNew: false);
      return;
    }

    setState(() {
      _mode = EditorMode.drawPath;
      _selectedPoiId = null;
      _bulkConnectionPlan = null;
      _poiConnectionDraft = null;
    });
  }

  void _onSectionChanged(EditorSection section) {
    setState(() {
      _section = section;
      _bulkConnectionPlan = null;
      _poiConnectionDraft = null;
      _movingPoiId = null;
      _movingVertexId = null;
      _selectedVertexId = null;
      _pendingConnectFromId = null;

      switch (section) {
        case EditorSection.routes:
          _mode = EditorMode.drawPath;
          _selectedPoiId = null;
        case EditorSection.places:
          _mode = EditorMode.editPlace;
          _selectedPoiId = null;
          _lastVertexId = null;
          _pathStrokeVertexIds.clear();
        case EditorSection.map:
        case EditorSection.audioTour:
        case EditorSection.treasureHunt:
          _mode = EditorMode.drawPath;
          _selectedPoiId = null;
          _lastVertexId = null;
          _pathStrokeVertexIds.clear();
      }
    });
  }

  void _changeMappingMethod() {
    setState(() {
      _isRecording = false;
      _mappingMethod = null;
    });
    _positionSub?.cancel();
  }

  Future<void> _handlePoiConnectionTap(MapPoi poi) async {
    setState(() => _selectedPoiId = poi.id);

    final hasActive = poiHasActiveConnection(
      poi: poi,
      vertices: _data.vertices,
      edges: _data.edges,
    );
    final isBroken = poiConnectionIsBroken(
      poi: poi,
      vertices: _data.vertices,
      edges: _data.edges,
    );

    if (hasActive && !isBroken) {
      await _offerMovePoiConnection(poi);
      return;
    }

    await _beginPoiPathConnection(poi, isNew: false);
  }

  Future<void> _connectPoiFromPanel(MapPoi poi) async {
    setState(() => _selectedPoiId = poi.id);
    await _beginPoiPathConnection(poi, isNew: false);
  }

  Future<void> _movePoiConnectionFromPanel(MapPoi poi) async {
    setState(() => _selectedPoiId = poi.id);
    await _offerMovePoiConnection(poi);
  }

  void _removePoiConnectionFromPanel(MapPoi poi) {
    setState(() {
      _selectedPoiId = poi.id;
      _applyClearPoiConnection(poi);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kobling fjernet fra ${poi.displayTitle}')),
    );
  }

  Future<void> _proposeAllPoiConnections() async {
    if (_data.edges.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tegn mindst én officiel sti først')),
      );
      return;
    }
    if (_data.pois.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der er ingen steder at koble endnu')),
      );
      return;
    }

    final plan = planAllPoiPathConnections(
      pois: _data.pois,
      vertices: _data.vertices,
      edges: _data.edges,
    );

    if (!mounted) return;

    final action = await showDialog<_BulkConnectionDialogAction>(
      context: context,
      builder: (context) => _BulkPoiConnectionDialog(plan: plan),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _BulkConnectionDialogAction.preview:
        setState(() {
          _bulkConnectionPlan = plan;
          _poiConnectionDraft = null;
          _mode = EditorMode.editConnections;
        });
      case _BulkConnectionDialogAction.apply:
        _applyBulkConnectionPlan(plan);
      case _BulkConnectionDialogAction.cancel:
        break;
    }
  }

  void _applyBulkConnectionPlan(BulkPoiPathConnectionPlan plan) {
    final result = applyBulkPoiPathConnectionPlan(
      plan: plan,
      pois: _data.pois,
      vertices: _data.vertices,
      edges: _data.edges,
      uuid: _uuid,
    );

    setState(() {
      _data = _data.copyWith(
        vertices: result.vertices,
        edges: result.edges,
        pois: result.pois,
      );
      _bulkConnectionPlan = null;
    });

    if (!mounted) return;

    final skipped = plan.skippedCount;
    final message = skipped == 0
        ? '${plan.connectableCount} steder koblet til stien'
        : '${plan.connectableCount} steder koblet — $skipped uden for rækkevidde';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _clearBulkConnectionPreview() {
    if (_bulkConnectionPlan == null) return;
    setState(() => _bulkConnectionPlan = null);
  }

  EventMapData get _mapDisplayData {
    final draft = _poiConnectionDraft;
    if (draft == null || !draft.isNew) return _data;
    if (_data.pois.any((poi) => poi.id == draft.poi.id)) return _data;
    return _data.copyWith(pois: [..._data.pois, draft.poi]);
  }

  void _selectPoi(MapPoi poi) {
    setState(() {
      _selectedPoiId = poi.id;
      _selectedVertexId = null;
      _mode = EditorMode.editPlace;
    });
    _showPoiSheet(
      lat: poi.lat,
      lng: poi.lng,
      existing: poi,
    );
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
      if (fromIndex >= 0) {
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
    }

    _lastVertexId = vertex.id;
    if (_pathStrokeVertexIds.isEmpty || _pathStrokeVertexIds.last != vertex.id) {
      _pathStrokeVertexIds.add(vertex.id);
    }
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

  Future<void> _addPlaceAtMapLocation(double lat, double lng) async {
    final accessVertexId = findNearestVertexId(
      lat: lat,
      lng: lng,
      vertices: _data.vertices,
      maxDistanceMeters: AppConstants.routingSnapMaxMeters,
    );
    await _showPoiSheet(
      lat: lat,
      lng: lng,
      accessVertexId: accessVertexId,
    );
  }

  Future<void> _addPlaceAtCurrentLocation() async {
    final pos = _currentPosition;
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venter på GPS-signal…')),
      );
      return;
    }

    if (!_isRecording) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start mapping først, så stien fører til stedet'),
        ),
      );
      return;
    }

    final accessVertexId = _ensurePathVertexAt(pos.latitude, pos.longitude);
    await _showPoiSheet(
      lat: pos.latitude,
      lng: pos.longitude,
      accessVertexId: accessVertexId,
    );
  }

  void _movePoi(String poiId, double lat, double lng) {
    final index = _data.pois.indexWhere((p) => p.id == poiId);
    if (index < 0) return;
    final pois = List<MapPoi>.from(_data.pois);
    pois[index] = pois[index].copyWith(lat: lat, lng: lng);
    _data = _data.copyWith(pois: pois);
  }

  void _handlePoiMoved(MapPoi poi, LatLng coordinate) {
    final draft = _poiConnectionDraft;
    if (draft != null && draft.poi.id == poi.id) {
      final movedPoi = draft.poi.copyWith(
        lat: coordinate.latitude,
        lng: coordinate.longitude,
      );
      final snap = suggestPoiPathConnection(
        poi: movedPoi,
        vertices: _data.vertices,
        edges: _data.edges,
        pois: _data.pois,
      );
      setState(() {
        _poiConnectionDraft = PoiPathConnectionDraft(
          poi: movedPoi,
          snap: snap ?? draft.snap,
          isNew: draft.isNew,
        );
      });
      return;
    }

    _movePoi(poi.id, coordinate.latitude, coordinate.longitude);
    setState(() {});
  }

  void _selectMappingMethod(MappingMethod method) {
    setState(() {
      _mappingMethod = method;
      _previewIllustratedWhileDrawing = false;
    });
    if (method == MappingMethod.walk) {
      _mode = EditorMode.drawPath;
      _startLocationStream();
    } else {
      _positionSub?.cancel();
      _isRecording = false;
      _mode = EditorMode.drawPath;
    }
  }

  bool get _showBasemapOnMap {
    if (!_data.event.hasIllustratedBasemap || !_showIllustratedBasemap) {
      return false;
    }
    if (_section == EditorSection.map) {
      return true;
    }
    if (_mappingMethod == MappingMethod.draw && !_previewIllustratedWhileDrawing) {
      return false;
    }
    return true;
  }

  Future<void> _showPoiSheet({
    required double lat,
    required double lng,
    MapPoi? existing,
    String? accessVertexId,
  }) async {
    final mappingHint = existing == null
        ? (_mappingMethod == MappingMethod.draw
            ? 'Tryk præcist på kortet — træk pinnen bagefter om nødvendigt.'
            : 'Stien fører hertil — træk pinnen bagefter for præcis placering.')
        : null;

    final result = await PoiEditorSheet.show(
      context,
      eventId: widget.eventId,
      repository: _repository,
      existing: existing,
      lat: lat,
      lng: lng,
      isNew: existing == null,
      mappingHint: mappingHint,
    );

    if (result == null || !mounted) return;

    switch (result.action) {
      case PoiEditorAction.cancel:
        return;
      case PoiEditorAction.delete:
        if (existing == null) return;
        setState(() {
          final pois = _data.pois.where((p) => p.id != existing.id).toList();
          _data = _data.copyWith(pois: pois);
          if (_selectedPoiId == existing.id) {
            _selectedPoiId = null;
          }
        });
        return;
      case PoiEditorAction.movePin:
        if (existing == null) return;
        setState(() {
          _selectedPoiId = existing.id;
          _movingPoiId = existing.id;
          _mode = EditorMode.editPlace;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tryk på kortet hvor pinnen skal stå — eller træk pinnen'),
          ),
        );
        return;
      case PoiEditorAction.save:
        break;
    }

    final basePoi = result.poi;
    if (basePoi == null) return;

    final poi = accessVertexId != null
        ? basePoi.copyWith(accessVertexId: accessVertexId)
        : basePoi;

    setState(() {
      final pois = List<MapPoi>.from(_data.pois);
      if (existing != null) {
        final index = pois.indexWhere((p) => p.id == existing.id);
        if (index >= 0) pois[index] = poi;
        _selectedPoiId = poi.id;
      } else {
        pois.add(poi);
        _selectedPoiId = poi.id;
      }
      _data = _data.copyWith(pois: pois);
      _mode = EditorMode.editPlace;
    });
  }

  Future<void> _openAreaSetup() async {
    final bounds = await Navigator.push<MapBounds>(
      context,
      MaterialPageRoute(
        builder: (context) => AreaSetupScreen(
          eventId: widget.eventId,
          eventName: _data.event.name,
          initialCenter: _mapCenter,
          initialBounds: _data.event.bounds,
        ),
      ),
    );
    if (bounds == null || !mounted) return;
    final refreshed = await _repository.loadForEdit(eventId: widget.eventId);
    setState(() => _data = refreshed);
  }

  Future<void> _uploadIllustratedBasemap() async {
    if (_data.event.bounds == null || !_data.event.bounds!.isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vælg først kortområde'),
        ),
      );
      await _openAreaSetup();
      if (_data.event.bounds == null) return;
    }

    if (!mounted) return;
    final saved = await pickAndAlignBasemap(
      context,
      eventId: widget.eventId,
      eventName: _data.event.name,
      bounds: _data.event.bounds!,
      viewBounds: _data.event.navigationBounds,
      fromEditor: true,
    );
    if (!saved || !mounted) return;

    final refreshed = await _repository.loadForEdit(eventId: widget.eventId);
    setState(() {
      _data = refreshed;
      _showIllustratedBasemap = true;
    });
  }

  Future<void> _openTreasureHuntEditor() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => TreasureHuntEditorScreen(
          eventId: widget.eventId,
          mapData: _data,
          onSaved: (updated) => setState(() => _data = updated),
        ),
      ),
    );
  }

  Future<void> _openAudioTourEditor() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AudioTourEditorScreen(
          eventId: widget.eventId,
          mapData: _data,
          onSaved: (updated) => setState(() => _data = updated),
        ),
      ),
    );
  }

  Future<void> _openPublish() async {
    final saved = await _save();
    if (!saved || !mounted) return;
    final slug = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => PublishScreen(
          eventId: widget.eventId,
          eventName: _data.event.name,
          mapData: _data,
        ),
      ),
    );
    if (slug != null && mounted) {
      setState(() {
        _data = _data.copyWith(
          event: _data.event.copyWith(
            status: 'published',
            publicSlug: slug,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final method = _mappingMethod;
    final statusText = _buildStatusText(method);

    return Scaffold(
      appBar: AppBar(
        leading: _inConnectionsFlow
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Tilbage til ruter',
                onPressed: _exitConnectionsMode,
              )
            : null,
        title: Text(_inConnectionsFlow ? 'Koblinger' : _data.event.name),
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
          TextButton(onPressed: _openPublish, child: const Text('Publicér')),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text('Kunne ikke hente kort: $_error'),
              actions: [
                TextButton(onPressed: () => setState(() => _error = null), child: const Text('Luk')),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                EventMapWidget(
                  data: _mapDisplayData,
                  initialCenter: _mapCenter,
                  myLocationEnabled:
                      _section == EditorSection.routes && method == MappingMethod.walk,
                  showIllustratedBasemap: _showBasemapOnMap,
                  illustratedMapOnly: _showBasemapOnMap,
                  showEventPaths: true,
                  showPathVertices: true,
                  showPoiMarkers: true,
                  selectedPoiId: _selectedPoiId,
                  selectedVertexId: _selectedVertexId,
                  previewLines: _mapPreviewLines,
                  connectionPoints: _mapConnectionPoints,
                  poiDraggable: _mode == EditorMode.editPlace ||
                      _mode == EditorMode.connectPoiToPath,
                  vertexDraggable: _movingVertexId != null,
                  onMapTap: _handleMapTap,
                  onPoiTapped: _handlePoiTapped,
                  onPoiMoved: _handlePoiMoved,
                  onVertexTapped: _handleVertexTapped,
                  onVertexMoved: _handleVertexMoved,
                ),
                if (_showBasemapOnMap && method == MappingMethod.draw)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange.shade800,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'Preview af tegning — skjul den for at tegne på OSM-kortet',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                      ),
                    ),
                  ),
                if (_isRecording)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.red.shade700,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Optager sti',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (method == null && _section == EditorSection.routes)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: _MappingMethodPicker(
                          onSelected: _selectMappingMethod,
                        ),
                      ),
                    ),
                  ),
                if (_section == EditorSection.routes &&
                    ((method == MappingMethod.draw && _mode == EditorMode.drawPath) ||
                        (method == MappingMethod.walk && _isRecording)) &&
                    _canUndoPathPoint)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Material(
                      elevation: 4,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _undoLastPathPoint,
                        child: Tooltip(
                          message: 'Fortryd sidste punkt',
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Icon(
                              Icons.undo,
                              color: Theme.of(context).colorScheme.primary,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(statusText, style: Theme.of(context).textTheme.bodySmall),
          ),
          _buildSectionPanel(method),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${_data.edges.length} stier · ${_data.pois.length} steder · ${_data.vertices.length} punkter',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) =>
            _onSectionChanged(EditorSection.values[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Ruter',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Steder',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Kort',
          ),
          NavigationDestination(
            icon: Icon(Icons.headphones_outlined),
            selectedIcon: Icon(Icons.headphones),
            label: 'Lydvandringer',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Skattejagt',
          ),
        ],
      ),
    );
  }

  String _buildStatusText(MappingMethod? method) {
    switch (_section) {
      case EditorSection.map:
        return 'Tilpas kortområde og illustreret overlay-kort';
      case EditorSection.audioTour:
        final count = _data.audioTourCatalog.tours.length;
        return count == 0
            ? 'Opret lydvandringer der guider gæster langs stierne'
            : '$count lydvandring${count == 1 ? '' : 'er'} på kortet';
      case EditorSection.treasureHunt:
        final huntCount = _data.treasureHuntCatalog.hunts.length;
        return huntCount == 0
            ? 'Opret skattejagter med poster på kortet'
            : '$huntCount skattejagt${huntCount == 1 ? '' : 'er'}';
      case EditorSection.places:
        if (_mode == EditorMode.addPlace) {
          return 'Tryk på kortet hvor stedet skal stå';
        }
        if (_movingPoiId != null) {
          return 'Tryk hvor pinnen skal stå — eller træk den';
        }
        return 'Tryk på et sted for at redigere — eller tilføj et nyt';
      case EditorSection.routes:
        if (method == null) {
          return 'Vælg om du vil tegne eller gå ruterne';
        }
        if (_bulkConnectionPlan != null) {
          return 'Forhåndsvisning: ${_bulkConnectionPlan!.connectableCount} tilkoblingsstier';
        }
        if (method == MappingMethod.walk) {
          return _isRecording
              ? 'Optager sti — gå ruten på kortet'
              : 'Tryk «Start mapping» og gå ruten fysisk';
        }
        if (_mode == EditorMode.connectPoiToPath) {
          return 'Tryk på stien hvor tilkoblingen skal være — bekræft bagefter';
        }
        if (_mode == EditorMode.editConnections) {
          return 'Tryk på et sted eller dets koblingssti for at rette';
        }
        if (_movingVertexId != null) {
          return 'Træk stipunktet eller tryk hvor det skal stå';
        }
        if (!_showBasemapOnMap && _data.event.hasIllustratedBasemap) {
          return 'OSM-kort vises under tegning — illustreret kort er skjult';
        }
        if (_lastVertexId != null) {
          return 'Tryk på kortet for næste punkt — tryk på et sted for at koble stien';
        }
        if (_pendingConnectFromId != null) {
          return 'Tryk på det andet punkt og vælg «Kobl til valgt punkt»';
        }
        return 'Tryk på kortet for at tegne stier — brug «Koblinger» for sted-tilkoblinger';
    }
  }

  Widget _buildSectionPanel(MappingMethod? method) {
    switch (_section) {
      case EditorSection.routes:
        if (_bulkConnectionPlan != null) {
          return _BulkConnectionPreviewToolbar(
            plan: _bulkConnectionPlan!,
            onApply: () => _applyBulkConnectionPlan(_bulkConnectionPlan!),
            onDismiss: _clearBulkConnectionPreview,
          );
        }
        if (_mode == EditorMode.connectPoiToPath && _poiConnectionDraft != null) {
          return _PoiConnectionToolbar(
            distanceMeters: _poiConnectionDraft!.snap.distanceMeters,
            onConfirm: _confirmPoiPathConnection,
            onCancel: () => _cancelPoiPathConnection(
              resumePoi: _poiConnectionDraft!.poi,
              wasNew: _poiConnectionDraft!.isNew,
            ),
          );
        }
        if (_mode == EditorMode.editConnections) {
          return PoiConnectionsPanel(
            pois: _data.pois,
            vertices: _data.vertices,
            edges: _data.edges,
            selectedPoiId: _selectedPoiId,
            onConnectAll: _proposeAllPoiConnections,
            onPoiSelected: (poi) => setState(() => _selectedPoiId = poi.id),
            onConnectPoi: _connectPoiFromPanel,
            onMoveConnection: _movePoiConnectionFromPanel,
            onRemoveConnection: _removePoiConnectionFromPanel,
          );
        }
        if (method == null) return const SizedBox.shrink();
        return _RoutesToolbar(
          mappingMethod: method,
          isRecording: _isRecording,
          pathActive: _lastVertexId != null,
          onToggleRecording: _toggleRecording,
          onChangeMethod: _changeMappingMethod,
          onEnterConnections: _enterConnectionsMode,
          onFinishPath: _finishPath,
          onUndo: _undo,
        );
      case EditorSection.places:
        return _PlacesToolbar(
          mode: _mode,
          walkRecording: method == MappingMethod.walk && _isRecording,
          onModeChanged: (mode) => setState(() {
            _mode = mode;
            _movingPoiId = null;
          }),
          onAddPlaceAtGps: _addPlaceAtCurrentLocation,
        );
      case EditorSection.map:
        return _MapSectionPanel(
          hasIllustratedBasemap: _data.event.hasIllustratedBasemap,
          basemapVisible: _showBasemapOnMap,
          onAreaSetup: _openAreaSetup,
          onUploadBasemap: _uploadIllustratedBasemap,
          onToggleBasemap: () => setState(() {
            _showIllustratedBasemap = !_showIllustratedBasemap;
            _previewIllustratedWhileDrawing = _showIllustratedBasemap;
          }),
        );
      case EditorSection.audioTour:
        return _AudioTourSectionPanel(
          tourCount: _data.audioTourCatalog.tours.length,
          onOpenEditor: _openAudioTourEditor,
        );
      case EditorSection.treasureHunt:
        return _TreasureHuntSectionPanel(
          huntCount: _data.treasureHuntCatalog.hunts.length,
          postCount: _data.treasureHuntCatalog.primaryHunt.posts.length,
          onOpenEditor: _openTreasureHuntEditor,
        );
    }
  }
}

class _MappingMethodPicker extends StatelessWidget {
  const _MappingMethodPicker({required this.onSelected});

  final ValueChanged<MappingMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hvordan vil du lave kortet?',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vælg én metode — du kan skifte senere under fanen Ruter.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            for (final method in MappingMethod.values) ...[
              _MethodOptionCard(
                icon: method == MappingMethod.walk
                    ? Icons.directions_walk
                    : Icons.draw_outlined,
                title: method.title,
                subtitle: method.subtitle,
                onTap: () => onSelected(method),
              ),
              if (method != MappingMethod.values.last) const SizedBox(height: 12),
            ],
          ],
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

class _RoutesToolbar extends StatelessWidget {
  const _RoutesToolbar({
    required this.mappingMethod,
    required this.isRecording,
    required this.pathActive,
    required this.onToggleRecording,
    required this.onChangeMethod,
    required this.onEnterConnections,
    required this.onFinishPath,
    required this.onUndo,
  });

  final MappingMethod mappingMethod;
  final bool isRecording;
  final bool pathActive;
  final VoidCallback onToggleRecording;
  final VoidCallback onChangeMethod;
  final VoidCallback onEnterConnections;
  final VoidCallback onFinishPath;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: mappingMethod == MappingMethod.walk
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onToggleRecording,
                          icon: Icon(isRecording ? Icons.stop : Icons.directions_walk),
                          label: Text(isRecording ? 'Stop mapping' : 'Start mapping'),
                          style: FilledButton.styleFrom(
                            backgroundColor: isRecording ? Colors.red.shade700 : null,
                          ),
                        ),
                      ),
                      IconButton(onPressed: onUndo, icon: const Icon(Icons.undo)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _RoutesSecondaryActions(
                    onChangeMethod: onChangeMethod,
                    onEnterConnections: onEnterConnections,
                  ),
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.timeline),
                          label: const Text('Tegn sti'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (pathActive)
                        TextButton(onPressed: onFinishPath, child: const Text('Afslut sti'))
                      else
                        IconButton(onPressed: onUndo, icon: const Icon(Icons.undo)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _RoutesSecondaryActions(
                    onChangeMethod: onChangeMethod,
                    onEnterConnections: onEnterConnections,
                  ),
                ],
              ),
      ),
    );
  }
}

class _RoutesSecondaryActions extends StatelessWidget {
  const _RoutesSecondaryActions({
    required this.onChangeMethod,
    required this.onEnterConnections,
  });

  final VoidCallback onChangeMethod;
  final VoidCallback onEnterConnections;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onEnterConnections,
            icon: const Icon(Icons.link),
            label: const Text('Koblinger'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onChangeMethod,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Metode'),
          ),
        ),
      ],
    );
  }
}

class _PlacesToolbar extends StatelessWidget {
  const _PlacesToolbar({
    required this.mode,
    required this.walkRecording,
    required this.onModeChanged,
    required this.onAddPlaceAtGps,
  });

  final EditorMode mode;
  final bool walkRecording;
  final ValueChanged<EditorMode> onModeChanged;
  final VoidCallback onAddPlaceAtGps;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onModeChanged(EditorMode.addPlace),
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Tilføj sted'),
                    style: FilledButton.styleFrom(
                      backgroundColor: mode == EditorMode.addPlace
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      foregroundColor: mode == EditorMode.addPlace
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onModeChanged(EditorMode.editPlace),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Rediger sted'),
                    style: FilledButton.styleFrom(
                      backgroundColor: mode == EditorMode.editPlace
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      foregroundColor: mode == EditorMode.editPlace
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (walkRecording) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onAddPlaceAtGps,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Tilføj sted ved GPS'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapSectionPanel extends StatelessWidget {
  const _MapSectionPanel({
    required this.hasIllustratedBasemap,
    required this.basemapVisible,
    required this.onAreaSetup,
    required this.onUploadBasemap,
    required this.onToggleBasemap,
  });

  final bool hasIllustratedBasemap;
  final bool basemapVisible;
  final Future<void> Function() onAreaSetup;
  final Future<void> Function() onUploadBasemap;
  final VoidCallback onToggleBasemap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: onAreaSetup,
              icon: const Icon(Icons.crop_free),
              label: const Text('Kortområde og udsnit'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onUploadBasemap,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                hasIllustratedBasemap ? 'Skift overlay-kort' : 'Upload overlay-kort',
              ),
            ),
            if (hasIllustratedBasemap) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onToggleBasemap,
                icon: Icon(basemapVisible ? Icons.layers : Icons.layers_outlined),
                label: Text(basemapVisible ? 'Skjul overlay-kort' : 'Vis overlay-kort'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TreasureHuntSectionPanel extends StatelessWidget {
  const _TreasureHuntSectionPanel({
    required this.huntCount,
    required this.postCount,
    required this.onOpenEditor,
  });

  final int huntCount;
  final int postCount;
  final Future<void> Function() onOpenEditor;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              huntCount == 0
                  ? 'Ingen skattejagter endnu'
                  : huntCount == 1
                      ? '$postCount post${postCount == 1 ? '' : 'er'} i skattejagten'
                      : '$huntCount skattejagter',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onOpenEditor,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Administrer skattejagt'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioTourSectionPanel extends StatelessWidget {
  const _AudioTourSectionPanel({
    required this.tourCount,
    required this.onOpenEditor,
  });

  final int tourCount;
  final Future<void> Function() onOpenEditor;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tourCount == 0
                  ? 'Ingen lydvandringer endnu'
                  : '$tourCount lydvandring${tourCount == 1 ? '' : 'er'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onOpenEditor,
              icon: const Icon(Icons.headphones_outlined),
              label: const Text('Administrer lydvandringer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoiConnectionToolbar extends StatelessWidget {
  const _PoiConnectionToolbar({
    required this.distanceMeters,
    required this.onConfirm,
    required this.onCancel,
  });

  final double distanceMeters;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tilkoblingssti: ${distanceMeters.round()} m fra stedet til stien',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Annuller'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check),
                    label: const Text('Bekræft tilkobling'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _BulkConnectionDialogAction { preview, apply, cancel }

class _BulkPoiConnectionDialog extends StatelessWidget {
  const _BulkPoiConnectionDialog({required this.plan});

  final BulkPoiPathConnectionPlan plan;

  @override
  Widget build(BuildContext context) {
    final maxDistance = AppConstants.poiPathAccessMaxMeters.toInt();

    return AlertDialog(
      title: const Text('Kobl alle steder til stierne?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              plan.connectableCount == 0
                  ? 'Ingen steder kan kobles automatisk inden for $maxDistance m.'
                  : 'Appen foreslår tilkobling for ${plan.connectableCount} sted${plan.connectableCount == 1 ? '' : 'er'}.',
            ),
            if (plan.skippedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${plan.skippedCount} sted${plan.skippedCount == 1 ? '' : 'er'} er for langt fra stierne:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (plan.proposals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Forslag:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  itemCount: plan.proposals.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final proposal = plan.proposals[index];
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            proposal.poi.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${proposal.distanceMeters.round()} m'),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (plan.outOfRange.isNotEmpty && plan.proposals.isEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: ListView.separated(
                  itemCount: plan.outOfRange.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    return Text(plan.outOfRange[index].displayTitle);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _BulkConnectionDialogAction.cancel),
          child: const Text('Annuller'),
        ),
        if (plan.connectableCount > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, _BulkConnectionDialogAction.preview),
            child: const Text('Vis på kort'),
          ),
        if (plan.connectableCount > 0)
          FilledButton(
            onPressed: () => Navigator.pop(context, _BulkConnectionDialogAction.apply),
            child: const Text('Anvend alle'),
          ),
      ],
    );
  }
}

class _BulkConnectionPreviewToolbar extends StatelessWidget {
  const _BulkConnectionPreviewToolbar({
    required this.plan,
    required this.onApply,
    required this.onDismiss,
  });

  final BulkPoiPathConnectionPlan plan;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${plan.connectableCount} orange tilkoblingsstier vist på kortet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDismiss,
                    child: const Text('Skjul forslag'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onApply,
                    icon: const Icon(Icons.check),
                    label: const Text('Anvend alle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
