import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../data/models/poi_media.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/routing/routing_service.dart';
import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_poi.dart';

enum AudioTourPhase {
  navigateToStop,
  readyAtStop,
  playingStop,
  walkingToNext,
  playingWander,
  completed,
}

class AudioTourGuidanceController extends ChangeNotifier {
  AudioTourGuidanceController({
    required EventMapData data,
    required AudioTourConfig config,
    RoutingService? routing,
  })  : _data = data,
        _routing = routing ?? RoutingService(),
        _config = config {
    _player.playerStateStream.listen(_onPlayerState);
    _player.positionStream.listen((_) => notifyListeners());
    _player.durationStream.listen((_) => notifyListeners());
    _resetTour();
  }

  static const arrivalThresholdMeters = 25.0;

  final EventMapData _data;
  final RoutingService _routing;
  final AudioTourConfig _config;
  final AudioPlayer _player = AudioPlayer();

  AudioTourPhase _phase = AudioTourPhase.navigateToStop;
  int _poiStopIndex = 0;
  List<ll.LatLng> _routePoints = [];
  double _distanceMeters = 0;
  double _approachMeters = 0;
  String? _error;
  AudioTourWanderClip? _activeWander;

  AudioTourPhase get phase => _phase;
  int get poiStopIndex => _poiStopIndex;
  List<ll.LatLng> get routePoints => _routePoints;
  double get distanceMeters => _distanceMeters;
  double get approachMeters => _approachMeters;
  String? get error => _error;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  AudioTourConfig get config => _config;

  MapPoi? get currentTargetPoi {
    final ids = _config.poiStopIds;
    if (_poiStopIndex < 0 || _poiStopIndex >= ids.length) return null;
    return _data.poiById(ids[_poiStopIndex]);
  }

  AudioTourWanderClip? get wanderEnRoute {
    if (_poiStopIndex <= 0) return null;
    return wanderBetweenPoiStops(_config, _poiStopIndex - 1, _poiStopIndex);
  }

  bool get canPlayWander =>
      _phase == AudioTourPhase.walkingToNext && wanderEnRoute != null;

  bool get canPlayStop {
    if (_phase != AudioTourPhase.readyAtStop) return false;
    return _currentStopAudio != null;
  }

  PoiMedia? get _currentStopAudio {
    final poi = currentTargetPoi;
    if (poi == null) return null;
    final item = _config.poiItemAtStopIndex(_poiStopIndex);
    return poi.audioById(item?.audioId) ?? poi.primaryAudio;
  }

  String get statusTitle => switch (_phase) {
        AudioTourPhase.navigateToStop => 'Gå til startpunktet',
        AudioTourPhase.readyAtStop => 'Du er fremme',
        AudioTourPhase.playingStop => 'Afspiller…',
        AudioTourPhase.walkingToNext => 'Gå til næste stop',
        AudioTourPhase.playingWander => 'Vandrelyd',
        AudioTourPhase.completed => 'Lydvandring afsluttet',
      };

  String get statusSubtitle {
    final poi = currentTargetPoi;
    return switch (_phase) {
      AudioTourPhase.navigateToStop ||
      AudioTourPhase.readyAtStop ||
      AudioTourPhase.playingStop =>
        poi?.displayTitle ?? '',
      AudioTourPhase.walkingToNext => poi?.displayTitle ?? 'Næste stop',
      AudioTourPhase.playingWander => _activeWander?.title ?? 'Vandrelyd',
      AudioTourPhase.completed => 'Tak for turen',
    };
  }

  void _resetTour() {
    _poiStopIndex = 0;
    _phase = AudioTourPhase.navigateToStop;
    _routePoints = [];
    _distanceMeters = 0;
    _approachMeters = 0;
    _activeWander = null;
    _error = null;
  }

  void startTour() {
    _resetTour();
    notifyListeners();
  }

  void updateLocation(double lat, double lng) {
    final target = currentTargetPoi;
    if (target == null) return;

    if (_phase == AudioTourPhase.navigateToStop ||
        _phase == AudioTourPhase.walkingToNext) {
      _recomputeRoute(lat, lng, target);
      final distanceToTarget = haversineMeters(lat, lng, target.lat, target.lng);
      if (distanceToTarget <= arrivalThresholdMeters) {
        _phase = AudioTourPhase.readyAtStop;
      }
    }

    notifyListeners();
  }

  void _recomputeRoute(double lat, double lng, MapPoi target) {
    final plan = _routing.planRouteToPoi(
      lat: lat,
      lng: lng,
      vertices: _data.vertices,
      edges: _data.edges,
      poi: target,
      pois: _data.pois,
    );
    if (plan == null) {
      _routePoints = [ll.LatLng(lat, lng), ll.LatLng(target.lat, target.lng)];
      _distanceMeters = haversineMeters(lat, lng, target.lat, target.lng);
      _approachMeters = 0;
      return;
    }
    _routePoints = plan.points
        .map((point) => ll.LatLng(point.latitude, point.longitude))
        .toList();
    _distanceMeters = plan.totalMeters;
    _approachMeters = plan.approachMeters;
  }

  Future<void> playCurrentStop() async {
    final poi = currentTargetPoi;
    final audio = _currentStopAudio;
    if (poi == null || audio == null) {
      _error = 'Intet lydklip for dette stop';
      notifyListeners();
      return;
    }

    try {
      _error = null;
      _activeWander = null;
      await _player.stop();
      await _player.setUrl(audio.url);
      _phase = AudioTourPhase.playingStop;
      await _player.play();
      notifyListeners();
    } on Object catch (error) {
      _error = 'Kunne ikke afspille: $error';
      notifyListeners();
    }
  }

  Future<void> playWander() async {
    final wander = wanderEnRoute;
    if (wander == null) return;

    try {
      _error = null;
      _activeWander = wander;
      await _player.stop();
      await _player.setUrl(wander.url);
      _phase = AudioTourPhase.playingWander;
      await _player.play();
      notifyListeners();
    } on Object catch (error) {
      _error = 'Kunne ikke afspille vandrelyd: $error';
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    notifyListeners();
  }

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      unawaited(_handlePlaybackCompleted());
    }
    notifyListeners();
  }

  Future<void> _handlePlaybackCompleted() async {
    await _player.stop();

    if (_phase == AudioTourPhase.playingStop) {
      if (_poiStopIndex >= _config.poiStopIds.length - 1) {
        _phase = AudioTourPhase.completed;
        _routePoints = [];
        notifyListeners();
        return;
      }

      _poiStopIndex++;
      _phase = AudioTourPhase.walkingToNext;
      _activeWander = wanderEnRoute;
      notifyListeners();
      return;
    }

    if (_phase == AudioTourPhase.playingWander) {
      _phase = AudioTourPhase.walkingToNext;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
