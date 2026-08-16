import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/geo/geo_utils.dart';
import '../../core/routing/routing_service.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_poi.dart';
import '../../widgets/event_map_widget.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.mapData,
    required this.destination,
  });

  final EventMapData mapData;
  final MapPoi destination;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _routing = RoutingService();
  StreamSubscription<Position>? _positionSub;
  ll.LatLng? _userLocation;
  List<ll.LatLng> _routePoints = [];
  double _distanceMeters = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = 'GPS er slået fra');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Ingen adgang til placering');
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(_updateRoute);

    final current = await Geolocator.getCurrentPosition();
    _updateRoute(current);
  }

  void _updateRoute(Position position) {
    final plan = _routing.planRouteToPoi(
      lat: position.latitude,
      lng: position.longitude,
      vertices: widget.mapData.vertices,
      edges: widget.mapData.edges,
      poi: widget.destination,
      pois: widget.mapData.pois,
    );

    if (plan == null) {
      setState(() {
        _userLocation = ll.LatLng(position.latitude, position.longitude);
        _routePoints = [];
        _distanceMeters = 0;
        _status = widget.destination.accessVertexId == null &&
                widget.mapData.edges.isEmpty
            ? 'Der er endnu ingen stier på kortet'
            : 'Ingen sti fundet i nærheden af stedet';
      });
      return;
    }

    setState(() {
      _userLocation = ll.LatLng(position.latitude, position.longitude);
      _routePoints = plan.points;
      _distanceMeters = plan.totalMeters;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = estimateWalkMinutes(_distanceMeters);

    return Scaffold(
      appBar: AppBar(
        title: Text('→ ${widget.destination.displayTitle}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _status ??
                  '${_distanceMeters.round()} m · ca. $minutes min gang',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: EventMapWidget(
              data: widget.mapData,
              routePoints: _routePoints,
              initialCenter: _userLocation,
              constrainToEventBounds: true,
              boundsFitPadding: const EdgeInsets.fromLTRB(24, 80, 24, 100),
              myLocationEnabled: true,
              myLocationRenderMode: MyLocationRenderMode.compass,
              myLocationTrackingMode: MyLocationTrackingMode.trackingCompass,
              showPathVertices: false,
              showEventPaths: !widget.mapData.event.hasIllustratedBasemap,
              showIllustratedBasemap: true,
              illustratedMapOnly: widget.mapData.event.hasIllustratedBasemap,
              routeDotted: _routePoints.length >= 2,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Afslut navigation'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
