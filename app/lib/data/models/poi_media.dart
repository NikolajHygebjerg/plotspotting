enum PoiMediaKind {
  image,
  video,
  audio;

  static PoiMediaKind fromJson(String? value) {
    return switch (value) {
      'video' => PoiMediaKind.video,
      'audio' => PoiMediaKind.audio,
      _ => PoiMediaKind.image,
    };
  }

  String toJson() => switch (this) {
        PoiMediaKind.video => 'video',
        PoiMediaKind.audio => 'audio',
        PoiMediaKind.image => 'image',
      };
}

class PoiMedia {
  const PoiMedia({
    required this.id,
    required this.url,
    required this.kind,
    this.storagePath,
    this.caption,
  });

  final String id;
  final String url;
  final PoiMediaKind kind;
  final String? storagePath;
  final String? caption;

  PoiMedia copyWith({
    String? id,
    String? url,
    PoiMediaKind? kind,
    String? storagePath,
    String? caption,
  }) {
    return PoiMedia(
      id: id ?? this.id,
      url: url ?? this.url,
      kind: kind ?? this.kind,
      storagePath: storagePath ?? this.storagePath,
      caption: caption ?? this.caption,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'kind': kind.toJson(),
        if (storagePath != null) 'storage_path': storagePath,
        if (caption != null && caption!.isNotEmpty) 'caption': caption,
      };

  factory PoiMedia.fromJson(Map<String, dynamic> json) {
    return PoiMedia(
      id: json['id'] as String,
      url: json['url'] as String,
      kind: PoiMediaKind.fromJson(json['kind'] as String?),
      storagePath: json['storage_path'] as String?,
      caption: json['caption'] as String?,
    );
  }
}
