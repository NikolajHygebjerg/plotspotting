import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/constants.dart';
import 'package:event_map/core/embed/embed_query.dart';

void main() {
  group('parseEmbedQuery', () {
    test('accepts common truthy values', () {
      expect(parseEmbedQuery('1'), isTrue);
      expect(parseEmbedQuery('true'), isTrue);
      expect(parseEmbedQuery('TRUE'), isTrue);
      expect(parseEmbedQuery('yes'), isTrue);
    });

    test('rejects other values', () {
      expect(parseEmbedQuery(null), isFalse);
      expect(parseEmbedQuery(''), isFalse);
      expect(parseEmbedQuery('0'), isFalse);
      expect(parseEmbedQuery('false'), isFalse);
    });
  });

  group('AppConstants embed URLs', () {
    test('publicEventUrl adds embed query', () {
      expect(
        AppConstants.publicEventUrl('friland', embed: true),
        'https://plotspotting.vercel.app/e/friland?embed=1',
      );
    });

    test('embedIframeSnippet includes geolocation allow', () {
      final snippet = AppConstants.embedIframeSnippet('friland');
      expect(snippet, contains('embed=1'));
      expect(snippet, contains('allow="geolocation"'));
    });
  });
}
