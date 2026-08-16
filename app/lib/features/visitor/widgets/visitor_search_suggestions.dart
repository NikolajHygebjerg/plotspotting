import 'package:flutter/material.dart';

import '../../../data/models/map_poi.dart';

class VisitorSearchSuggestions extends StatelessWidget {
  const VisitorSearchSuggestions({
    super.key,
    required this.query,
    required this.results,
    required this.onSelect,
    this.onToggleFavorite,
    this.favoriteIds = const {},
  });

  final String query;
  final List<MapPoi> results;
  final ValueChanged<MapPoi> onSelect;
  final ValueChanged<MapPoi>? onToggleFavorite;
  final Set<String> favoriteIds;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.4,
        ),
        child: results.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Ingen forslag — prøv et andet navn, nummer eller sted',
                  style: TextStyle(height: 1.4),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Mener du',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final poi = results[index];
                        final isFav = favoriteIds.contains(poi.id);
                        return ListTile(
                          title: _HighlightedText(
                            text: poi.displayTitle,
                            query: query,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          subtitle: _HighlightedText(
                            text: poi.displaySubtitle,
                            query: query,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (onToggleFavorite != null)
                                IconButton(
                                  icon: Icon(
                                    isFav ? Icons.favorite : Icons.favorite_border,
                                    color: isFav ? Colors.red : null,
                                  ),
                                  onPressed: () => onToggleFavorite!(poi),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => onSelect(poi),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    this.style,
  });

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedText = text.toLowerCase();
    final matchIndex = normalizedQuery.isEmpty
        ? -1
        : normalizedText.indexOf(normalizedQuery);

    if (matchIndex < 0) {
      return Text(text, style: style);
    }

    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium!;
    final highlightStyle = baseStyle.copyWith(fontWeight: FontWeight.w700);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
            style: highlightStyle,
          ),
          TextSpan(text: text.substring(matchIndex + normalizedQuery.length)),
        ],
      ),
    );
  }
}
