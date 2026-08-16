import 'package:flutter/material.dart';

import '../../../core/navigation/route_guidance.dart';

class VisitorTurnBanner extends StatelessWidget {
  const VisitorTurnBanner({
    super.key,
    required this.instruction,
    required this.destinationLabel,
    required this.onStop,
  });

  final NavigationInstruction instruction;
  final String destinationLabel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFF1565C0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _iconForManeuver(instruction.kind),
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instruction.primaryText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    instruction.secondaryText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destinationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onStop,
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Afslut navigation',
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForManeuver(ManeuverKind kind) {
    return switch (kind) {
      ManeuverKind.depart => Icons.navigation,
      ManeuverKind.continueStraight => Icons.arrow_upward,
      ManeuverKind.turnSlightLeft => Icons.turn_slight_left,
      ManeuverKind.turnLeft => Icons.turn_left,
      ManeuverKind.turnSharpLeft => Icons.subdirectory_arrow_left,
      ManeuverKind.turnSlightRight => Icons.turn_slight_right,
      ManeuverKind.turnRight => Icons.turn_right,
      ManeuverKind.turnSharpRight => Icons.subdirectory_arrow_right,
      ManeuverKind.arrive => Icons.flag,
    };
  }
}
