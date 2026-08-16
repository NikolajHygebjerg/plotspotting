import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/poi_media.dart';
import 'package:event_map/data/models/poi_occupant.dart';

void main() {
  test('matchesQuery finds house number, occupants and keywords', () {
    const poi = MapPoi(
      id: '1',
      name: 'Hytten',
      category: 'home',
      lat: 56.36,
      lng: 10.52,
      houseNumber: '12',
      occupants: [
        PoiOccupant(name: 'Anna Jensen'),
        PoiOccupant(name: 'Solcelle ApS', kind: PoiOccupantKind.business),
      ],
      description: 'Blå dør',
      searchKeywords: 'værksted solceller',
    );

    expect(poi.matchesQuery('12'), isTrue);
    expect(poi.matchesQuery('anna'), isTrue);
    expect(poi.matchesQuery('solcelle'), isTrue);
    expect(poi.matchesQuery('hytten'), isTrue);
    expect(poi.matchesQuery('blå'), isTrue);
    expect(poi.matchesQuery('solceller'), isTrue);
    expect(poi.matchesQuery('99'), isFalse);
  });

  test('displayTitle prefers house number and first occupant', () {
    const poi = MapPoi(
      id: '1',
      name: 'Hytten',
      category: 'home',
      lat: 56.36,
      lng: 10.52,
      houseNumber: '12',
      occupants: [PoiOccupant(name: 'Anna')],
    );

    expect(poi.displayTitle, 'Nr. 12 · Anna');
  });

  test('displaySubtitle lists all occupants when several', () {
    const poi = MapPoi(
      id: '1',
      name: 'Hytten',
      category: 'home',
      lat: 56.36,
      lng: 10.52,
      houseNumber: '12',
      occupants: [
        PoiOccupant(name: 'Anna'),
        PoiOccupant(name: 'Solcelle ApS', kind: PoiOccupantKind.business),
      ],
    );

    expect(poi.displaySubtitle, contains('Anna'));
    expect(poi.displaySubtitle, contains('Solcelle ApS'));
  });

  test('fromJson reads legacy resident_name as occupant', () {
    final poi = MapPoi.fromJson({
      'id': '1',
      'name': 'Hytten',
      'category': 'home',
      'lat': 56.36,
      'lng': 10.52,
      'metadata': {'resident_name': 'Anna Jensen'},
    });

    expect(poi.occupants, [const PoiOccupant(name: 'Anna Jensen')]);
    expect(poi.matchesQuery('anna'), isTrue);
  });

  test('metadata media round-trips through toJson and fromJson', () {
    const poi = MapPoi(
      id: '1',
      name: 'Hytten',
      category: 'home',
      lat: 56.36,
      lng: 10.52,
      media: [
        PoiMedia(
          id: 'event/poi/photo.jpg',
          url: 'https://example.com/photo.jpg',
          kind: PoiMediaKind.image,
          storagePath: 'event/poi/photo.jpg',
        ),
        PoiMedia(
          id: 'event/poi/clip.mp4',
          url: 'https://example.com/clip.mp4',
          kind: PoiMediaKind.video,
          storagePath: 'event/poi/clip.mp4',
        ),
      ],
    );

    final restored = MapPoi.fromJson(poi.toJson());

    expect(restored.media, hasLength(2));
    expect(restored.images, hasLength(1));
    expect(restored.videos, hasLength(1));
    expect(restored.hasMedia, isTrue);
  });
}
