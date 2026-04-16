import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre du bas pour les routes `/accountant/*` hors du shell `/dashboard`.
/// Communication et hub « Compta » restent accessibles depuis la grille du tableau de bord.
class AccountantBottomNav extends StatelessWidget {
  const AccountantBottomNav({super.key});

  static int selectedIndexForPath(String path) {
    if (path.startsWith('/accountant/payments')) return 1;
    if (path.startsWith('/accountant/expenses')) return 2;
    if (path.startsWith('/accountant/caisse')) return 3;
    // Accueil : /dashboard, /accountant, inscriptions, communication, etc.
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
            context.go('/accountant/payments');
            break;
          case 2:
            context.go('/accountant/expenses');
            break;
          case 3:
            context.go('/accountant/caisse');
            break;
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.payment), label: 'Paiements'),
        NavigationDestination(icon: Icon(Icons.money_off), label: 'Dépenses'),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet),
          label: 'Caisse',
        ),
      ],
    );
  }
}
