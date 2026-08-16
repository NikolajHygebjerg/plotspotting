import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/data/models/audio_tour.dart';

void main() {
  test('wanderBetweenPoiStops finds clip between two poi stops', () {
    const config = AudioTourConfig(
      id: 'test',
      enabled: true,
      items: [
        AudioTourItem.poi(poiId: 'a'),
        AudioTourItem.wander(
          wander: AudioTourWanderClip(
            id: 'w1',
            url: 'https://example.com/w1.mp3',
            title: 'Gå videre',
          ),
        ),
        AudioTourItem.poi(poiId: 'b'),
      ],
    );

    expect(wanderBetweenPoiStops(config, 0, 1)?.id, 'w1');
    expect(wanderBetweenPoiStops(config, 0, 0), isNull);
  });

  test('isConfigured requires enabled tour with poi stops', () {
    expect(
      const AudioTourConfig(
        id: 'test',
        enabled: true,
        items: [AudioTourItem.poi(poiId: 'a')],
      ).isConfigured,
      isTrue,
    );
    expect(
      const AudioTourConfig(id: 'test', enabled: true, items: []).isConfigured,
      isFalse,
    );
  });

  test('empty audio_tours list overrides legacy audio_tour', () {
    final catalog = AudioTourCatalog.fromEventMetadata({
      'audio_tours': [],
      'audio_tour': {
        'enabled': true,
        'items': [
          {'kind': 'poi', 'poi_id': 'legacy'},
        ],
      },
    });
    expect(catalog.tours, isEmpty);
  });
}
