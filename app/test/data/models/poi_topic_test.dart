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

    test('fromJson hydrates topics-only metadata from backend', () {
      final poi = MapPoi.fromJson({
        'id': '1',
        'name': 'Sted',
        'category': 'home',
        'lat': 56.36,
        'lng': 10.52,
        'metadata': {
          'topics': {
            'address': {'house_number': '36'},
            'name': {
              'nickname': 'Hytten',
              'occupants': [
                {'name': 'Laila'},
              ],
            },
            'info': {
              'description': 'Blå dør',
              'media': [
                {
                  'id': 'photo',
                  'url': 'https://example.com/photo.jpg',
                  'kind': 'image',
                  'storage_path': 'photo',
                },
              ],
            },
            'audio': {
              'media': [
                {
                  'id': 'story',
                  'url': 'https://example.com/story.mp3',
                  'kind': 'audio',
                  'storage_path': 'story',
                },
              ],
            },
          },
        },
      });

      expect(poi.availableTopics, {
        PoiTopic.address,
        PoiTopic.name,
        PoiTopic.info,
        PoiTopic.audio,
      });
      expect(poi.name, 'Hytten');
      expect(poi.houseNumber, '36');
      expect(poi.description, 'Blå dør');
      expect(poi.occupants, [const PoiOccupant(name: 'Laila')]);
      expect(poi.matchesActiveTopics(PoiTopic.values.toSet()), isTrue);
    });

    test('matchesActiveTopics shows every place when all filters are active', () {
      const poi = MapPoi(
        id: '1',
        name: 'Sted',
        category: 'home',
        lat: 56.36,
        lng: 10.52,
      );

      expect(poi.availableTopics, isEmpty);
      expect(poi.matchesActiveTopics(PoiTopic.values.toSet()), isTrue);
      expect(
        poi.matchesActiveTopics({PoiTopic.address}),
        isFalse,
      );
    });

    test('matchesActiveTopics respects partial filter selection', () {
      const poi = MapPoi(
        id: '1',
        name: 'Hytten',
        category: 'home',
        lat: 56.36,
        lng: 10.52,
        houseNumber: '12',
      );

      expect(poi.matchesActiveTopics({PoiTopic.address, PoiTopic.name}), isTrue);
      expect(poi.matchesActiveTopics({PoiTopic.audio}), isFalse);
    });

    test('fromJson parses metadata provided as json string', () {
      final poi = MapPoi.fromJson({
        'id': '2',
        'name': 'Sted',
        'category': 'home',
        'lat': 56.36,
        'lng': 10.52,
        'metadata': '{"house_number":"18","occupants":[{"name":"Bo"}]}',
      });

      expect(poi.houseNumber, '18');
      expect(poi.occupants, [const PoiOccupant(name: 'Bo')]);
      expect(poi.availableTopics, contains(PoiTopic.address));
    });
  });
}
