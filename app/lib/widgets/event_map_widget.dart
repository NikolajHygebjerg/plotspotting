import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/constants.dart';
import '../core/geo/geo_utils.dart';
import '../core/utils/debounce.dart';
import '../data/models/event_map_data.dart';
import '../data/models/map_edge.dart';
import '../data/models/map_poi.dart';
import '../data/models/map_vertex.dart';
import 'route_dots_overlay.dart';

class EventMapWidget extends StatefulWidget {
  const EventMapWidget({
    super.key,
    required this.data,
    this.routePoints = const [],
    this.previewLines = const [],
    this.connectionPoints = const [],
    this.initialCenter,
    this.myLocationEnabled = false,
    this.myLocationRenderMode = MyLocationRenderMode.normal,
    this.myLocationTrackingMode = MyLocationTrackingMode.none,
    this.showEventPaths = true,
    this.showPathVertices = true,
    this.showIllustratedBasemap = true,
    this.routeDotted = false,
    this.selectedPoiId,
    this.selectedVertexId,
    this.destinationPoiId,
    this.showPoiMarkers = true,
    this.poiDraggable = false,
    this.vertexDraggable = false,
    this.onMapTap,
    this.onPoiTapped,
    this.onPoiMoved,
    this.onVertexTapped,
    this.onVertexMoved,
    this.onMapCreated,
    this.constrainToEventBounds = false,
    this.boundsFitPadding,
    this.illustratedMapOnly = false,
    this.attributionButtonPosition,
    this.attributionButtonMargins,
    this.overlayEdges = const [],
    this.overlayEdgeColor = '#F9A825',
  });

  final EventMapData data;
  final List<ll.LatLng> routePoints;
  final List<List<ll.LatLng>> previewLines;
  final List<ll.LatLng> connectionPoints;
  final ll.LatLng? initialCenter;
  final bool myLocationEnabled;
  final MyLocationRenderMode myLocationRenderMode;
  final MyLocationTrackingMode myLocationTrackingMode;
  final bool showEventPaths;
  final bool showPathVertices;
  final bool showIllustratedBasemap;
  final bool routeDotted;
  final String? selectedPoiId;
  final String? selectedVertexId;
  final String? destinationPoiId;
  final bool showPoiMarkers;
  final bool poiDraggable;
  final bool vertexDraggable;
  final void Function(LatLng coordinate)? onMapTap;
  final void Function(MapPoi poi)? onPoiTapped;
  final void Function(MapPoi poi, LatLng coordinate)? onPoiMoved;
  final void Function(MapVertex vertex)? onVertexTapped;
  final void Function(MapVertex vertex, LatLng coordinate)? onVertexMoved;
  final void Function(MapLibreMapController controller)? onMapCreated;
  /// When true, pan/zoom is limited to [EventMeta.bounds] and the camera fits that area.
  final bool constrainToEventBounds;
  final EdgeInsets? boundsFitPadding;
  /// Skjul OSM og vis kun illustreret kort (fuld opacity) — til gæster.
  final bool illustratedMapOnly;
  final AttributionButtonPosition? attributionButtonPosition;
  final Point? attributionButtonMargins;
  /// Ekstra stier (fx jagt-specifikke) tegnes oven på officielle stier.
  final List<MapEdge> overlayEdges;
  final String overlayEdgeColor;

  @override
  State<EventMapWidget> createState() => _EventMapWidgetState();
}

class _EventMapWidgetState extends State<EventMapWidget> {
  static const _basemapSourceId = 'illustrated-basemap';
  static const _basemapLayerId = 'illustrated-basemap-layer';
  /// Basemap sits above land/water but below paths, pins and labels we draw.
  static const _basemapBelowLayerId = 'water';

  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _basemapReady = false;
  String? _loadedBasemapUrl;
  Future<void>? _syncBasemapInFlight;
  final _poiSymbols = <String, Symbol>{};
  final _poiLabelSymbols = <String, Symbol>{};
  final _poiCircles = <String, Circle>{};
  final _vertexCircles = <String, Circle>{};
  OnFeatureDragCallback? _dragCallback;
  final _routeOverlayKey = GlobalKey<RouteDotsOverlayState>();
  final _overlayPositionThrottler = Throttler(const Duration(milliseconds: 80));
  Line? _routeLine;
  Line? _previewLine;
  final _previewLines = <Line>[];
  Circle? _connectionPointCircle;
  final _connectionPointCircles = <Circle>[];
  final _routeDotCircles = <Circle>[];

