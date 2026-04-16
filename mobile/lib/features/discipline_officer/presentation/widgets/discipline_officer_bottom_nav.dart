import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre du bas pour les routes `/discipline-officer/*` hors du shell `/dashboard`.
class DisciplineOfficerBottomNav extends StatelessWidget {
  const DisciplineOfficerBottomNav({super.key});

  static int selectedIndexForPath(String path) {
    if (path.startsWith('/discipline-officer/discipline')) return 1;
    if (path.startsWith('/discipline-officer/meetings')) return 2;
    if (path.startsWith('/discipline-officer/communication')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    return NavigationBar(
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: selectedIndexForPath(path),
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.go('/dashboard');
            break;
          case 1:
            context.go('/discipline-officer/discipline');
            break;
          case 2:
            context.go('/discipline-officer/meetings');
            break;
          case 3:
            context.go('/discipline-officer/communication');
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.gavel), label: 'Discipline'),
        NavigationDestination(icon: Icon(Icons.event), label: 'Réunions'),
        NavigationDestination(icon: Icon(Icons.message), label: 'Messages'),
      ],
    );
  }
}

