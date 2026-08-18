import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/navigation/route_guidance.dart';
import '../../core/search/poi_search.dart';
import '../../core/storage/organizer_session_persistence.dart';
import '../../core/routing/routing_service.dart';
import '../../core/storage/visitor_favorites_storage.dart';
import '../../core/utils/debounce.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../auth/sign_in_screen.dart';
import '../../data/models/audio_tour.dart';
import '../home/home_screen.dart';
import '../map_setup/map_setup_flow.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/poi_topic.dart';
import '../../widgets/event_map_widget.dart';
import 'widgets/visitor_map_controls.dart';
import 'widgets/visitor_bottom_nav.dart';
import 'widgets/visitor_destination_preview.dart';
import 'widgets/visitor_poi_topic_filter_bar.dart';
import 'widgets/visitor_poi_topic_sheets.dart';
import 'widgets/visitor_search_suggestions.dart';
import 'widgets/visitor_turn_banner.dart';
import 'widgets/visitor_audio_tour_bar.dart';
import 'widgets/route_map_navigation_camera.dart';
import 'widgets/visitor_recenter_chip.dart';
import 'audio_tour_guidance_controller.dart';
import 'visitor_experience.dart';
import 'visitor_experience_picker_screen.dart';

class VisitorMapScreen extends StatefulWidget {
  const VisitorMapScreen({
    super.key,
    required this.mapData,
    this.experience = VisitorExperience.search,
    this.audioTourConfig,
    this.initialSearch,
    this.embed = false,
    this.organizerPreview = false,
  });

  final EventMapData mapData;
  final VisitorExperience experience;
  final AudioTourConfig? audioTourConfig;
  final String? initialSearch;
  final bool embed;
  final bool organizerPreview;

  @override
  State<VisitorMapScreen> createState() => _VisitorMapScreenState();
}

