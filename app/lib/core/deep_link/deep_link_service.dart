import 'package:app_links/app_links.dart';

import '../embed/embed_query.dart';

class DeepLinkRequest {
  const DeepLinkRequest({
    required this.slug,
    this.searchQuery,
    this.treasureHuntSlug,
    this.embed = false,
  });

  final String slug;
  final String? searchQuery;
  /// Slug for selvstændig skattejagt-side: /e/{event}/jagt/{treasureHuntSlug}
  final String? treasureHuntSlug;
  /// Kort vises uden app-shell — til iframe på kunders hjemmesider.
  final bool embed;
}

class DeepLinkService {
  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  Future<DeepLinkRequest?> getInitialLink() async {
    final uri = await _appLinks.getInitialLink();
    return _parse(uri);
  }

  Stream<DeepLinkRequest> get linkStream {
    return _appLinks.uriLinkStream
        .map(_parse)
        .where((event) => event != null)
        .cast<DeepLinkRequest>();
  }

  DeepLinkRequest? parseUri(Uri? uri) => _parse(uri);

  DeepLinkRequest? _parse(Uri? uri) {
    if (uri == null) return null;

    // eventmap://visit/friland?search=12
    if (uri.scheme == 'eventmap' && uri.host == 'visit') {
      final slug = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (slug.isEmpty) return null;
      return DeepLinkRequest(
        slug: slug,
        searchQuery: uri.queryParameters['search'],
        treasureHuntSlug: uri.queryParameters['jagt'],
        embed: parseEmbedQuery(uri.queryParameters['embed']),
      );
    }

    // https://eventmap.app/e/friland/jagt/familie-jagt
    // https://example.dk/localmap/e/friland/jagt/familie-jagt?search=12
    final segments = uri.pathSegments;
    final eventIndex = segments.indexOf('e');
    if (eventIndex >= 0 && eventIndex + 1 < segments.length) {
      final eventSlug = segments[eventIndex + 1];
      String? huntSlug;
      if (eventIndex + 3 < segments.length &&
          segments[eventIndex + 2] == 'jagt') {
        huntSlug = segments[eventIndex + 3];
      }
      huntSlug ??= uri.queryParameters['jagt'];

      return DeepLinkRequest(
        slug: eventSlug,
        searchQuery: uri.queryParameters['search'],
        treasureHuntSlug: huntSlug,
        embed: parseEmbedQuery(uri.queryParameters['embed']),
      );
    }

    return null;
  }
}
