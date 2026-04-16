import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre du bas pour les routes `/admin/*` hors du shell `/dashboard`.
class AdminBottomNav extends StatelessWidget {
  const AdminBottomNav({super.key});

  static int selectedIndexForPath(String path) {
    if (path.startsWith('/admin/enrollments')) return 1;
    if (path.startsWith('/admin/students')) return 2;
    if (path.startsWith('/admin/classes')) return 3;
    return 0; // Accueil (/dashboard, etc.)
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
            context.go('/admin/enrollments');
            break;
          case 2:
            context.go('/admin/students');
            break;
          case 3:
            context.go('/admin/classes');
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
        NavigationDestination(
            icon: Icon(Icons.person_add), label: 'Inscriptions'),
        NavigationDestination(icon: Icon(Icons.people), label: 'Élèves'),
        NavigationDestination(icon: Icon(Icons.class_), label: 'Classes'),
      ],
    );
  }
}

