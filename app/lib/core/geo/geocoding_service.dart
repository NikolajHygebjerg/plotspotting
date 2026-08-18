import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Result from OpenStreetMap Nominatim address lookup.
class GeocodingResult {
  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.bounds,
  });

  final String displayName;
  final double lat;
  final double lng;
  final GeocodingBounds? bounds;

  factory GeocodingResult.fromJson(Map<String, dynamic> json) {
    GeocodingBounds? bounds;
    final bbox = json['boundingbox'];
    if (bbox is List && bbox.length >= 4) {
      bounds = GeocodingBounds(
        south: double.parse(bbox[0] as String),
        north: double.parse(bbox[1] as String),
        west: double.parse(bbox[2] as String),
        east: double.parse(bbox[3] as String),
      );
    }

    return GeocodingResult(
      displayName: json['display_name'] as String? ?? '',
      lat: double.parse(json['lat'] as String),
      lng: double.parse(json['lon'] as String),
      bounds: bounds,
    );
  }
}

class GeocodingBounds {
  const GeocodingBounds({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
  });

  final double south;
  final double north;
  final double west;
  final double east;

  double get centerLat => (south + north) / 2;
  double get centerLng => (west + east) / 2;

  double estimateZoom() {
    final latSpan = (north - south).abs();
    final lngSpan = (east - west).abs();
    final span = math.max(latSpan, lngSpan);
    if (span <= 0) return 16;
    final zoom = math.log(360 / span) / math.ln2 - 1.2;
    return zoom.clamp(10.0, 18.0);
  }
}

/// Address search via OpenStreetMap Nominatim (free, no API key).
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'Plotspotting/1.0 (https://plotspotting.vercel.app)';

  Future<List<GeocodingResult>> search(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'q': trimmed,
        'format': 'json',
        'limit': '$limit',
        'addressdetails': '1',
      },
    );

    final response = await _client.get(
      uri,
      headers: const {'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      throw Exception('Adressesøgning fejlede (${response.statusCode})');
    }

    return parseSearchResponse(response.body);
  }

  static List<GeocodingResult> parseSearchResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GeocodingResult.fromJson)
        .where((result) => result.displayName.isNotEmpty)
        .toList();
  }
}
