import 'package:flutter/material.dart';

enum VisitorTab { explore, route, audioTour }

class VisitorBottomNav extends StatelessWidget {
  const VisitorBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
    this.showAudioTour = false,
  });

  final VisitorTab current;
  final ValueChanged<VisitorTab> onChanged;
  final bool showAudioTour;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: 'Udforsk',
                selected: current == VisitorTab.explore,
                onTap: () => onChanged(VisitorTab.explore),
              ),
              _NavItem(
                icon: Icons.directions_outlined,
                selectedIcon: Icons.directions,
                label: 'Rute',
                selected: current == VisitorTab.route,
                onTap: () => onChanged(VisitorTab.route),
              ),
              if (showAudioTour)
                _NavItem(
                  icon: Icons.headphones_outlined,
                  selectedIcon: Icons.headphones,
                  label: 'Lydvandring',
                  selected: current == VisitorTab.audioTour,
                  onTap: () => onChanged(VisitorTab.audioTour),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF1565C0) : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? (selectedIcon ?? icon) : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
