import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' hide LatLng;
import 'package:maplibre_gl/maplibre_gl.dart' as ml show LatLng;

import '../../core/navigation/route_guidance.dart';
import '../../core/routing/routing_service.dart';
import '../../core/routing/treasure_hunt_path_network.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/poi_media.dart';
import '../../data/models/treasure_hunt.dart';
import '../../widgets/event_map_widget.dart';
import '../map_editor/widgets/treasure_hunt_post_overlay.dart';
import 'widgets/poi_audio_player.dart';
import 'widgets/poi_media_viewer.dart';
import 'widgets/visitor_map_controls.dart';
import 'widgets/visitor_turn_banner.dart';
import 'widgets/route_map_navigation_camera.dart';
import 'widgets/visitor_recenter_chip.dart';

/// Besøgskort med kun skattejagt — navigation følger officielle + jagtstier.
class VisitorTreasureHuntScreen extends StatefulWidget {
  const VisitorTreasureHuntScreen({
    super.key,
    required this.mapData,
    required this.hunt,
    this.embed = false,
  });

  final EventMapData mapData;
  final TreasureHuntConfig hunt;
  final bool embed;

  @override
  State<VisitorTreasureHuntScreen> createState() =>
      _VisitorTreasureHuntScreenState();
}

class _VisitorTreasureHuntScreenState extends State<VisitorTreasureHuntScreen> {
  final _routing = RoutingService();
  final _overlayKey = GlobalKey<TreasureHuntPostOverlayState>();

  MapLibreMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  ll.LatLng? _userLocation;
  TreasureHuntPost? _targetPost;
  var _isNavigating = false;
  var _mapFollowing = true;
  var _programmaticCameraMove = false;
  Position? _lastPosition;
  List<ll.LatLng> _routePoints = [];
  List<RouteManeuver> _maneuvers = const [];
  NavigationInstruction? _instruction;
  String? _status;

  late TreasureHuntRoutingNetwork _network;

  List<TreasureHuntPost> get _posts => widget.hunt.orderedPosts;

  @override
  void initState() {
    super.initState();
    _network = TreasureHuntRoutingNetwork.fromEvent(
      data: widget.mapData,
      hunt: widget.hunt,
    );
    _targetPost = _posts.isNotEmpty ? _posts.first : null;
    _startLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController = null;
    super.dispose();
  }

