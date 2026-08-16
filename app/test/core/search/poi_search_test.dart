import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/search/poi_search.dart';
import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/poi_occupant.dart';

void main() {
  const poi = MapPoi(
    id: '1',
    name: 'Friland',
    category: 'home',
    lat: 56.36,
    lng: 10.52,
    houseNumber: '36',
    occupants: [PoiOccupant(name: 'Nikolaj Hygebjerg')],
    searchKeywords: 'værksted',
  );

  test('suggest ranks prefix and occupant matches highest', () {
    final results = PoiSearch.suggest([poi], 'nik');
    expect(results, [poi]);

    expect(PoiSearch.rank(poi, '36'), greaterThan(PoiSearch.rank(poi, 'værk')));
    expect(PoiSearch.rank(poi, 'fril'), greaterThan(0));
  });

  test('suggest tolerates small typos', () {
    expect(PoiSearch.matches(poi, 'nikolj'), isTrue);
    expect(PoiSearch.suggest([poi], 'nikolj'), [poi]);
  });

  test('suggest matches multi-word queries', () {
    expect(PoiSearch.matches(poi, 'friland 36'), isTrue);
    expect(PoiSearch.suggest([poi], 'friland 36'), [poi]);
  });
}
