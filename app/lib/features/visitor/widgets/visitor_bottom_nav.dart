import 'package:flutter/material.dart';

enum VisitorTab { map, search, favorites, menu }

class VisitorBottomNav extends StatelessWidget {
  const VisitorBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final VisitorTab current;
  final ValueChanged<VisitorTab> onChanged;

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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map,
                label: 'Kort',
                selected: current == VisitorTab.map,
                onTap: () => onChanged(VisitorTab.map),
              ),
              _NavItem(
                icon: Icons.search,
                label: 'Søg',
                selected: current == VisitorTab.search,
                onTap: () => onChanged(VisitorTab.search),
              ),
              _NavItem(
                icon: Icons.favorite_border,
                selectedIcon: Icons.favorite,
                label: 'Favoritter',
                selected: current == VisitorTab.favorites,
                onTap: () => onChanged(VisitorTab.favorites),
              ),
              _NavItem(
                icon: Icons.menu,
                label: 'Menu',
                selected: current == VisitorTab.menu,
                onTap: () => onChanged(VisitorTab.menu),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
