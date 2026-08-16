class MapVertex {
  const MapVertex({
    required this.id,
    required this.lat,
    required this.lng,
    this.label,
    this.isEntrance = false,
  });

  final String id;
  final double lat;
  final double lng;
  final String? label;
  final bool isEntrance;

  MapVertex copyWith({
    String? id,
    double? lat,
    double? lng,
    String? label,
    bool? isEntrance,
  }) {
    return MapVertex(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      label: label ?? this.label,
      isEntrance: isEntrance ?? this.isEntrance,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        if (label != null) 'label': label,
        'is_entrance': isEntrance,
      };

  factory MapVertex.fromJson(Map<String, dynamic> json) {
    return MapVertex(
      id: json['id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      label: json['label'] as String?,
      isEntrance: json['is_entrance'] as bool? ?? false,
    );
  }
}
