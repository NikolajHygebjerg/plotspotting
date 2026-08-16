import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/constants.dart';
import 'package:event_map/core/utils/slugify.dart';
import 'package:event_map/data/models/treasure_hunt.dart';

void main() {
  test('isConfigured requires enabled hunt with posts', () {
    expect(
      const TreasureHuntConfig(
        id: 'h1',
        enabled: true,
        posts: [
          TreasureHuntPost(
            id: 'p1',
            lat: 56,
            lng: 10,
            title: 'Post 1',
          ),
        ],
      ).isConfigured,
      isTrue,
    );
    expect(
      const TreasureHuntConfig(id: 'h1', enabled: true, posts: []).isConfigured,
      isFalse,
    );
  });

  test('isStandaloneReady requires title and posts', () {
    expect(
      const TreasureHuntConfig(
        id: 'h1',
        standaloneEnabled: true,
        standaloneTitle: 'Familie jagt',
        posts: [
          TreasureHuntPost(id: 'p1', lat: 56, lng: 10, title: 'Start'),
        ],
      ).isStandaloneReady,
      isTrue,
    );
    expect(
      const TreasureHuntConfig(
        id: 'h1',
        standaloneEnabled: true,
        posts: [
          TreasureHuntPost(id: 'p1', lat: 56, lng: 10, title: 'Start'),
        ],
      ).isStandaloneReady,
      isFalse,
    );
  });

  test('catalog round-trips through event metadata', () {
    const catalog = TreasureHuntCatalog([
      TreasureHuntConfig(
        id: 'h1',
        title: 'Familie jagt',
        enabled: true,
        standaloneEnabled: true,
        standaloneTitle: 'Velkommen til jagten',
        standaloneSlug: 'familie-jagt',
        posts: [
          TreasureHuntPost(
            id: 'p1',
            lat: 56,
            lng: 10,
            title: 'Start',
            nextPostId: 'p2',
            sortOrder: 0,
          ),
          TreasureHuntPost(
            id: 'p2',
            lat: 56.001,
            lng: 10.001,
            title: 'Mål',
            sortOrder: 1,
          ),
        ],
      ),
    ]);

    final restored = TreasureHuntCatalog.fromEventMetadata(catalog.toEventMetadata());
    expect(restored.hunts.length, 1);
    expect(restored.primaryHunt.posts.length, 2);
    expect(restored.primaryHunt.postById('p1')?.nextPostId, 'p2');
    expect(restored.primaryHunt.standaloneTitle, 'Velkommen til jagten');
    expect(restored.primaryHunt.standaloneSlug, 'familie-jagt');
  });

  test('huntByStandaloneSlug finds hunt', () {
    const catalog = TreasureHuntCatalog([
      TreasureHuntConfig(
        id: 'h1',
        standaloneSlug: 'sommer-jagt',
        posts: const [],
      ),
    ]);
    expect(catalog.huntByStandaloneSlug('sommer-jagt')?.id, 'h1');
  });

  test('slugify handles danish characters', () {
    expect(slugify('Familie skattejagt'), 'familie-skattejagt');
    expect(slugify('Søndags jagt'), 'soendags-jagt');
  });

  test('public URL uses event and hunt slug', () {
    expect(
      AppConstants.treasureHuntPublicUrl(
        eventSlug: 'friland',
        huntSlug: 'familie-jagt',
      ),
      'https://plotspotting.vercel.app/e/friland/jagt/familie-jagt',
    );
  });

  test('empty treasure_hunts list yields empty catalog', () {
    final catalog = TreasureHuntCatalog.fromEventMetadata({'treasure_hunts': []});
    expect(catalog.hunts, isEmpty);
  });
}
