import 'package:flutter/material.dart';

import '../../../data/models/poi_topic.dart';

/// Sammenklappelig filtermenu i venstre kant — vælg hvilke emner der vises ved tryk på steder.
class VisitorPoiTopicFilterDrawer extends StatefulWidget {
  const VisitorPoiTopicFilterDrawer({
    super.key,
    required this.activeTopics,
    required this.onChanged,
  });

  final Set<PoiTopic> activeTopics;
  final ValueChanged<Set<PoiTopic>> onChanged;

  @override
  State<VisitorPoiTopicFilterDrawer> createState() =>
      _VisitorPoiTopicFilterDrawerState();
}

class _VisitorPoiTopicFilterDrawerState extends State<VisitorPoiTopicFilterDrawer> {
  var _expanded = false;

  void _toggle(PoiTopic topic) {
    final next = Set<PoiTopic>.from(widget.activeTopics);
    if (next.contains(topic)) {
      if (next.length <= 1) return;
      next.remove(topic);
    } else {
      next.add(topic);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: _expanded ? 196 : 34,
      constraints: BoxConstraints(
        maxHeight: _expanded ? 320 : 120,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(2, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _expanded ? _buildExpanded(theme) : _buildCollapsed(theme),
    );
  }

  Widget _buildCollapsed(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = true),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.tune,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 6),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'Filtrér',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filtrér',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _expanded = false),
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.chevron_left, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Vælg hvilke emner der vises når du trykker på et sted',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final topic in PoiTopic.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _TopicFilterRow(
                topic: topic,
                selected: widget.activeTopics.contains(topic),
                onTap: () => _toggle(topic),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicFilterRow extends StatelessWidget {
  const _TopicFilterRow({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final PoiTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.45)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                topic.icon,
                size: 20,
                color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      topic.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: selected ? colorScheme.primary : colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
