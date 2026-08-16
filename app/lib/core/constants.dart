import 'config/app_config.dart';

abstract final class AppConstants {
  static String get publicEventBaseUrl => AppConfig.publicEventBaseUrl;

  static String publicEventUrl(
    String slug, {
    String? searchQuery,
    bool embed = false,
  }) {
    final params = <String, String>{
      if (embed) 'embed': '1',
      if (searchQuery != null && searchQuery.trim().isNotEmpty)
        'search': searchQuery.trim(),
    };
    return Uri.parse('$publicEventBaseUrl/$slug')
        .replace(queryParameters: params.isEmpty ? null : params)
        .toString();
  }

  static String embedIframeSnippet(String slug, {int height = 600}) {
    final src = publicEventUrl(slug, embed: true);
    return '<iframe src="$src" width="100%" height="$height" '
        'style="border:0;" allow="geolocation" loading="lazy" '
        'title="Plotspotting kort"></iframe>';
  }

  static String treasureHuntPublicUrl({
    required String eventSlug,
    required String huntSlug,
    bool embed = false,
  }) {
    final base = '$publicEventBaseUrl/$eventSlug/jagt/$huntSlug';
    if (!embed) return base;
    return Uri.parse(base).replace(queryParameters: const {'embed': '1'}).toString();
  }
  static const mapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';
  static const snapDistanceMeters = 5.0;
  static const routingSnapMaxMeters = 40.0;
  /// Max afstand fra et hus til nærmeste sti ved navigation.
  static const poiPathAccessMaxMeters = 200.0;
  /// Minimum GPS movement before a new path point is recorded while mapping.
  static const recordingMinStepMeters = 5.0;
  static const poiTapMaxMeters = 30.0;
  static const vertexTapMaxMeters = 7.0;
  /// Auto-snap til eksisterende stipunkt kun ved meget tæt placering.
  static const pathDrawSnapMeters = 2.5;
  /// Spacing between route dots when navigating (Google Maps style).
  static const routeDotIntervalMeters = 8.0;
  static const routeDotRadius = 3.5;
  /// Fast skærmstørrelse til rute-prikker (Flutter-overlay).
  static const routeDotScreenSize = 6.0;
  static const routeLineColor = '#4285F4';
  static const routeDotColor = '#4285F4';
  static const defaultZoom = 16.0;
  /// Gæster får ekstra plads at zoome/panorere uden for tegningens georef.
  static const areaViewBoundsExpansionFactor = 1.45;
  /// Neutral baggrund når gæster kun skal se det illustrerede kort.
  static const illustratedOnlyMapStyle = '''
{
  "version": 8,
  "name": "illustrated-only",
  "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "#f4f1ea"}
    }
  ]
}
''';
  static const poiMapFontStack = ['Noto Sans Regular'];

  /// Friland økosamfund, Feldballe (ca. centrum af området)
  static const frilandCenterLat = 56.3612;
  static const frilandCenterLng = 10.5274;
  static const frilandSlug = 'friland';
}
