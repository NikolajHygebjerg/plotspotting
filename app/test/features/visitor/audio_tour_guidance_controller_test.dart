import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/data/models/audio_tour.dart';
import 'package:event_map/data/models/event_map_data.dart';
import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/poi_media.dart';
import 'package:event_map/features/visitor/audio_tour_guidance_controller.dart';

void main() {
  const stopA = MapPoi(
    id: 'a',
    name: 'Stop A',
    category: 'info',
    lat: 56.0008,
    lng: 10.0,
    media: [
      PoiMedia(
        id: 'audio-a',
        url: 'https://example.com/a.mp3',
        kind: PoiMediaKind.audio,
        storagePath: 'audio-a',
        caption: 'Historie A',
      ),
    ],
  );
  const stopB = MapPoi(
    id: 'b',
    name: 'Stop B',
    category: 'info',
    lat: 56.0016,
    lng: 10.0,
    media: [
      PoiMedia(
        id: 'audio-b',
        url: 'https://example.com/b.mp3',
        kind: PoiMediaKind.audio,
        storagePath: 'audio-b',
      ),
    ],
  );

  const config = AudioTourConfig(
    id: 'tour',
    enabled: true,
    items: [
      AudioTourItem.poi(poiId: 'a'),
      AudioTourItem.poi(poiId: 'b'),
    ],
  );

  final data = EventMapData(
    event: const EventMeta(id: 'event', name: 'Test'),
    pois: const [stopA, stopB],
  );

  AudioTourGuidanceController createController() {
    return AudioTourGuidanceController(data: data, config: config);
  }

  test('starts guiding to first stop', () {
    final controller = createController();

    expect(controller.phase, AudioTourPhase.navigateToStop);
    expect(controller.isGuidingToStop, isTrue);
    expect(controller.currentTargetPoi?.id, 'a');
  });

  test('arrival switches to readyAtStop', () {
    final controller = createController();

    controller.updateLocation(stopA.lat, stopA.lng);

    expect(controller.phase, AudioTourPhase.readyAtStop);
    expect(controller.canPlayStop, isTrue);
    expect(controller.canGoToNextStop, isTrue);
    controller.dispose();
  });

  test('goToNextStop from readyAtStop guides to next stop', () async {
    final controller = createController();
    controller.updateLocation(stopA.lat, stopA.lng);
    expect(controller.phase, AudioTourPhase.readyAtStop);

    await controller.goToNextStop();

    expect(controller.phase, AudioTourPhase.walkingToNext);
    expect(controller.poiStopIndex, 1);
    expect(controller.currentTargetPoi?.id, 'b');
    expect(controller.isGuidingToStop, isTrue);
    expect(controller.routePoints.length, greaterThanOrEqualTo(2));
    controller.dispose();
  });

  test('goToNextStop from last stop completes tour', () async {
    final controller = createController();
    controller.updateLocation(stopA.lat, stopA.lng);
    await controller.goToNextStop();
    controller.updateLocation(stopB.lat, stopB.lng);

    expect(controller.phase, AudioTourPhase.readyAtStop);
    expect(controller.poiStopIndex, 1);

    await controller.goToNextStop();

    expect(controller.phase, AudioTourPhase.completed);
    expect(controller.canGoToNextStop, isFalse);
    controller.dispose();
  });
}