  bool get _useFlutterRouteOverlay =>
      _useBlankMapStyle && widget.routeDotted && widget.routePoints.length >= 2;

  bool get _trackCameraForOverlays => _useFlutterRouteOverlay;

  bool get _useEventBounds =>
      widget.constrainToEventBounds &&
      widget.data.event.navigationBounds != null &&
      widget.data.event.navigationBounds!.isValid;

  bool get _useIllustratedBasemap =>
      widget.showIllustratedBasemap && widget.data.event.hasIllustratedBasemap;

  bool get _useBlankMapStyle => widget.illustratedMapOnly && _useIllustratedBasemap;

  @override
  void didUpdateWidget(covariant EventMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_styleReady) return;

    final graphChanged =
        oldWidget.data.vertices.length != widget.data.vertices.length ||
            oldWidget.data.edges.length != widget.data.edges.length ||
            oldWidget.data.pois.length != widget.data.pois.length ||
            oldWidget.data.vertices != widget.data.vertices ||
            oldWidget.data.edges != widget.data.edges ||
            oldWidget.data.pois != widget.data.pois;

    final basemapChanged = oldWidget.showIllustratedBasemap != widget.showIllustratedBasemap ||
        oldWidget.illustratedMapOnly != widget.illustratedMapOnly ||
        oldWidget.data.event.basemapUrl != widget.data.event.basemapUrl ||
        oldWidget.data.event.bounds != widget.data.event.bounds;

    final annotationVisualsChanged =
        oldWidget.selectedPoiId != widget.selectedPoiId ||
            oldWidget.selectedVertexId != widget.selectedVertexId ||
            oldWidget.destinationPoiId != widget.destinationPoiId ||
            oldWidget.showPoiMarkers != widget.showPoiMarkers ||
            (oldWidget.onPoiTapped != null) != (widget.onPoiTapped != null);

    final routeChanged =
        oldWidget.routeDotted != widget.routeDotted ||
            !_sameLatLngList(oldWidget.routePoints, widget.routePoints);

    final previewChanged =
        !_samePreviewLines(oldWidget.previewLines, widget.previewLines) ||
            !_sameLatLngList(oldWidget.connectionPoints, widget.connectionPoints);

    if (basemapChanged) {
      _syncMapContent();
    } else if (graphChanged ||
        oldWidget.showEventPaths != widget.showEventPaths ||
        oldWidget.overlayEdges != widget.overlayEdges ||
        oldWidget.overlayEdgeColor != widget.overlayEdgeColor ||
        oldWidget.showPathVertices != widget.showPathVertices) {
      if (widget.showIllustratedBasemap && widget.data.event.hasIllustratedBasemap) {
        _syncMapContent();
      } else {
        _syncAnnotations();
      }
    } else if (routeChanged || previewChanged) {
      _syncRouteOnly();
    } else if (annotationVisualsChanged) {
      _syncPoiVisuals(oldWidget);
    }

