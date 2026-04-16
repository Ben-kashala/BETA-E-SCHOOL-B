import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre du bas pour les élèves sur les routes « modules » (cours, devoirs, bibliothèque…).
class StudentBottomNav extends StatelessWidget {
  const StudentBottomNav({super.key});

  static int selectedIndexForPath(String path) {
    if (path.startsWith('/courses')) return 1;
    if (path.startsWith('/assignments')) return 2;
    if (path.startsWith('/library')) return 3;
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
            context.go('/courses');
            break;
          case 2:
            context.go('/assignments');
            break;
          case 3:
            context.go('/library');
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.book), label: 'Cours'),
        NavigationDestination(icon: Icon(Icons.assignment), label: 'Devoirs'),
        NavigationDestination(
            icon: Icon(Icons.library_books), label: 'Bibliothèque'),
      ],
    );
  }
}