  Future<void> _startLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() => _status = 'Slå GPS til for at finde vej mellem poster');
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _status = 'Giv adgang til placering for navigation');
      }
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      ),
    ).listen(
      (position) {
        if (!mounted) return;
        _lastPosition = position;
        setState(() {
          _userLocation = ll.LatLng(position.latitude, position.longitude);
        });
        if (_isNavigating && _targetPost != null) {
          _recomputeRoute(position);
          _updateTurnByTurn(position);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _status = 'Placeringsfejl — prøv igen');
      },
    );
  }

  void _recomputeRoute(Position position) {
    final target = _targetPost;
    if (target == null) return;

    final plan = _routing.planRouteBetweenCoordinates(
      startLat: position.latitude,
      startLng: position.longitude,
      goalLat: target.lat,
      goalLng: target.lng,
      vertices: _network.vertices,
      edges: _network.edges,
    );

    if (!mounted) return;
    setState(() {
      if (plan == null) {
        _routePoints = [];
        _maneuvers = const [];
        _status = 'Ingen sti fundet til ${target.displayTitle}';
        return;
      }
      _routePoints = plan.points;
      _maneuvers = buildRouteManeuvers(plan.points);
      _status = null;
    });
  }

  void _updateTurnByTurn(Position position) {
    if (_routePoints.length < 2 || _maneuvers.isEmpty) return;
    final heading = position.heading >= 0 ? position.heading : null;
    final instruction = buildNavigationInstruction(
      route: _routePoints,
      maneuvers: _maneuvers,
      lat: position.latitude,
      lng: position.longitude,
      userHeading: heading,
    );
    if (!mounted) return;
    setState(() => _instruction = instruction);
    if (_mapFollowing && instruction != null) {
      unawaited(_updateNavigationCamera(position, instruction));
    }
  }

  Future<void> _updateNavigationCamera(
    Position position,
    NavigationInstruction instruction,
  ) async {
    await RouteMapNavigationCamera.animateToInstruction(
      controller: _mapController,
      position: position,
      instruction: instruction,
      setProgrammaticFlag: (value) => _programmaticCameraMove = value,
    );
  }

  void _onMapCameraMoved() {
    if (_programmaticCameraMove || !mounted) return;
    if (_isNavigating && _mapFollowing) {
      setState(() => _mapFollowing = false);
    }
  }

  void _onCameraTrackingDismissed() {
    if (!mounted) return;
    if (_isNavigating && _mapFollowing) {
      setState(() => _mapFollowing = false);
    }
  }

  void _beginNavigationTo(TreasureHuntPost post) {
    setState(() {
      _targetPost = post;
      _isNavigating = true;
      _mapFollowing = true;
      _instruction = null;
    });
    final location = _userLocation;
    if (location != null) {
      final position = Position(
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: _lastPosition?.heading ?? 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
      _recomputeRoute(position);
      _updateTurnByTurn(position);
    }
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _mapFollowing = true;
      _instruction = null;
      _routePoints = [];
      _maneuvers = const [];
    });
  }

  Future<void> _recenterOnUser() async {
    final controller = _mapController;
    final location = _userLocation;
    if (controller == null || location == null || !mounted) return;

    if (_isNavigating) {
      setState(() => _mapFollowing = true);
      final position = _lastPosition ??
          Position(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
      if (_instruction != null) {
        await _updateNavigationCamera(position, _instruction!);
      } else {
        await RouteMapNavigationCamera.animateToUser(
          controller: controller,
          lat: location.latitude,
          lng: location.longitude,
          setProgrammaticFlag: (value) => _programmaticCameraMove = value,
        );
      }
      return;
    }

    try {
      await RouteMapNavigationCamera.animateToUser(
        controller: controller,
        lat: location.latitude,
        lng: location.longitude,
        setProgrammaticFlag: (value) => _programmaticCameraMove = value,
        zoom: 17,
      );
    } on Object {
      // Native map may be gone after leaving the screen.
    }
  }

  Future<void> _zoomIn() async {
    if (!mounted) return;
    try {
      await _mapController?.animateCamera(CameraUpdate.zoomIn());
    } on Object {
      // Ignore if map is gone.
    }
  }

  Future<void> _zoomOut() async {
    if (!mounted) return;
    try {
      await _mapController?.animateCamera(CameraUpdate.zoomOut());
    } on Object {
      // Ignore if map is gone.
    }
  }

  void _showPost(TreasureHuntPost post) {
    final nextPost = post.hasNextPost
        ? widget.hunt.postById(post.nextPostId!)
        : null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final visualMedia = post.media
            .where((item) => item.kind != PoiMediaKind.audio)
            .toList();
        final audioClips =
            post.media.where((item) => item.kind == PoiMediaKind.audio).toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.displayTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (post.bodyText != null && post.bodyText!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(post.bodyText!),
                  ],
                  if (visualMedia.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    PoiMediaViewer(media: visualMedia),
                  ],
                  for (final clip in audioClips) ...[
                    const SizedBox(height: 12),
                    PoiAudioPlayer(clip: clip),
                  ],
                  if (nextPost != null) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _beginNavigationTo(nextPost);
                      },
                      icon: const Icon(Icons.directions_walk),
                      label: Text('Gå til ${nextPost.displayTitle}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embed
          ? null
          : AppBar(
              title: Text(widget.hunt.landingHeadline),
            ),
      body: Stack(
        children: [
          EventMapWidget(
            data: widget.mapData,
            routePoints: _routePoints,
            routeDotted: _isNavigating,
            showIllustratedBasemap: true,
            showEventPaths: true,
            showPathVertices: false,
            showPoiMarkers: false,
            overlayEdges: _network.huntEdges,
            myLocationEnabled: true,
            myLocationRenderMode: MyLocationRenderMode.compass,
            myLocationTrackingMode: MyLocationTrackingMode.none,
            onCameraMove: _onMapCameraMoved,
            onCameraTrackingDismissed: _onCameraTrackingDismissed,
            onMapCreated: (controller) {
              _mapController = controller;
              setState(() {});
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _overlayKey.currentState?.updatePositions();
              });
            },
          ),
          if (_mapController != null)
            TreasureHuntPostOverlay(
              key: _overlayKey,
              controller: _mapController!,
              posts: _posts,
              selectedPostId: _targetPost?.id,
              onPostTapped: _showPost,
            ),
          if (_isNavigating && _instruction != null && _targetPost != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: VisitorTurnBanner(
                instruction: _instruction!,
                destinationLabel: _targetPost!.displayTitle,
                onStop: _stopNavigation,
              ),
            ),
          if (_isNavigating && !_mapFollowing)
            VisitorRecenterChip(
              onTap: _recenterOnUser,
              bottom: 80,
            ),
          if (_status != null && !_isNavigating)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_status!, textAlign: TextAlign.center),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: VisitorMapControls(
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onRecenter: _recenterOnUser,
            ),
          ),
        ],
      ),
    );
  }
}