    if (oldWidget.poiDraggable != widget.poiDraggable ||
        oldWidget.vertexDraggable != widget.vertexDraggable) {
      _updateDragListener();
    }
    if (oldWidget.myLocationTrackingMode != widget.myLocationTrackingMode &&
        widget.myLocationEnabled) {
      _controller?.updateMyLocationTrackingMode(widget.myLocationTrackingMode);
    }
  }

  bool _samePreviewLines(List<List<ll.LatLng>> a, List<List<ll.LatLng>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameLatLngList(a[i], b[i])) return false;
    }
    return true;
  }

  bool _sameLatLngList(List<ll.LatLng> a, List<ll.LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _removeDragListener();
    super.dispose();
  }

  void _updateDragListener() {
    final controller = _controller;
    if (controller == null) return;

    _removeDragListener();
    if (widget.poiDraggable && widget.onPoiMoved != null ||
        widget.vertexDraggable && widget.onVertexMoved != null) {
      _dragCallback = _handleFeatureDrag;
      controller.onFeatureDrag.add(_dragCallback!);
    }
  }

  void _removeDragListener() {
    final controller = _controller;
    if (controller != null && _dragCallback != null) {
      controller.onFeatureDrag.remove(_dragCallback!);
      _dragCallback = null;
    }
  }

  void _handleFeatureDrag(
    Point<double> point,
    LatLng origin,
    LatLng current,
    LatLng delta,
    String id,
    Annotation? annotation,
    DragEventType eventType,
  ) {
    if (eventType != DragEventType.end) return;

    for (final entry in _poiSymbols.entries) {
      if (entry.value.id == id || entry.value == annotation) {
        final poi = widget.data.pois.firstWhere((p) => p.id == entry.key);
        widget.onPoiMoved?.call(poi, current);
        return;
      }
    }

    for (final entry in _vertexCircles.entries) {
      if (entry.value.id == id || entry.value == annotation) {
        final vertex = widget.data.vertices.firstWhere((v) => v.id == entry.key);
        widget.onVertexMoved?.call(vertex, current);
        return;
      }
    }
  }

  Future<void> _clearPreviewAnnotations() async {
    final controller = _controller;
    if (controller == null) return;

    if (_previewLine != null) {
      try {
        await controller.removeLine(_previewLine!);
      } on Object {
        // Line may already be gone.
      }
      _previewLine = null;
    }

    for (final line in _previewLines) {
      try {
        await controller.removeLine(line);
      } on Object {
        // Line may already be gone.
      }
    }
    _previewLines.clear();

    if (_connectionPointCircle != null) {
      try {
        await controller.removeCircle(_connectionPointCircle!);
      } on Object {
        // Circle may already be gone.
      }
      _connectionPointCircle = null;
    }

    for (final circle in _connectionPointCircles) {
      try {
        await controller.removeCircle(circle);
      } on Object {
        // Circle may already be gone.
      }
    }
    _connectionPointCircles.clear();
  }

  Future<void> _drawPreviewLines() async {
    final controller = _controller;
    if (controller == null) return;

    await _clearPreviewAnnotations();

    for (final points in widget.previewLines) {
      if (points.length < 2) continue;
      final line = await controller.addLine(
        LineOptions(
          geometry: points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
          lineColor: '#FB8C00',
          lineWidth: 4,
          lineOpacity: 0.9,
        ),
      );
      _previewLines.add(line);
    }

    for (final connectionPoint in widget.connectionPoints) {
      final circle = await controller.addCircle(
        CircleOptions(
          geometry: LatLng(connectionPoint.latitude, connectionPoint.longitude),
          circleRadius: 8,
          circleColor: '#FB8C00',
          circleStrokeWidth: 2,
          circleStrokeColor: '#FFFFFF',
        ),
      );
      _connectionPointCircles.add(circle);
    }
  }

  Future<void> _drawRoute(List<ll.LatLng> routePoints) async {
    final controller = _controller;
    if (controller == null || routePoints.length < 2) return;

    await _clearRouteAnnotations();

    if (widget.routeDotted) {
      final dots = samplePointsAlongPolyline(
        routePoints,
        intervalMeters: AppConstants.routeDotIntervalMeters,
      );
      for (final point in dots) {
        final circle = await controller.addCircle(
          CircleOptions(
            geometry: LatLng(point.latitude, point.longitude),
            circleRadius: AppConstants.routeDotRadius,
            circleColor: AppConstants.routeDotColor,
            circleStrokeWidth: 1,
            circleStrokeColor: '#FFFFFF',
          ),
        );
        _routeDotCircles.add(circle);
      }
      return;
    }

    _routeLine = await controller.addLine(
      LineOptions(
        geometry: routePoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(),
        lineColor: '#2E7D32',
        lineWidth: 6,
      ),
    );
  }

  Future<void> _clearRouteAnnotations() async {
    final controller = _controller;
    if (controller == null) return;

    if (_routeLine != null) {
      try {
        await controller.removeLine(_routeLine!);
      } on Object {
        // Line may already be gone.
      }
      _routeLine = null;
    }

    for (final circle in _routeDotCircles) {
      try {
        await controller.removeCircle(circle);
      } on Object {
        // Circle may already be gone.
      }
    }
    _routeDotCircles.clear();
  }

  Future<void> _syncRouteOnly() async {
    if (_useFlutterRouteOverlay) {
      await _routeOverlayKey.currentState?.updatePositions();
      return;
    }

    if (widget.routePoints.length < 2) {
      await _clearRouteAnnotations();
    } else {
      await _drawRoute(widget.routePoints);
    }

    if (widget.previewLines.isEmpty && widget.connectionPoints.isEmpty) {
      await _clearPreviewAnnotations();
    } else {
      await _drawPreviewLines();
    }
  }

  Future<void> _syncPoiVisuals(EventMapWidget oldWidget) async {
    final affectedIds = <String>{
      if (oldWidget.destinationPoiId != null) oldWidget.destinationPoiId!,
      if (widget.destinationPoiId != null) widget.destinationPoiId!,
      if (oldWidget.selectedPoiId != null) oldWidget.selectedPoiId!,
      if (widget.selectedPoiId != null) widget.selectedPoiId!,
      if (oldWidget.selectedVertexId != null) oldWidget.selectedVertexId!,
      if (widget.selectedVertexId != null) widget.selectedVertexId!,
    };

    for (final id in affectedIds) {
      if (_poiCircles.containsKey(id)) {
        await _refreshPoiAnnotation(id);
      } else if (_vertexCircles.containsKey(id)) {
        await _refreshVertexAnnotation(id);
      }
    }
  }

  Future<void> _refreshPoiAnnotation(String poiId) async {
    final controller = _controller;
    if (controller == null) return;

    MapPoi? poi;
    for (final candidate in widget.data.pois) {
      if (candidate.id == poiId) {
        poi = candidate;
        break;
      }
    }
    if (poi == null) return;

    final oldCircle = _poiCircles.remove(poiId);
    final oldSymbol = _poiSymbols.remove(poiId);
    final oldLabel = _poiLabelSymbols.remove(poiId);

    if (oldCircle != null) {
      try {
        await controller.removeCircle(oldCircle);
      } on Object {
        // Annotation may already be gone.
      }
    }
    if (oldSymbol != null) {
      try {
        await controller.removeSymbol(oldSymbol);
      } on Object {
        // Annotation may already be gone.
      }
    }
    if (oldLabel != null) {
      try {
        await controller.removeSymbol(oldLabel);
      } on Object {
        // Annotation may already be gone.
      }
    }

    await _addPoiAnnotation(poi);
  }

  Future<void> _refreshVertexAnnotation(String vertexId) async {
    final controller = _controller;
    if (controller == null) return;

    MapVertex? vertex;
    for (final candidate in widget.data.vertices) {
      if (candidate.id == vertexId) {
        vertex = candidate;
        break;
      }
    }
    if (vertex == null) return;

    final oldCircle = _vertexCircles.remove(vertexId);
    if (oldCircle != null) {
      try {
        await controller.removeCircle(oldCircle);
      } on Object {
        // Annotation may already be gone.
      }
    }

    final selected = vertex.id == widget.selectedVertexId;
    final vertexColor = _useIllustratedBasemap ? '#FF6D00' : '#1565C0';
    final circle = await controller.addCircle(
      CircleOptions(
        geometry: LatLng(vertex.lat, vertex.lng),
        circleRadius: selected ? 7 : (_useIllustratedBasemap ? 5 : 4),
        circleColor: selected ? '#D84315' : vertexColor,
        circleStrokeWidth: selected ? 2 : 1.5,
        circleStrokeColor: '#FFFFFF',
        draggable: widget.vertexDraggable && widget.selectedVertexId == vertex.id,
      ),
    );
    _vertexCircles[vertex.id] = circle;
  }

  Future<void> _addPoiAnnotation(MapPoi poi) async {
    final controller = _controller;
    if (controller == null) return;

    final isDestination = poi.id == widget.destinationPoiId;
    if (!widget.showPoiMarkers && !isDestination && widget.onPoiTapped == null) {
      return;
    }

    final isInteractive = widget.onPoiTapped != null;
    final selected = poi.id == widget.selectedPoiId;
    final pinColor = isDestination
        ? '#E53935'
        : selected
            ? '#D84315'
            : poi.markerColorHex;

    final pinRadius = isDestination
        ? 16.0
        : isInteractive
            ? (_useIllustratedBasemap ? 13.0 : 14.0)
            : 8.0;
    final circle = await controller.addCircle(
      CircleOptions(
        geometry: LatLng(poi.lat, poi.lng),
        circleRadius: pinRadius,
        circleColor: pinColor,
        circleOpacity: isDestination || selected ? 0.95 : 0.25,
        circleStrokeWidth: isInteractive ? 3.5 : 2.5,
        circleStrokeColor: '#FFFFFF',
      ),
    );
    _poiCircles[poi.id] = circle;

    final symbol = await controller.addSymbol(
      SymbolOptions(
        geometry: LatLng(poi.lat, poi.lng),
        textField: poi.mapPinIcon,
        fontNames: AppConstants.poiMapFontStack,
        textSize: isDestination ? 24 : (isInteractive ? (_useIllustratedBasemap ? 18 : 22) : 16),
        textColor: '#FFFFFF',
        textHaloColor: pinColor,
        textHaloWidth: isInteractive ? 2.2 : 1.6,
        zIndex: 20,
        draggable: widget.poiDraggable,
      ),
    );
    _poiSymbols[poi.id] = symbol;
  }

  Future<void> _removeBasemapIfPresent() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.removeLayer(_basemapLayerId);
    } on Object {
      // Layer may already be gone after hot restart or style reload.
    }
    try {
      await controller.removeSource(_basemapSourceId);
    } on Object {
      // Source may already be gone.
    }
    _basemapReady = false;
    _loadedBasemapUrl = null;
  }

  Future<void> _syncBasemap() async {
    if (_syncBasemapInFlight != null) {
      await _syncBasemapInFlight;
      return;
    }
    _syncBasemapInFlight = _syncBasemapImpl();
    try {
      await _syncBasemapInFlight;
    } finally {
      _syncBasemapInFlight = null;
    }
  }

  Future<void> _syncBasemapImpl() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;

    if (!_useIllustratedBasemap) {
      // Always try to remove — native layer may exist after hot restart
      // even when _basemapReady is false.
      await _removeBasemapIfPresent();
      return;
    }

    final event = widget.data.event;
    final url = event.basemapUrl!;
    if (_basemapReady && _loadedBasemapUrl == url) return;

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200 || !mounted) return;

    final quad = event.bounds!.toLatLngQuad();
    final bytes = response.bodyBytes;

    if (_basemapReady) {
      try {
        await controller.updateImageSource(_basemapSourceId, bytes, quad);
      } on Object {
        await _removeBasemapIfPresent();
        await _addBasemapLayer(controller, bytes, quad);
      }
    } else {
      await _removeBasemapIfPresent();
      try {
        await _addBasemapLayer(controller, bytes, quad);
      } on PlatformException catch (error) {
        if (error.code == 'duplicateSource') {
          await controller.updateImageSource(_basemapSourceId, bytes, quad);
          try {
            await controller.addImageLayerBelow(
              _basemapLayerId,
              _basemapSourceId,
              _basemapBelowLayerId,
            );
          } on Object {
            await controller.addImageLayer(_basemapLayerId, _basemapSourceId);
          }
          _basemapReady = true;
        } else {
          rethrow;
        }
      }
    }
    _loadedBasemapUrl = url;
  }

  Future<void> _addBasemapLayer(
    MapLibreMapController controller,
    Uint8List bytes,
    LatLngQuad quad,
  ) async {
    await controller.addImageSource(_basemapSourceId, bytes, quad);
    if (_useBlankMapStyle) {
      await controller.addImageLayer(_basemapLayerId, _basemapSourceId);
    } else {
      try {
        await controller.addImageLayerBelow(
          _basemapLayerId,
          _basemapSourceId,
          _basemapBelowLayerId,
        );
      } on Object {
        await controller.addImageLayer(_basemapLayerId, _basemapSourceId);
      }
    }
    _basemapReady = true;
  }

  /// Re-draw paths and POI pins on top of the basemap layer.
  Future<void> _syncMapContent() async {
    await _syncBasemap();
    await _syncAnnotations();
  }

  Future<void> _syncAnnotations() async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;

    try {
      await controller.clearLines();
      await controller.clearCircles();
      await controller.clearSymbols();
    } on Object {
      // Map may be mid-reload after hot restart.
      return;
    }
    _routeLine = null;
    _previewLine = null;
    _previewLines.clear();
    _connectionPointCircle = null;
    _connectionPointCircles.clear();
    _routeDotCircles.clear();
    _poiSymbols.clear();
    _poiLabelSymbols.clear();
    _poiCircles.clear();
    _vertexCircles.clear();

    if (widget.showEventPaths) {
      final lineColor = _useIllustratedBasemap ? '#FF6D00' : '#1565C0';
      final lineWidth = _useIllustratedBasemap ? 5.0 : 4.0;
      for (final edge in widget.data.edges) {
        await controller.addLine(
          LineOptions(
            geometry: edge.geometry
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            lineColor: lineColor,
            lineWidth: lineWidth,
            lineOpacity: widget.routeDotted ? 0.25 : 0.95,
          ),
        );
      }
    }

    if (widget.overlayEdges.isNotEmpty) {
      for (final edge in widget.overlayEdges) {
        await controller.addLine(
          LineOptions(
            geometry: edge.geometry
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            lineColor: widget.overlayEdgeColor,
            lineWidth: _useIllustratedBasemap ? 5.5 : 4.5,
            lineOpacity: 0.95,
          ),
        );
      }
    }

    if (widget.showPathVertices) {
      final vertexColor = _useIllustratedBasemap ? '#FF6D00' : '#1565C0';
      for (final vertex in widget.data.vertices) {
        final selected = vertex.id == widget.selectedVertexId;
        final circle = await controller.addCircle(
          CircleOptions(
            geometry: LatLng(vertex.lat, vertex.lng),
            circleRadius: selected ? 7 : (_useIllustratedBasemap ? 5 : 4),
            circleColor: selected ? '#D84315' : vertexColor,
            circleStrokeWidth: selected ? 2 : 1.5,
            circleStrokeColor: '#FFFFFF',
            draggable: widget.vertexDraggable &&
                widget.selectedVertexId == vertex.id,
          ),
        );
        _vertexCircles[vertex.id] = circle;
      }
    }

    if (widget.routePoints.length >= 2 && !_useFlutterRouteOverlay) {
      await _drawRoute(widget.routePoints);
    }

    if (widget.previewLines.isNotEmpty && !_useFlutterRouteOverlay) {
      await _drawPreviewLines();
    }

    for (final poi in widget.data.pois) {
      await _addPoiAnnotation(poi);
    }

    if (_useFlutterRouteOverlay) {
      await _routeOverlayKey.currentState?.updatePositions();
    }
  }

  void _updateOverlayPositions() {
    _overlayPositionThrottler.run(() {
      if (_useFlutterRouteOverlay) {
        _routeOverlayKey.currentState?.updatePositions();
      }
    });
  }

  Future<void> _fitToEventBounds() async {
    final controller = _controller;
    final bounds = widget.data.event.navigationBounds;
    if (!_useEventBounds || controller == null || bounds == null) return;

    final padding = widget.boundsFitPadding ?? EdgeInsets.zero;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds.toLatLngBounds(),
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
    );
  }

  CameraPosition _initialCamera() {
    if (_useEventBounds) {
      final bounds = widget.data.event.navigationBounds!;
      return CameraPosition(
        target: LatLng(bounds.centerLat, bounds.centerLng),
        zoom: bounds.estimateInitialZoom(),
      );
    }

    final center = widget.initialCenter ??
        (widget.data.event.centerLat != null && widget.data.event.centerLng != null
            ? ll.LatLng(widget.data.event.centerLat!, widget.data.event.centerLng!)
            : widget.data.vertices.isNotEmpty
                ? ll.LatLng(widget.data.vertices.first.lat, widget.data.vertices.first.lng)
                : widget.data.pois.isNotEmpty
                    ? ll.LatLng(widget.data.pois.first.lat, widget.data.pois.first.lng)
                    : const ll.LatLng(56.301, 10.479));

    return CameraPosition(
      target: LatLng(center.latitude, center.longitude),
      zoom: AppConstants.defaultZoom,
    );
  }

  void _handleCircleTapped(Circle circle) {
    for (final entry in _poiCircles.entries) {
      if (entry.value == circle) {
        final poi = widget.data.pois.firstWhere((p) => p.id == entry.key);
        widget.onPoiTapped?.call(poi);
        return;
      }
    }

    for (final entry in _vertexCircles.entries) {
      if (entry.value == circle) {
        final vertex = widget.data.vertices.firstWhere((v) => v.id == entry.key);
        widget.onVertexTapped?.call(vertex);
        return;
      }
    }
  }

  void _handleSymbolTapped(Symbol symbol) {
    for (final entry in _poiSymbols.entries) {
      if (entry.value == symbol) {
        final poi = widget.data.pois.firstWhere((p) => p.id == entry.key);
        widget.onPoiTapped?.call(poi);
        return;
      }
    }
    for (final entry in _poiLabelSymbols.entries) {
      if (entry.value == symbol) {
        final poi = widget.data.pois.firstWhere((p) => p.id == entry.key);
        widget.onPoiTapped?.call(poi);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationBounds = widget.data.event.navigationBounds;
    final cameraTargetBounds = _useEventBounds && navigationBounds != null
        ? navigationBounds.toCameraTargetBounds()
        : CameraTargetBounds.unbounded;

    return Stack(
      children: [
        MapLibreMap(
          styleString: _useBlankMapStyle
              ? AppConstants.illustratedOnlyMapStyle
              : AppConstants.mapStyleUrl,
          initialCameraPosition: _initialCamera(),
          cameraTargetBounds: cameraTargetBounds,
          compassEnabled: false,
          trackCameraPosition: _trackCameraForOverlays,
          attributionButtonPosition:
              widget.attributionButtonPosition ?? AttributionButtonPosition.topLeft,
          attributionButtonMargins: widget.attributionButtonMargins,
          featureTapsTriggersMapClick: widget.onMapTap != null,
          myLocationEnabled: widget.myLocationEnabled,
          myLocationRenderMode: widget.myLocationRenderMode,
          myLocationTrackingMode: widget.myLocationEnabled
              ? widget.myLocationTrackingMode
              : MyLocationTrackingMode.none,
          onMapCreated: (controller) {
            _controller = controller;
            controller.onSymbolTapped.add(_handleSymbolTapped);
            controller.onCircleTapped.add(_handleCircleTapped);
            _updateDragListener();
            widget.onMapCreated?.call(controller);
            if (_trackCameraForOverlays) {
              setState(() {});
            }
          },
          onStyleLoadedCallback: () async {
            _styleReady = true;
            _basemapReady = false;
            _loadedBasemapUrl = null;
            await _syncMapContent();
            if (_useEventBounds) {
              await _fitToEventBounds();
            }
            if (mounted) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            _updateOverlayPositions();
          },
          onCameraMove: (_) => _updateOverlayPositions(),
          onMapIdle: _updateOverlayPositions,
          onMapClick: widget.onMapTap == null
              ? null
              : (point, coordinates) => widget.onMapTap!(coordinates),
        ),
        if (_useFlutterRouteOverlay && _controller != null)
          Positioned.fill(
            child: RouteDotsOverlay(
              key: _routeOverlayKey,
              controller: _controller!,
              routePoints: widget.routePoints,
            ),
          ),
      ],
    );
  }
}
