import 'package:flutter/material.dart';

/// Fixed center crop frame for choosing map area during setup.
class AreaCropOverlay extends StatelessWidget {
  const AreaCropOverlay({
    super.key,
    required this.cropFraction,
  });

  /// Fraction of the shortest map side used for the square crop frame.
  final double cropFraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide * cropFraction;
        return IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2.5,
                    ),
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Kortudsnit',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Slider for adjusting crop frame size.
class AreaCropSizeControl extends StatelessWidget {
  const AreaCropSizeControl({
    super.key,
    required this.cropFraction,
    required this.onChanged,
  });

  final double cropFraction;
  final ValueChanged<double> onChanged;

  static const minFraction = 0.25;
  static const maxFraction = 0.92;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = cropFraction < 0.45
        ? 'Lille'
        : cropFraction < 0.7
            ? 'Mellem'
            : 'Stort';

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.crop_free, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Størrelse på kortudsnit',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
            Slider(
              value: cropFraction,
              min: minFraction,
              max: maxFraction,
              divisions: 13,
              label: label,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
