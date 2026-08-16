import '../../core/constants.dart';
import '../../core/utils/slugify.dart';
import 'poi_media.dart';
import 'treasure_hunt_path_network.dart';

class TreasureHuntPost {
  const TreasureHuntPost({
    required this.id,
    required this.lat,
    required this.lng,
    required this.title,
    this.bodyText,
    this.media = const [],
    this.nextPostId,
    this.sortOrder = 0,
  });

  final String id;
  final double lat;
  final double lng;
  final String title;
  final String? bodyText;
  final List<PoiMedia> media;
  final String? nextPostId;
  final int sortOrder;

  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : 'Post';

  bool get hasNextPost =>
      nextPostId != null && nextPostId!.trim().isNotEmpty;

  TreasureHuntPost copyWith({
    String? id,
    double? lat,
    double? lng,
    String? title,
    String? bodyText,
    List<PoiMedia>? media,
    String? nextPostId,
    bool clearNextPostId = false,
    int? sortOrder,
  }) {
    return TreasureHuntPost(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      title: title ?? this.title,
      bodyText: bodyText ?? this.bodyText,
      media: media ?? this.media,
      nextPostId: clearNextPostId ? null : (nextPostId ?? this.nextPostId),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        'title': title,
        if (bodyText != null && bodyText!.trim().isNotEmpty)
          'body_text': bodyText,
        if (media.isNotEmpty) 'media': media.map((item) => item.toJson()).toList(),
        if (nextPostId != null && nextPostId!.isNotEmpty) 'next_post_id': nextPostId,
        'sort_order': sortOrder,
      };

  factory TreasureHuntPost.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'] as List? ?? const [];
    return TreasureHuntPost(
      id: json['id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      title: json['title'] as String? ?? 'Post',
      bodyText: json['body_text'] as String?,
      media: rawMedia
          .map((item) => PoiMedia.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      nextPostId: json['next_post_id'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class TreasureHuntConfig {
  const TreasureHuntConfig({
    required this.id,
    this.title,
    this.enabled = false,
    this.posts = const [],
    this.standaloneEnabled = false,
    this.standaloneTitle,
    this.standaloneSlug,
    this.coverImage,
    this.pathNetwork = const TreasureHuntPathNetwork(),
  });

  final String id;
  final String? title;
  final bool enabled;
  final List<TreasureHuntPost> posts;
  /// Del som selvstændig hjemmeside uafhængigt af kortet.
  final bool standaloneEnabled;
  /// Overskrift på landingssiden.
  final String? standaloneTitle;
  /// URL-del efter `/e/{event}/jagt/`.
  final String? standaloneSlug;
  final PoiMedia? coverImage;
  /// Jagt-specifikke stier — bruges ikke på det almindelige besøgskort.
  final TreasureHuntPathNetwork pathNetwork;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : 'Skattejagt';

  String get landingHeadline {
    final headline = standaloneTitle?.trim();
    if (headline != null && headline.isNotEmpty) return headline;
    return displayTitle;
  }

  String get urlSlug =>
      standaloneSlug?.trim().isNotEmpty == true ? standaloneSlug!.trim() : id;

  bool get isConfigured => enabled && posts.isNotEmpty;

  bool get isStandaloneReady =>
      standaloneEnabled &&
      standaloneTitle?.trim().isNotEmpty == true &&
      posts.isNotEmpty;

  String? publicUrlForEvent(String? eventSlug) {
    if (eventSlug == null || eventSlug.isEmpty || !isStandaloneReady) {
      return null;
    }
    return AppConstants.treasureHuntPublicUrl(
      eventSlug: eventSlug,
      huntSlug: urlSlug,
    );
  }

  List<TreasureHuntPost> get orderedPosts {
    final copy = List<TreasureHuntPost>.from(posts);
    copy.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return copy;
  }

  TreasureHuntPost? postById(String id) {
    for (final post in posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  TreasureHuntConfig copyWith({
    String? id,
    String? title,
    bool? enabled,
    List<TreasureHuntPost>? posts,
    bool? standaloneEnabled,
    String? standaloneTitle,
    String? standaloneSlug,
    PoiMedia? coverImage,
    bool clearCoverImage = false,
    TreasureHuntPathNetwork? pathNetwork,
  }) {
    return TreasureHuntConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      enabled: enabled ?? this.enabled,
      posts: posts ?? this.posts,
      standaloneEnabled: standaloneEnabled ?? this.standaloneEnabled,
      standaloneTitle: standaloneTitle ?? this.standaloneTitle,
      standaloneSlug: standaloneSlug ?? this.standaloneSlug,
      coverImage: clearCoverImage ? null : (coverImage ?? this.coverImage),
      pathNetwork: pathNetwork ?? this.pathNetwork,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null && title!.isNotEmpty) 'title': title,
        'enabled': enabled,
        'posts': posts.map((post) => post.toJson()).toList(),
        if (standaloneEnabled) 'standalone_enabled': true,
        if (standaloneTitle != null && standaloneTitle!.isNotEmpty)
          'standalone_title': standaloneTitle,
        if (standaloneSlug != null && standaloneSlug!.isNotEmpty)
          'standalone_slug': standaloneSlug,
        if (coverImage != null) 'cover_image': coverImage!.toJson(),
        ...pathNetwork.toJson(),
      };

  factory TreasureHuntConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const TreasureHuntConfig(id: 'default');
    }
    final rawPosts = json['posts'] as List? ?? const [];
    final coverRaw = json['cover_image'];
    return TreasureHuntConfig(
      id: json['id'] as String? ?? 'default',
      title: json['title'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      posts: rawPosts
          .map(
            (post) => TreasureHuntPost.fromJson(
              Map<String, dynamic>.from(post as Map),
            ),
          )
          .toList(),
      standaloneEnabled: json['standalone_enabled'] as bool? ?? false,
      standaloneTitle: json['standalone_title'] as String?,
      standaloneSlug: json['standalone_slug'] as String?,
      coverImage: coverRaw is Map
          ? PoiMedia.fromJson(Map<String, dynamic>.from(coverRaw))
          : null,
      pathNetwork: TreasureHuntPathNetwork.fromJson(json),
    );
  }

  static String uniqueStandaloneSlug({
    required String title,
    required String huntId,
    required Iterable<TreasureHuntConfig> existingHunts,
  }) {
    final base = slugify(title);
    final candidate = base.isEmpty ? huntId : base;
    final taken = {
      for (final hunt in existingHunts)
        if (hunt.id != huntId) hunt.urlSlug,
    };
    if (!taken.contains(candidate)) return candidate;

    var suffix = 2;
    while (taken.contains('$candidate-$suffix')) {
      suffix++;
    }
    return '$candidate-$suffix';
  }
}

class TreasureHuntCatalog {
  const TreasureHuntCatalog(this.hunts);

  final List<TreasureHuntConfig> hunts;

  List<TreasureHuntConfig> get configuredHunts =>
      hunts.where((hunt) => hunt.isConfigured).toList();

  List<TreasureHuntConfig> get standaloneHunts =>
      hunts.where((hunt) => hunt.isStandaloneReady).toList();

  bool get hasConfiguredHunt => configuredHunts.isNotEmpty;

  bool get hasStandaloneHunt => standaloneHunts.isNotEmpty;

  TreasureHuntConfig get primaryHunt {
    if (configuredHunts.isNotEmpty) return configuredHunts.first;
    if (hunts.isNotEmpty) return hunts.first;
    return const TreasureHuntConfig(id: 'default');
  }

  TreasureHuntConfig? huntById(String id) {
    for (final hunt in hunts) {
      if (hunt.id == id) return hunt;
    }
    return null;
  }

  TreasureHuntConfig? huntByStandaloneSlug(String slug) {
    for (final hunt in hunts) {
      if (hunt.urlSlug == slug) return hunt;
    }
    return null;
  }

  TreasureHuntCatalog copyWith({List<TreasureHuntConfig>? hunts}) =>
      TreasureHuntCatalog(hunts ?? this.hunts);

  static TreasureHuntCatalog fromEventMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return const TreasureHuntCatalog([]);
    }

    final rawHunts = metadata['treasure_hunts'];
    if (!metadata.containsKey('treasure_hunts')) {
      return const TreasureHuntCatalog([]);
    }

    final items = rawHunts is List ? rawHunts : const [];
    return TreasureHuntCatalog(
      items
          .map(
            (hunt) => TreasureHuntConfig.fromJson(
              Map<String, dynamic>.from(hunt as Map),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toEventMetadata() => {
        'treasure_hunts': hunts.map((hunt) => hunt.toJson()).toList(),
      };
}
