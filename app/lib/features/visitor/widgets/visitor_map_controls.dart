import 'package:flutter/material.dart';

class VisitorMapControls extends StatelessWidget {
  const VisitorMapControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Icons.add,
          tooltip: 'Zoom ind',
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 8),
        _ControlButton(
          icon: Icons.remove,
          tooltip: 'Zoom ud',
          onPressed: onZoomOut,
        ),
        const SizedBox(height: 8),
        _ControlButton(
          icon: Icons.navigation,
          tooltip: 'Centrer på mig',
          onPressed: onRecenter,
          filled: true,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      color: filled ? const Color(0xFF1565C0) : Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              size: 22,
              color: filled ? Colors.white : const Color(0xFF1565C0),
            ),
          ),
        ),
      ),
    );
  }
}
