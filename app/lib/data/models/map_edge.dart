import 'package:latlong2/latlong.dart';

class MapEdge {
  const MapEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.geometry,
    required this.lengthMeters,
    this.bidirectional = true,
  });

  final String id;
  final String fromId;
  final String toId;
  final List<LatLng> geometry;
  final double lengthMeters;
  final bool bidirectional;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_id': fromId,
        'to_id': toId,
        'length_meters': lengthMeters,
        'bidirectional': bidirectional,
        'coordinates': geometry.map((p) => [p.longitude, p.latitude]).toList(),
      };

  factory MapEdge.fromJson(Map<String, dynamic> json) {
    final coords = (json['coordinates'] as List? ?? const [])
        .cast<List>()
        .map(
          (pair) => LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          ),
        )
        .toList();

    return MapEdge(
      id: json['id'] as String,
      fromId: json['from_id'] as String? ?? json['from'] as String,
      toId: json['to_id'] as String? ?? json['to'] as String,
      geometry: coords,
      lengthMeters: (json['length_meters'] as num?)?.toDouble() ?? 0,
      bidirectional: json['bidirectional'] as bool? ?? true,
    );
  }
}
