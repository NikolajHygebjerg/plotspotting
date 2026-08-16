import 'package:flutter/material.dart';

class VisitorRouteCard extends StatelessWidget {
  const VisitorRouteCard({
    super.key,
    required this.startLabel,
    required this.destinationLabel,
    this.distanceMeters,
    this.onClose,
  });

  final String startLabel;
  final String destinationLabel;
  final double? distanceMeters;
  final VoidCallback? onClose;

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
                    'Navigation',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _RouteRow(
              icon: Icons.circle,
              iconColor: const Color(0xFF4285F4),
              iconSize: 12,
              label: 'Din placering: $startLabel',
            ),
            const SizedBox(height: 10),
            _RouteRow(
              icon: Icons.location_on,
              iconColor: const Color(0xFFE53935),
              iconSize: 20,
              label: 'Mål: $destinationLabel',
            ),
            if (distanceMeters != null) ...[
              const SizedBox(height: 10),
              Text(
                '${distanceMeters!.round()} m · ca. ${(distanceMeters! / 80).ceil().clamp(1, 999)} min gang',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.iconSize = 18,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.3,
                ),
          ),
        ),
      ],
    );
  }
}
