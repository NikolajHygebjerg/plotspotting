import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/poi_media.dart';
import 'package:event_map/data/models/poi_occupant.dart';
import 'package:event_map/data/models/poi_topic.dart';

void main() {
  group('MapPoiTopicContent', () {
    test('availableTopics reflects filled fields', () {
      const poi = MapPoi(
        id: '1',
        name: 'Hytten',
        category: 'home',
        lat: 56.36,
        lng: 10.52,
        houseNumber: '12',
        occupants: [PoiOccupant(name: 'Anna')],
        description: 'Blå dør',
        media: [
          PoiMedia(
            id: 'a1',
            url: 'https://example.com/story.mp3',
            kind: PoiMediaKind.audio,
            storagePath: 'a1',
          ),
        ],
      );

      expect(poi.availableTopics, {
        PoiTopic.address,
        PoiTopic.name,
        PoiTopic.info,
        PoiTopic.audio,
      });
    });

    test('toJson stores topics metadata', () {
      const poi = MapPoi(
        id: '1',
        name: 'Hytten',
        category: 'home',
        lat: 56.36,
        lng: 10.52,
        houseNumber: '12',
        description: 'Blå dør',
      );

      final metadata = poi.toJson()['metadata'] as Map<String, dynamic>;
      final topics = metadata['topics'] as Map<String, dynamic>;

      expect(topics['address'], {'house_number': '12'});
      expect(topics['info'], {'description': 'Blå dør'});
    });
  });
}
