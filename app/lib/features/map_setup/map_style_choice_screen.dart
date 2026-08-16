import 'package:flutter/material.dart';

import '../../data/models/map_bounds.dart';
import 'illustrated_map_setup_screen.dart';
import 'map_setup_flow.dart';
import 'map_setup_step_header.dart';

/// Bruger vælger standardkort eller illustreret kort efter området er gemt.
class MapStyleChoiceScreen extends StatelessWidget {
  const MapStyleChoiceScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.bounds,
  });

  final String eventId;
  final String eventName;
  final MapBounds bounds;

  void _useStandardMap(BuildContext context) {
    MapSetupFlow.openEditor(
      context,
      eventId: eventId,
      eventName: eventName,
    );
  }

  void _useIllustratedMap(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => IllustratedMapSetupScreen(
          eventId: eventId,
          eventName: eventName,
          bounds: bounds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vælg korttype'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const MapSetupStepHeader(currentStep: 1),
          const SizedBox(height: 24),
          Text(
            'Hvordan skal kortet se ud for gæsterne?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Du har valgt et område. Vælg om gæster skal se et almindeligt kort '
            'eller et håndtegnet illustreret kort ovenpå det samme GPS-område.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _ChoiceCard(
            icon: Icons.map_outlined,
            title: 'Standardkort',
            subtitle:
                'OpenStreetMap med veje, bygninger og terræn. '
                'Klar med det samme — du kan gå i gang med at tegne stier.',
            onTap: () => _useStandardMap(context),
          ),
          const SizedBox(height: 16),
          _ChoiceCard(
            icon: Icons.brush_outlined,
            title: 'Illustreret kort',
            subtitle:
                'Et tegnet kort i din egen stil (fx vandfarve). '
                'Du får en kort guide til at lave det med AI og uploade det — '
                'GPS matcher det valgte område.',
            highlighted: true,
            onTap: () => _useIllustratedMap(context),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlighted ? theme.colorScheme.primaryContainer : theme.cardColor;

    return Card(
      elevation: highlighted ? 2 : 0,
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Text(
                      'Vælg →',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
