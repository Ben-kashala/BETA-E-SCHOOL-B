import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/network/api_service.dart';

void _showChangePasswordDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => const _ChangePasswordDialog(),
  );
}

void _showHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Aide'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bienvenue sur E-School.'),
            const SizedBox(height: 12),
            const Text('Fonctionnalités principales :'),
            const SizedBox(height: 8),
            const Text('• Tableau de bord : vue d\'ensemble de votre activité'),
            const Text('• Cours & Devoirs : accédez à vos contenus et rendus'),
            const Text('• Notes & Bulletins : consultez vos résultats'),
            const Text('• Paiements : suivez les frais scolaires'),
            const Text('• Réunions : dates des rencontres parent-enseignant'),
            const Text('• Bibliothèque : livres et ressources'),
            const SizedBox(height: 12),
            const Text('En cas de problème, contactez l\'administration de votre école.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

void _showAboutDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('À propos'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('E-School', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Application mobile de gestion scolaire.'),
            SizedBox(height: 12),
            Text('Plateforme digitale pour les écoles : cours, notes, paiements, réunions et plus.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les nouveaux mots de passe ne correspondent pas.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService().post(
        '/api/auth/users/change_password/',
        data: {
          'current_password': _currentController.text,
          'new_password': _newController.text,
          'new_password2': _confirmController.text,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié avec succès.'), backgroundColor: Colors.green),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      String msg = 'Erreur lors du changement de mot de passe.';
      final data = e.response?.data;
      if (data is Map) {
        for (final key in ['current_password', 'new_password', 'new_password2', 'non_field_errors', 'detail']) {
          final v = data[key];
          if (v is String) { msg = v; break; }
          if (v is List && v.isNotEmpty && v[0] is String) { msg = v[0] as String; break; }
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Changer le mot de passe'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Mot de passe actuel',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'Au moins 6 caractères' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmer le nouveau mot de passe',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Modifier'),
        ),
      ],
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isStudent = user?.isStudent ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                user?.firstName[0].toUpperCase() ?? (isStudent ? 'E' : 'P'),
                style: const TextStyle(fontSize: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user?.fullName ?? (isStudent ? 'Élève' : 'Parent'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (isStudent && user?.studentId != null) ...[
              const SizedBox(height: 8),
              Text(
                'Matricule: ${user!.studentId}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 32),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.email),
                    title: const Text('Email'),
                    subtitle: Text(user?.email ?? ''),
                  ),
                  if (user?.phone != null) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: const Text('Téléphone'),
                      subtitle: Text(user!.phone!),
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Rôle'),
                    subtitle: Text(
                      isStudent 
                        ? 'Élève' 
                        : user?.isParent == true 
                          ? 'Parent' 
                          : user?.role ?? 'Utilisateur',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Changer le mot de passe'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showChangePasswordDialog(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Préférences'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.push('/preferences');
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Aide'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showHelpDialog(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('À propos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showAboutDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Déconnexion'),
                    content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Annuler'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Déconnexion'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Déconnexion'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
