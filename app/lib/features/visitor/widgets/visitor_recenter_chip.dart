import 'package:flutter/material.dart';

class VisitorRecenterChip extends StatelessWidget {
  const VisitorRecenterChip({
    super.key,
    required this.onTap,
    this.bottom = 168,
  });

  final VoidCallback onTap;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: Center(
        child: Material(
          elevation: 3,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.navigation,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Centrér igen',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
