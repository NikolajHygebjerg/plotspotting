import 'package:flutter/material.dart';

import '../../../data/models/map_poi.dart';
import '../../../data/models/poi_occupant.dart';
import '../../../data/models/poi_topic.dart';
import 'poi_audio_player.dart';
import 'poi_media_viewer.dart';

Future<void> showVisitorPoiTopicPicker(
  BuildContext context, {
  required MapPoi poi,
  required Set<PoiTopic> activeTopics,
  required bool isDestination,
  VoidCallback? onNavigateHere,
}) {
  final topics = poi.availableTopics.intersection(activeTopics).toList()
    ..sort((a, b) => a.index.compareTo(b.index));

  if (topics.isEmpty) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            activeTopics.isEmpty
                ? 'Vælg mindst ét emne i filtermenuen til venstre.'
                : 'Dette sted har ingen information for de valgte emner.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  if (topics.length == 1) {
    return showVisitorPoiTopicDetail(
      context,
      poi: poi,
      topic: topics.first,
      isDestination: isDestination,
      onNavigateHere: onNavigateHere,
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                poi.displayTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tryk på et emne',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final topic in topics)
                    _TopicPickerButton(
                      topic: topic,
                      onTap: () {
                        Navigator.pop(context);
                        showVisitorPoiTopicDetail(
                          context,
                          poi: poi,
                          topic: topic,
                          isDestination: isDestination,
                          onNavigateHere: onNavigateHere,
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showVisitorPoiTopicDetail(
  BuildContext context, {
  required MapPoi poi,
  required PoiTopic topic,
  required bool isDestination,
  VoidCallback? onNavigateHere,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.55),
                      child: Icon(
                        topic.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        topic.label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (isDestination)
                      Chip(
                        label: const Text('Din destination'),
                        backgroundColor: Colors.red.shade50,
                        labelStyle: TextStyle(color: Colors.red.shade800, fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._topicContent(context, poi: poi, topic: topic),
                if (onNavigateHere != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onNavigateHere();
                    },
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Naviger hertil'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

List<Widget> _topicContent(
  BuildContext context, {
  required MapPoi poi,
  required PoiTopic topic,
}) {
  return switch (topic) {
    PoiTopic.address => _addressContent(context, poi),
    PoiTopic.name => _nameContent(context, poi),
    PoiTopic.info => _infoContent(context, poi),
    PoiTopic.audio => _audioContent(context, poi),
  };
}

List<Widget> _addressContent(BuildContext context, MapPoi poi) {
  return [
    Text(
      poi.addressTopicText,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    ),
  ];
}

List<Widget> _nameContent(BuildContext context, MapPoi poi) {
  final widgets = <Widget>[
    Text(
      poi.nameTopicTitle,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    ),
  ];

  final subtitle = poi.nameTopicSubtitle;
  if (subtitle != null) {
    widgets.addAll([
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }

  if (poi.occupants.length > 1) {
    widgets.addAll([
      const SizedBox(height: 16),
      Text('Beboere og virksomheder', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      ...poi.occupants.map(
        (occupant) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(
                occupant.kind == PoiOccupantKind.business
                    ? Icons.storefront_outlined
                    : Icons.person_outline,
                size: 18,
                color: Colors.grey.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(occupant.name)),
            ],
          ),
        ),
      ),
    ]);
  }

  return widgets;
}

List<Widget> _infoContent(BuildContext context, MapPoi poi) {
  final widgets = <Widget>[];

  if (poi.description != null && poi.description!.trim().isNotEmpty) {
    widgets.add(Text(poi.description!));
  }

  if (poi.hasVisualMedia) {
    if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 16));
    widgets.add(PoiMediaViewer(media: poi.infoMedia));
  }

  if (widgets.isEmpty) {
    widgets.add(const Text('Ingen info tilgængelig'));
  }

  return widgets;
}

List<Widget> _audioContent(BuildContext context, MapPoi poi) {
  return [
    for (final clip in poi.audioClips) ...[
      PoiAudioPlayer(clip: clip),
      if (clip != poi.audioClips.last) const SizedBox(height: 12),
    ],
  ];
}

class _TopicPickerButton extends StatelessWidget {
  const _TopicPickerButton({
    required this.topic,
    required this.onTap,
  });

  final PoiTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(topic.icon, size: 28, color: colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              topic.label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
