import '../../data/models/map_poi.dart';

abstract final class PoiSearch {
  static const suggestionLimit = 8;

  static List<MapPoi> suggest(
    Iterable<MapPoi> pois,
    String query, {
    int limit = suggestionLimit,
  }) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return const [];

    final ranked = <MapPoi>[];
    for (final poi in pois) {
      if (rank(poi, normalized) > 0) {
        ranked.add(poi);
      }
    }

    ranked.sort((a, b) {
      final rankCompare = rank(b, normalized).compareTo(rank(a, normalized));
      if (rankCompare != 0) return rankCompare;
      return a.displayTitle.compareTo(b.displayTitle);
    });

    if (ranked.length <= limit) return ranked;
    return ranked.sublist(0, limit);
  }

  static bool matches(MapPoi poi, String query) => rank(poi, query) > 0;

  static int rank(MapPoi poi, String query) {
    final q = _normalize(query);
    if (q.isEmpty) return 0;

    var best = 0;
    for (final term in _termsFor(poi)) {
      best = _maxRank(best, _rankTerm(_normalize(term), q));
    }

    final tokens = q.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
    if (tokens.length > 1) {
      final combined = _termsFor(poi).map(_normalize).join(' ');
      if (tokens.every(combined.contains)) {
        best = _maxRank(best, 650);
      }
    }

    return best;
  }

  static Iterable<String> _termsFor(MapPoi poi) sync* {
    yield poi.name;
    yield poi.displayTitle;
    yield poi.navigationLabel;
    yield poi.mapPinLabel;
    if (poi.houseNumber != null) yield poi.houseNumber!;
    if (poi.description != null) yield poi.description!;
    if (poi.searchKeywords != null) yield poi.searchKeywords!;
    for (final occupant in poi.occupants) {
      yield occupant.name;
    }
  }

  static int _rankTerm(String term, String query) {
    if (term.isEmpty || query.isEmpty) return 0;
    if (term == query) return 1000;
    if (term.startsWith(query)) {
      return 900 - (term.length - query.length).clamp(0, 80);
    }

    for (final word in term.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (word == query) return 860;
      if (word.startsWith(query)) return 820 - (word.length - query.length).clamp(0, 40);
    }

    if (term.contains(query)) return 700;

    if (query.length >= 2 && _isSubsequence(term, query)) return 500;

    for (final word in term.split(RegExp(r'\s+'))) {
      if (word.isEmpty || query.length < 3) continue;
      final distance = _levenshtein(word, query);
      if (distance == 0) return 860;
      if (distance == 1) return 450;
      if (distance == 2 && query.length >= 5) return 350;
    }

    return 0;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _maxRank(int current, int candidate) =>
      candidate > current ? candidate : current;

  static bool _isSubsequence(String text, String query) {
    var queryIndex = 0;
    for (var i = 0; i < text.length && queryIndex < query.length; i++) {
      if (text.codeUnitAt(i) == query.codeUnitAt(queryIndex)) {
        queryIndex++;
      }
    }
    return queryIndex == query.length;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (index) => index);
    final current = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final substitutionCost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitutionCost,
        ].reduce((value, next) => value < next ? value : next);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }
}