class _VisitorMapScreenState extends State<VisitorMapScreen> {
  final _routing = RoutingService();
  final _repository = EventRepository();
  final _auth = AuthRepository();
  final _favoritesStorage = VisitorFavoritesStorage();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  late EventMapData _data;
  VisitorTab _tab = VisitorTab.map;
  MapPoi? _selectedPoi;
  bool _isNavigating = false;
  Set<String> _favoriteIds = {};
  StreamSubscription<Position>? _positionSub;
  MapLibreMapController? _mapController;
  ll.LatLng? _userLocation;
  List<ll.LatLng> _routePoints = [];
  List<RouteManeuver> _maneuvers = const [];
  NavigationInstruction? _instruction;
  String _startLabel = 'Din placering';
  double _distanceMeters = 0;
  double _approachMeters = 0;
  double _departureMeters = 0;
  String? _status;
  String _query = '';
  List<MapPoi> _searchSuggestions = const [];
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 200));
  var _routeComputeGeneration = 0;
  AudioTourGuidanceController? _audioTourController;
  Set<PoiTopic> _activeTopics = PoiTopic.values.toSet();
  bool _gpsReady = false;
  bool _audioTourMapFollowing = true;
  bool _searchMapFollowing = true;
  bool _programmaticCameraMove = false;
  NavigationInstruction? _audioTourInstruction;
  List<RouteManeuver> _audioTourManeuvers = const [];
  List<ll.LatLng> _lastAudioTourGuidedRoute = const [];
  Position? _lastPosition;
  double? _movementHeading;
  ll.LatLng? _previousPositionForHeading;

  bool get _showTopicFilters => !_isAudioTourMode;

  bool get _isSearchMode => widget.experience == VisitorExperience.search;
  bool get _isExploreMode => widget.experience == VisitorExperience.explore;
  bool get _isAudioTourMode => widget.experience == VisitorExperience.audioTour;

  bool get _audioTourGuiding =>
      _isAudioTourMode &&
      _gpsReady &&
      !widget.organizerPreview &&
      (_audioTourController?.isGuidingToStop ?? false);

  double? get _userHeading {
    final heading = _lastPosition?.heading;
    if (heading != null && heading >= 0) return heading;
    return _movementHeading;
  }

  bool get _userLocationNavigating => _isNavigating || _audioTourGuiding;

  AudioTourConfig? get _activeAudioTour =>
      widget.audioTourConfig ?? _data.audioTourCatalog.primaryTour;

  EventMapData get _displayData {
    if (_isAudioTourMode) {
      final tour = _activeAudioTour;
      if (tour != null) {
        return _data.copyWith(pois: _data.audioTourStopsFor(tour));
      }
    }
    return _data;
  }

  EventMapData get _mapDisplayData => _displayData;

  @override
  void initState() {
    super.initState();
    _data = widget.mapData;
    _query = widget.initialSearch?.trim() ?? '';
    _searchController.text = _query;
    if (_query.isNotEmpty) {
      _refreshSearchSuggestions();
    }
    if (_isAudioTourMode && _data.hasAudioTour) {
      final tour = _activeAudioTour;
      if (tour != null) {
        _audioTourController = AudioTourGuidanceController(
          data: _data,
          config: tour,
        );
        _audioTourController!.addListener(_onAudioTourChanged);
      }
      _gpsReady = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFavorites();
      if (!widget.organizerPreview) {
        _startTracking();
      }
    });
  }

  void _onAudioTourChanged() {
    if (!mounted) return;

    final controller = _audioTourController;
    if (controller == null) {
      setState(() {});
      return;
    }

    if (controller.isGuidingToStop) {
      final route = controller.routePoints;
      if (!_sameRoute(route, _lastAudioTourGuidedRoute)) {
        _lastAudioTourGuidedRoute = List<ll.LatLng>.from(route);
        _audioTourMapFollowing = true;
        _syncAudioTourManeuvers(route);
      }
    } else {
      _lastAudioTourGuidedRoute = const [];
      _audioTourInstruction = null;
      _audioTourManeuvers = const [];
    }

    setState(() {});
  }

  bool _sameRoute(List<ll.LatLng> a, List<ll.LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  void _syncAudioTourManeuvers(List<ll.LatLng> route) {
    if (route.length < 2) {
      _audioTourManeuvers = const [];
      return;
    }
    _audioTourManeuvers = buildRouteManeuvers(route);
  }

  void _updateAudioTourTurnByTurn(Position position) {
    final controller = _audioTourController;
    if (controller == null || !_audioTourMapFollowing) return;

    final route = controller.routePoints;
    if (route.length < 2) return;

    _syncAudioTourManeuvers(route);
    final heading = position.heading >= 0 ? position.heading : null;
    final instruction = buildNavigationInstruction(
      route: route,
      maneuvers: _audioTourManeuvers,
      lat: position.latitude,
      lng: position.longitude,
      userHeading: heading,
    );

    if (!mounted) return;
    setState(() => _audioTourInstruction = instruction);
    if (instruction != null) {
      unawaited(_updateNavigationCamera(position, instruction));
    }
  }

  void _onMapCameraMoved() {
    if (_programmaticCameraMove || !mounted) return;
    if (_audioTourGuiding && _audioTourMapFollowing) {
      setState(() => _audioTourMapFollowing = false);
      return;
    }
    if (_isNavigating && _searchMapFollowing) {
      setState(() => _searchMapFollowing = false);
    }
  }

  void _onCameraTrackingDismissed() {
    if (!mounted) return;
    if (_audioTourGuiding && _audioTourMapFollowing) {
      setState(() => _audioTourMapFollowing = false);
      return;
    }
    if (_isNavigating && _searchMapFollowing) {
      setState(() => _searchMapFollowing = false);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController = null;
    _searchDebouncer.dispose();
    _audioTourController?.removeListener(_onAudioTourChanged);
    _audioTourController?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final ids = await _favoritesStorage.load(_data.event.id);
    if (mounted) setState(() => _favoriteIds = ids);
  }

  Future<void> _startTracking() async {
    final audioTour = _isAudioTourMode;

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted && !audioTour) {
        setState(() {
          _status = 'GPS er slået fra';
          _gpsReady = false;
        });
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && !audioTour) {
      permission = await Geolocator.requestPermission();
    }

    final hasPermission = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    if (!hasPermission && !audioTour) {
      if (mounted) {
        setState(() {
          _status = 'Ingen adgang til placering';
          _gpsReady = false;
        });
      }
      return;
    }

    if (mounted && !audioTour) setState(() => _gpsReady = true);

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      _onPosition,
      onError: (_) {
        if (!mounted || audioTour) return;
        setState(() {
          _status = 'Placeringsfejl — prøv igen';
          _gpsReady = false;
        });
      },
    );

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _onPosition(current);
    } on Object {
      // Stream delivers the first fix when ready.
    }
  }

  void _applyPosition(Position position) {
    _userLocation = ll.LatLng(position.latitude, position.longitude);
    _startLabel = locationLabelNear(
      lat: position.latitude,
      lng: position.longitude,
      vertices: _data.vertices,
      pois: _data.pois,
    );
  }

  void _updateMovementHeading(Position position) {
    if (position.heading >= 0) {
      _movementHeading = position.heading;
      return;
    }

    final current = ll.LatLng(position.latitude, position.longitude);
    final previous = _previousPositionForHeading;
    _previousPositionForHeading = current;
    if (previous == null) return;

    const distance = ll.Distance();
    if (distance(previous, current) < 2) return;
    _movementHeading = bearingDegrees(previous, current);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    _lastPosition = position;
    _applyPosition(position);
    _updateMovementHeading(position);

    if (_isAudioTourMode && _audioTourController != null) {
      if (!_gpsReady) _gpsReady = true;
      _audioTourController!.updateLocation(position.latitude, position.longitude);
      if (_audioTourGuiding && _audioTourMapFollowing) {
        _updateAudioTourTurnByTurn(position);
        return;
      }
      setState(() {});
      return;
    }

    if (_selectedPoi == null) {
      setState(() {});
      return;
    }

    if (_isNavigating) {
      _recomputeRoute(position);
      _updateTurnByTurn(position);
      return;
    }

    _scheduleRouteRefresh(position);
    setState(() {});
  }

  Position? _pendingRoutePosition;
  bool _routeRefreshScheduled = false;

  void _scheduleRouteRefresh(Position position) {
    _pendingRoutePosition = position;
    if (_routeRefreshScheduled) return;
    _routeRefreshScheduled = true;
    scheduleMicrotask(() {
      _routeRefreshScheduled = false;
      final pending = _pendingRoutePosition;
      if (pending == null || !mounted || _selectedPoi == null || _isNavigating) {
        return;
      }
      _recomputeRoute(pending);
      if (mounted) setState(() {});
    });
  }

  void _refreshSearchSuggestions() {
    _searchSuggestions = PoiSearch.suggest(_data.pois, _query);
  }

  void _onSearchChanged(String value) {
    final trimmed = value.trim();
    _searchDebouncer.run(() {
      if (!mounted) return;

      final selected = _selectedPoi;
      final keepsSelection = selected != null &&
          (trimmed == selected.displayTitle ||
              trimmed == selected.navigationLabel);

      setState(() {
        _query = trimmed;
        _refreshSearchSuggestions();
        if (selected != null && !keepsSelection) {
          _selectedPoi = null;
          _routePoints = [];
          _maneuvers = const [];
          _distanceMeters = 0;
          _approachMeters = 0;
          _departureMeters = 0;
          _instruction = null;
          _isNavigating = false;
          _status = null;
        }
      });
    });
  }

  String? get _routePreviewHint {
    if (_selectedPoi == null) return null;
    if (_userLocation == null) {
      return _status ?? 'Henter din placering…';
    }
    if (_routePoints.length < 2) {
      return _status ?? 'Beregner rute…';
    }
    return null;
  }

  bool get _canStartNavigation =>
      _routePoints.length >= 2 && _userLocation != null;

  void _recomputeRoute(Position position) {
    final poi = _selectedPoi;
    if (poi == null) return;

    final plan = _routing.planRouteToPoi(
      lat: position.latitude,
      lng: position.longitude,
      vertices: _data.vertices,
      edges: _data.edges,
      poi: poi,
      pois: _data.pois,
    );

    if (plan == null) {
      _applyRouteFailure(poi);
      return;
    }

    _routePoints = plan.points;
    _maneuvers = buildRouteManeuvers(plan.points);
    _distanceMeters = plan.totalMeters;
    _approachMeters = plan.approachMeters;
    _departureMeters = plan.departureMeters;
    _status = plan.points.length >= 2 ? null : 'Ingen rute fundet';
  }

  void _applyRouteFailure(MapPoi poi) {
    _routePoints = [];
    _maneuvers = const [];
    _distanceMeters = 0;
    _approachMeters = 0;
    _departureMeters = 0;
    _instruction = null;
    _status = _data.vertices.isEmpty || _data.edges.isEmpty
        ? 'Der er endnu ingen stier på kortet'
        : 'Ingen sti fundet i nærheden af stedet';
  }

  void _updateTurnByTurn(Position position) {
    if (!mounted) return;
    if (_routePoints.length < 2) {
      setState(() {});
      return;
    }

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
    if (_searchMapFollowing) {
      unawaited(_updateNavigationCamera(position, instruction));
    }
  }

  Future<void> _updateNavigationCamera(
    Position position,
    NavigationInstruction? instruction,
  ) async {
    if (instruction == null || !mounted) return;
    await RouteMapNavigationCamera.animateToInstruction(
      controller: _mapController,
      position: position,
      instruction: instruction,
      setProgrammaticFlag: (value) => _programmaticCameraMove = value,
    );
  }

  void _submitSearch() {
    final suggestions = _searchSuggestions;
    if (suggestions.isNotEmpty) {
      _selectDestination(suggestions.first);
      return;
    }

    setState(() {
      _selectedPoi = null;
      _isNavigating = false;
      _routePoints = [];
      _maneuvers = const [];
      _instruction = null;
      _distanceMeters = 0;
      _approachMeters = 0;
      _departureMeters = 0;
      _status = null;
      _tab = VisitorTab.map;
    });
    _searchFocus.unfocus();
  }

  List<MapPoi> get _favoritePois {
    return _data.pois.where((p) => _favoriteIds.contains(p.id)).toList()
      ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
  }

  void _selectDestination(MapPoi poi) {
    _searchDebouncer.cancel();
    _searchFocus.unfocus();
    setState(() {
      _selectedPoi = poi;
      _isNavigating = false;
      _instruction = null;
      _routePoints = [];
      _maneuvers = const [];
      _distanceMeters = 0;
      _approachMeters = 0;
      _departureMeters = 0;
      _status = null;
      _query = poi.displayTitle;
      _searchController.text = poi.navigationLabel;
      _tab = VisitorTab.map;
    });
    unawaited(_recomputeRouteForCurrentLocation());
  }

  void _beginNavigation() {
    if (!_canStartNavigation) return;

    setState(() {
      _isNavigating = true;
      _searchMapFollowing = true;
    });
    unawaited(_startNavigationTurnByTurn());
  }

  Future<void> _startNavigationTurnByTurn() async {
    await _recomputeRouteForCurrentLocation();
    if (!mounted || !_isNavigating || _userLocation == null) return;

    final location = _userLocation!;
    _updateTurnByTurn(
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
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedPoi = null;
      _isNavigating = false;
      _routePoints = [];
      _maneuvers = const [];
      _instruction = null;
      _distanceMeters = 0;
      _approachMeters = 0;
      _departureMeters = 0;
      _status = null;
    });
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _instruction = null;
    });
    unawaited(_recomputeRouteForCurrentLocation());
  }

  Future<void> _recomputeRouteForCurrentLocation() async {
    final poi = _selectedPoi;
    if (poi == null) return;

    final generation = ++_routeComputeGeneration;
    var location = _userLocation;

    if (location == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        );
        if (!mounted || generation != _routeComputeGeneration) return;
        _applyPosition(position);
        location = _userLocation;
      } on Object {
        if (!mounted || generation != _routeComputeGeneration) return;
        setState(() => _status = 'Kunne ikke finde din placering');
        return;
      }
    }

    if (location == null) return;

    _recomputeRoute(
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
      ),
    );
    if (!mounted || generation != _routeComputeGeneration) return;
    setState(() {});
  }

  void _showPoiInfo(MapPoi poi) {
    final isDestination = _selectedPoi?.id == poi.id;
    showVisitorPoiTopicPicker(
      context,
      poi: poi,
      activeTopics: _activeTopics,
      isDestination: isDestination,
      onNavigateHere: _isSearchMode && !isDestination
          ? () => _selectDestination(poi)
          : null,
    );
  }

  void _handlePoiTap(MapPoi poi) {
    _showPoiInfo(poi);
  }

  void _backToExperiencePicker() {
    _audioTourController?.startTour();
    if (widget.organizerPreview) {
      Navigator.pop(context);
      return;
    }
    final options = availableExperiences(_data);
    if (options.length <= 1) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorExperiencePickerScreen(
          mapData: _data,
          embed: widget.embed,
        ),
      ),
    );
  }

  void _switchExperience() {
    _audioTourController?.startTour();
    _clearSelection();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorExperiencePickerScreen(
          mapData: _data,
          embed: widget.embed,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(MapPoi poi) async {
    final isFav = await _favoritesStorage.toggle(_data.event.id, poi.id);
    if (!mounted) return;
    setState(() {
      if (isFav) {
        _favoriteIds.add(poi.id);
      } else {
        _favoriteIds.remove(poi.id);
      }
    });
  }

  Future<void> _recenterOnUser() async {
    final controller = _mapController;
    final location = _userLocation;
    if (controller == null || location == null || !mounted) return;

    try {
      if (_audioTourGuiding) {
        setState(() => _audioTourMapFollowing = true);
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
        if (_audioTourInstruction != null) {
          await _updateNavigationCamera(position, _audioTourInstruction);
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

      if (_isNavigating) {
        setState(() => _searchMapFollowing = true);
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
          await _updateNavigationCamera(position, _instruction);
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

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          AppConstants.defaultZoom,
        ),
      );
    } on Object {
      // Native map may be gone after leaving the screen.
    }
  }

  void _onTabChanged(VisitorTab tab) {
    setState(() => _tab = tab);
    if (tab == VisitorTab.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
    }
    if (tab == VisitorTab.favorites) {
      _showFavoritesSheet();
    } else if (tab == VisitorTab.menu) {
      _showMenuSheet();
    }
  }

  Future<void> _showFavoritesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final favorites = _favoritePois;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Favoritter',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (favorites.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Ingen favoritter endnu — tryk ♥ på et sted'),
                )
              else
                ...favorites.map(
                  (poi) => ListTile(
                    leading: const Icon(Icons.favorite, color: Colors.red),
                    title: Text(poi.displayTitle),
                    subtitle: Text(poi.displaySubtitle),
                    onTap: () {
                      Navigator.pop(context);
                      _selectDestination(poi);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (mounted) setState(() => _tab = VisitorTab.map);
  }

  Future<void> _showMenuSheet() async {
    if (!mounted || widget.embed) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_data.event.name, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(_data.event.description ?? 'Plotspotting gæstekort'),
            ),
            if (_data.event.publicSlug != null)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(AppConstants.publicEventUrl(_data.event.publicSlug!)),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Rediger kort'),
              subtitle: const Text('Kræver login med adgang til workspace'),
              onTap: () {
                Navigator.pop(context);
                _openAdminEditor();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Administration'),
              subtitle: const Text('Opret events, seneste kort og indstillinger'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              },
            ),
            if (availableExperiences(_data).length > 1)
              ListTile(
                leading: const Icon(Icons.apps_outlined),
                title: const Text('Skift oplevelse'),
                subtitle: const Text('Find et sted, opdagelse eller lydvandring'),
                onTap: () {
                  Navigator.pop(context);
                  _switchExperience();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Luk kort'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _tab = VisitorTab.map);
  }

  Future<void> _openAdminEditor() async {
    if (!_auth.isSignedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SignInScreen()),
      );
      if (!_auth.isSignedIn || !mounted) return;
    }

    try {
      final data = await _repository.loadForEdit(eventId: _data.event.id);
      await persistOrganizerSession(
        eventId: _data.event.id,
        eventName: data.event.name,
        publicSlug: data.event.publicSlug,
      );
      if (!mounted) return;
      await MapSetupFlow.openEditorOrSetup(
        context,
        eventId: _data.event.id,
        eventName: data.event.name,
        data: data,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke åbne redigering: $error')),
      );
    }
  }

  Future<void> _zoomIn() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;
    try {
      await controller.animateCamera(CameraUpdate.zoomIn());
    } on Object {
      // Native map may be gone after leaving the screen.
    }
  }

  Future<void> _zoomOut() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;
    try {
      await controller.animateCamera(CameraUpdate.zoomOut());
    } on Object {
      // Native map may be gone after leaving the screen.
    }
  }

  EdgeInsets _mapFitPadding(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    const leftFilter = 44.0;
    final bottomInset = widget.embed ? 16.0 : 112.0;
    if (_isAudioTourMode) {
      return EdgeInsets.fromLTRB(leftFilter, topInset + 56, 20, widget.embed ? 148 : 168);
    }
    if (_isSearchMode) {
      return EdgeInsets.fromLTRB(leftFilter, topInset + 88, 20, bottomInset);
    }
    return EdgeInsets.fromLTRB(leftFilter, topInset + 56, 20, bottomInset);
  }

  bool get _showSearchSuggestions =>
      _isSearchMode &&
      _query.isNotEmpty &&
      !_isNavigating &&
      _selectedPoi == null;

  double get _searchOverlayMaxHeight {
    if (!_showSearchSuggestions) return 0;
    return 240;
  }

  @override
  Widget build(BuildContext context) {
    final hasIllustrated = _data.event.hasIllustratedBasemap;
    final audioTour = _audioTourController;
    final showAudioRoute = _isAudioTourMode &&
        audioTour != null &&
        _gpsReady &&
        audioTour.routePoints.length >= 2 &&
        audioTour.isGuidingToStop;
    final showRoute = _isSearchMode && _selectedPoi != null && _routePoints.length >= 2;
    final displayData = _mapDisplayData;
    final audioTargetId = _isAudioTourMode ? audioTour?.currentTargetPoi?.id : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: EventMapWidget(
                      data: displayData,
                      routePoints: showRoute
                          ? _routePoints
                          : showAudioRoute
                              ? audioTour.routePoints
                              : const [],
                      initialCenter: _data.event.centerLat != null && _data.event.centerLng != null
                          ? ll.LatLng(_data.event.centerLat!, _data.event.centerLng!)
                          : null,
                      constrainToEventBounds: true,
                      boundsFitPadding: _mapFitPadding(context),
                      userLocation:
                          !widget.organizerPreview ? _userLocation : null,
                      userHeading: _userHeading,
                      userLocationNavigating: _userLocationNavigating,
                      showPathVertices: false,
                      showEventPaths: !hasIllustrated,
                      showIllustratedBasemap: true,
                      showPoiMarkers: true,
                      destinationPoiId: _isSearchMode
                          ? _selectedPoi?.id
                          : audioTargetId,
                      routeDotted: showRoute || showAudioRoute,
                      illustratedMapOnly: hasIllustrated,
                      onPoiTapped: _handlePoiTap,
                      onMapCreated: (c) => _mapController = c,
                      onCameraMove: _onMapCameraMoved,
                      onCameraTrackingDismissed: _onCameraTrackingDismissed,
                      attributionButtonPosition: _isSearchMode
                          ? AttributionButtonPosition.topRight
                          : AttributionButtonPosition.bottomLeft,
                      attributionButtonMargins: Point(
                        8,
                        _isSearchMode
                            ? MediaQuery.paddingOf(context).top + 8
                            : 8,
                      ),
                    ),
                  ),
                  ),
                  if (!_isSearchMode && !widget.embed)
                    Positioned(
                      top: 8,
                      left: 16,
                      child: Material(
                        elevation: 3,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: IconButton(
                          tooltip: 'Tilbage',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _backToExperiencePicker,
                        ),
                      ),
                    ),
                  if (!_isSearchMode && !widget.embed)
                    Positioned(
                      top: 8,
                      right: 16,
                      child: Material(
                        elevation: 3,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: IconButton(
                          tooltip: 'Menu',
                          icon: const Icon(Icons.menu),
                          onPressed: _showMenuSheet,
                        ),
                      ),
                    ),
                  if (_isSearchMode)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              elevation: 3,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(28),
                              child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              readOnly: _isNavigating,
                              decoration: InputDecoration(
                                hintText: 'Søg destination…',
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF1565C0)),
                                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _searchController,
                                  builder: (context, value, _) {
                                    if (value.text.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: _isNavigating
                                          ? _stopNavigation
                                          : () {
                                              _searchController.clear();
                                              _searchDebouncer.cancel();
                                              setState(() {
                                                _query = '';
                                                _searchSuggestions = const [];
                                                _selectedPoi = null;
                                                _isNavigating = false;
                                                _routePoints = [];
                                                _maneuvers = const [];
                                                _instruction = null;
                                                _distanceMeters = 0;
                                                _approachMeters = 0;
                                                _status = null;
                                              });
                                            },
                                    );
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onChanged: _isNavigating ? null : _onSearchChanged,
                              onSubmitted: (_) => _submitSearch(),
                            ),
                          ),
                          if (_isNavigating && _instruction != null && _selectedPoi != null) ...[
                            const SizedBox(height: 10),
                            VisitorTurnBanner(
                              instruction: _instruction!,
                              destinationLabel: _selectedPoi!.navigationLabel,
                              onStop: _stopNavigation,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Tryk på et sted på kortet for info',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      shadows: const [
                                        Shadow(color: Colors.black54, blurRadius: 4),
                                      ],
                                    ),
                              ),
                            ),
                          ] else if (_selectedPoi != null) ...[
                            const SizedBox(height: 10),
                            VisitorDestinationPreview(
                              startLabel: _startLabel,
                              destinationLabel: _selectedPoi!.navigationLabel,
                              distanceMeters: _routePoints.length >= 2 ? _distanceMeters : null,
                              canStart: _canStartNavigation,
                              approachMeters: _approachMeters,
                              departureMeters: _departureMeters,
                              statusHint: _routePreviewHint,
                              onStartRoute: _beginNavigation,
                              onClose: _clearSelection,
                            ),
                          ] else if (_status != null && _query.isEmpty) ...[
                            const SizedBox(height: 10),
                            Material(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.orange.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_status!, style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ],
                          if (_searchOverlayMaxHeight > 0) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: _searchOverlayMaxHeight),
                              child: Material(
                                elevation: 3,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  child: VisitorSearchSuggestions(
                                    query: _query,
                                    results: _searchSuggestions,
                                    favoriteIds: _favoriteIds,
                                    onToggleFavorite: _toggleFavorite,
                                    onSelect: _selectDestination,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: _isAudioTourMode ? 148 : 16,
                    child: VisitorMapControls(
                      onZoomIn: _zoomIn,
                      onZoomOut: _zoomOut,
                      onRecenter: _recenterOnUser,
                    ),
                  ),
                  if (_isAudioTourMode && audioTour != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: VisitorAudioTourBar(controller: audioTour),
                    ),
                  if (_isExploreMode)
                    Positioned(
                      top: 12,
                      left: 72,
                      right: 72,
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withValues(alpha: 0.94),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text(
                            widget.experience.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ),
                  if (_isAudioTourMode)
                    Positioned(
                      top: 12,
                      left: 72,
                      right: 72,
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withValues(alpha: 0.94),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text(
                            widget.experience.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ),
                  if (_audioTourGuiding &&
                      _audioTourInstruction != null &&
                      audioTour?.currentTargetPoi != null)
                    Positioned(
                      top: 56,
                      left: 16,
                      right: 16,
                      child: VisitorTurnBanner(
                        instruction: _audioTourInstruction!,
                        destinationLabel: audioTour!.currentTargetPoi!.displayTitle,
                        onStop: () => setState(() => _audioTourMapFollowing = false),
                      ),
                    ),
                  if (_audioTourGuiding && !_audioTourMapFollowing)
                    VisitorRecenterChip(
                      onTap: _recenterOnUser,
                      bottom: 168,
                    ),
                  if (_isNavigating && !_searchMapFollowing)
                    VisitorRecenterChip(
                      onTap: _recenterOnUser,
                      bottom: 16,
                    ),
                  if (_showTopicFilters)
                    Positioned(
                      left: 0,
                      top: _isSearchMode ? 96 : 72,
                      bottom: _isAudioTourMode ? 160 : 96,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: VisitorPoiTopicFilterDrawer(
                          activeTopics: _activeTopics,
                          onChanged: (topics) => setState(() => _activeTopics = topics),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_isSearchMode && !widget.embed)
              VisitorBottomNav(
                current: _tab,
                onChanged: _onTabChanged,
              ),
          ],
        ),
      ),
    );
  }
}
