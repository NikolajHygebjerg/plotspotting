import 'package:flutter/material.dart';

import '../../../data/models/poi_topic.dart';

class PoiTopicSection extends StatelessWidget {
  const PoiTopicSection({
    super.key,
    required this.topic,
    required this.child,
    this.subtitle,
  });

  final PoiTopic topic;
  final Widget child;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
              child: Icon(topic.icon, size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.label, style: theme.textTheme.titleSmall),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 20),
      ],
    );
  }
}
