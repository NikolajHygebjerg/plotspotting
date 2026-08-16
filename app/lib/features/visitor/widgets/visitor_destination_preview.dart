import 'package:flutter/material.dart';

import '../../../core/geo/geo_utils.dart';
import '../../../core/routing/routing_service.dart';

class VisitorDestinationPreview extends StatelessWidget {
  const VisitorDestinationPreview({
    super.key,
    required this.startLabel,
    required this.destinationLabel,
    required this.distanceMeters,
    required this.canStart,
    required this.onStartRoute,
    required this.onClose,
    this.approachMeters = 0,
    this.departureMeters = 0,
    this.statusHint,
  });

  final String startLabel;
  final String destinationLabel;
  final double? distanceMeters;
  final bool canStart;
  final double approachMeters;
  final double departureMeters;
  final String? statusHint;
  final VoidCallback onStartRoute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    destinationLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Fra: $startLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (distanceMeters != null) ...[
              const SizedBox(height: 8),
              Text(
                distanceMeters! > 0
                    ? '${distanceMeters!.round()} m · ca. ${estimateWalkMinutes(distanceMeters!)} min gang'
                    : 'Du er ved destinationen',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (approachMeters > RoutingService.approachMergeMeters) ...[
              const SizedBox(height: 6),
              Text(
                'Først ca. ${approachMeters.round()} m til nærmeste sti',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF1565C0),
                    ),
              ),
            ],
            if (departureMeters > RoutingService.approachMergeMeters) ...[
              const SizedBox(height: 6),
              Text(
                'Til sidst ca. ${departureMeters.round()} m fra stien til huset',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF1565C0),
                    ),
              ),
            ],
            if (statusHint != null && !canStart) ...[
              const SizedBox(height: 8),
              Text(
                statusHint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF1565C0),
                    ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canStart ? onStartRoute : null,
              icon: const Icon(Icons.directions_walk),
              label: const Text('Start rute'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF1565C0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
