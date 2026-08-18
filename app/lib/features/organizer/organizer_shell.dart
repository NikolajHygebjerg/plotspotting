import 'package:flutter/material.dart';

import '../account/user_account_screen.dart';
import '../map_editor/mapping_method.dart';

/// Fælles app bar for arrangør-flow med bruger-knap.
class OrganizerShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OrganizerShellAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      title: Text(title),
      actions: [
        ...actions,
        IconButton(
          tooltip: 'Bruger',
          icon: const Icon(Icons.person_outline),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserAccountScreen()),
            );
          },
        ),
      ],
    );
  }
}

/// Bundmenu med gæstvisning + rediger-faner.
class OrganizerBottomNav extends StatelessWidget {
  const OrganizerBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.visibility_outlined),
      selectedIcon: Icon(Icons.visibility),
      label: 'Gæst',
    ),
    NavigationDestination(
      icon: Icon(Icons.route_outlined),
      selectedIcon: Icon(Icons.route),
      label: 'Ruter',
    ),
    NavigationDestination(
      icon: Icon(Icons.place_outlined),
      selectedIcon: Icon(Icons.place),
      label: 'Steder',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: 'Kort',
    ),
    NavigationDestination(
      icon: Icon(Icons.headphones_outlined),
      selectedIcon: Icon(Icons.headphones),
      label: 'Lyd',
    ),
    NavigationDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag),
      label: 'Skattejagt',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
    );
  }
}

int organizerNavIndexForSection(EditorSection section) => section.index + 1;

EditorSection? editorSectionFromNavIndex(int index) {
  if (index <= 0) return null;
  final sections = EditorSection.values;
  final i = index - 1;
  if (i < 0 || i >= sections.length) return null;
  return sections[i];
}
