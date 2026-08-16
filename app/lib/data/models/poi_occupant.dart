enum PoiOccupantKind {
  resident('Beboer'),
  business('Virksomhed');

  const PoiOccupantKind(this.label);

  final String label;

  static PoiOccupantKind fromJson(String? value) {
    return switch (value) {
      'business' => PoiOccupantKind.business,
      _ => PoiOccupantKind.resident,
    };
  }

  String toJson() => switch (this) {
        PoiOccupantKind.business => 'business',
        PoiOccupantKind.resident => 'resident',
      };
}

class PoiOccupant {
  const PoiOccupant({
    required this.name,
    this.kind = PoiOccupantKind.resident,
  });

  final String name;
  final PoiOccupantKind kind;

  PoiOccupant copyWith({
    String? name,
    PoiOccupantKind? kind,
  }) {
    return PoiOccupant(
      name: name ?? this.name,
      kind: kind ?? this.kind,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PoiOccupant && other.name == name && other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(name, kind);

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.toJson(),
      };

  factory PoiOccupant.fromJson(Map<String, dynamic> json) {
    return PoiOccupant(
      name: json['name'] as String? ?? '',
      kind: PoiOccupantKind.fromJson(json['kind'] as String?),
    );
  }
}
