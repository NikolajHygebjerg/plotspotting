import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/deep_link/deep_link_service.dart';

void main() {
  final service = DeepLinkService();

  test('parses standalone treasure hunt path', () {
    final link = service.parseUri(
      Uri.parse('https://eventmap.app/e/friland/jagt/familie-jagt'),
    );
    expect(link?.slug, 'friland');
    expect(link?.treasureHuntSlug, 'familie-jagt');
  });

  test('parses treasure hunt query parameter', () {
    final link = service.parseUri(
      Uri.parse('https://plotspotting.dk/e/friland?jagt=familie-jagt'),
    );
    expect(link?.slug, 'friland');
    expect(link?.treasureHuntSlug, 'familie-jagt');
  });

  test('parses embed query parameter', () {
    final link = service.parseUri(
      Uri.parse('https://plotspotting.dk/e/friland?embed=1'),
    );
    expect(link?.slug, 'friland');
    expect(link?.embed, isTrue);
  });

  test('parses embed with search', () {
    final link = service.parseUri(
      Uri.parse('https://plotspotting.dk/e/friland?embed=true&search=12'),
    );
    expect(link?.slug, 'friland');
    expect(link?.searchQuery, '12');
    expect(link?.embed, isTrue);
  });

  test('parses subdirectory deploy path', () {
    final link = service.parseUri(
      Uri.parse('https://example.dk/localmap/e/friland/jagt/sommer'),
    );
    expect(link?.slug, 'friland');
    expect(link?.treasureHuntSlug, 'sommer');
  });
}
