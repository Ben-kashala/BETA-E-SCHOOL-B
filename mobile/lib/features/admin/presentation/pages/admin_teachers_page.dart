import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminTeachersPage extends ConsumerStatefulWidget {
  const AdminTeachersPage({super.key});

  @override
  ConsumerState<AdminTeachersPage> createState() => _AdminTeachersPageState();
}

class _AdminTeachersPageState extends ConsumerState<AdminTeachersPage> {
  List<dynamic> _teachers = [];
  List<dynamic> _filteredTeachers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/accounts/teachers/', useCache: false);
      setState(() {
        _teachers = response.data is List
            ? response.data
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredTeachers = _teachers.where((teacher) {
        if (_searchQuery.isNotEmpty) {
          final name = '${teacher['user']?['first_name'] ?? ''} ${teacher['user']?['last_name'] ?? ''}'.toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  void _showTeacherDetail(dynamic teacher) {
    final user = teacher['user'] ?? {};
    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Détail enseignant'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(Icons.person, 'Nom', name.isEmpty ? '—' : name),
              _detailRow(Icons.email, 'Email', user['email'] ?? '—'),
              _detailRow(Icons.badge, 'Matricule', teacher['employee_id']?.toString() ?? '—'),
              if (teacher['specialization'] != null && (teacher['specialization'] as String).isNotEmpty)
                _detailRow(Icons.school, 'Spécialisation', teacher['specialization'] as String),
              if (user['phone'] != null && (user['phone'] as String).isNotEmpty)
                _detailRow(Icons.phone, 'Téléphone', user['phone'] as String),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showTeacherForm(teacher: teacher);
            },
            child: const Text('Modifier'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateTeacher() {
    _showTeacherForm();
  }

  void _showTeacherForm({dynamic teacher}) {
    final formKey = GlobalKey<FormState>();
    final teacherMap = teacher is Map ? Map<String, dynamic>.from(teacher) : null;
    final user = teacherMap?['user'] is Map
        ? Map<String, dynamic>.from(teacherMap!['user'] as Map)
        : <String, dynamic>{};
    final isEditing = teacherMap != null;

    final username = TextEditingController(text: '${user['username'] ?? ''}');
    final email = TextEditingController(text: '${user['email'] ?? ''}');
    final firstName = TextEditingController(text: '${user['first_name'] ?? ''}');
    final lastName = TextEditingController(text: '${user['last_name'] ?? ''}');
    final phone = TextEditingController(text: '${user['phone'] ?? ''}');
    final password = TextEditingController();
    final password2 = TextEditingController();
    final employeeId =
        TextEditingController(text: '${teacherMap?['employee_id'] ?? ''}');
    final specialization =
        TextEditingController(text: '${teacherMap?['specialization'] ?? ''}');
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEditing ? 'Modifier l\'enseignant' : 'Créer un enseignant',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Nom d\'utilisateur *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      decoration: const InputDecoration(labelText: 'Email *'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'Téléphone'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: firstName,
                      decoration: const InputDecoration(labelText: 'Prénom *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: lastName,
                      decoration: const InputDecoration(labelText: 'Nom *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    if (!isEditing) ...[
                      TextFormField(
                        controller: password,
                        decoration: const InputDecoration(labelText: 'Mot de passe *'),
                        obscureText: true,
                        validator: (v) => (v == null || v.length < 6) ? 'Min. 6 caractères' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password2,
                        decoration: const InputDecoration(labelText: 'Confirmer le mot de passe *'),
                        obscureText: true,
                        validator: (v) => v != password.text ? 'Les mots de passe ne correspondent pas' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: employeeId,
                      decoration: const InputDecoration(labelText: 'Matricule (optionnel)'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: specialization,
                      decoration: const InputDecoration(labelText: 'Spécialisation (optionnel)'),
                    ),
                    const SizedBox(height: 24),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Annuler'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => loading = true);
                                try {
                                  if (isEditing) {
                                    final teacherId = teacherMap['id'];
                                    final userId = user['id'];
                                    if (teacherId == null || userId == null) {
                                      throw Exception('Identifiants enseignant/utilisateur introuvables.');
                                    }

                                    await ApiService().patch(
                                      '/api/auth/users/$userId/',
                                      data: {
                                        'username': username.text.trim(),
                                        'email': email.text.trim(),
                                        'first_name': firstName.text.trim(),
                                        'last_name': lastName.text.trim(),
                                        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                                      },
                                    );
                                    await ApiService().patch(
                                      '/api/auth/teachers/$teacherId/',
                                      data: {
                                        if (employeeId.text.trim().isNotEmpty)
                                          'employee_id': employeeId.text.trim()
                                        else
                                          'employee_id': null,
                                        if (specialization.text.trim().isNotEmpty)
                                          'specialization': specialization.text.trim()
                                        else
                                          'specialization': null,
                                      },
                                    );
                                  } else {
                                    final registerRes = await ApiService().post('/api/auth/register/', data: {
                                      'username': username.text.trim(),
                                      'email': email.text.trim(),
                                      'first_name': firstName.text.trim(),
                                      'last_name': lastName.text.trim(),
                                      'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                                      'password': password.text,
                                      'password2': password2.text,
                                      'role': 'TEACHER',
                                    });
                                    final userId = registerRes.data is Map ? (registerRes.data as Map)['id'] as int? : null;
                                    if (userId == null) {
                                      setModalState(() => loading = false);
                                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Utilisateur créé mais ID introuvable dans la réponse.')));
                                      return;
                                    }
                                    await ApiService().post('/api/auth/teachers/', data: {
                                      'user_id': userId,
                                      if (employeeId.text.trim().isNotEmpty) 'employee_id': employeeId.text.trim(),
                                      if (specialization.text.trim().isNotEmpty) 'specialization': specialization.text.trim(),
                                    });
                                  }
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing
                                              ? 'Enseignant modifié avec succès.'
                                              : 'Enseignant créé avec succès.',
                                        ),
                                      ),
                                    );
                                    _loadTeachers();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')),
                                    );
                                  }
                                }
                              },
                              child: Text(isEditing ? 'Enregistrer' : 'Créer'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enseignants'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateTeacher,
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un enseignant...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTeachers.isEmpty
                    ? const Center(child: Text('Aucun enseignant'))
                    : RefreshIndicator(
                        onRefresh: _loadTeachers,
                        child: ListView.builder(
                          itemCount: _filteredTeachers.length,
                          itemBuilder: (context, index) {
                            final teacher = _filteredTeachers[index];
                            final user = teacher['user'] ?? {};
                            final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppTheme.avatarBackgroundColor,
                                  foregroundColor: AppTheme.onAvatarBackgroundColor,
                                  child: Icon(Icons.person),
                                ),
                                title: Text(name.isEmpty ? 'Enseignant' : name),
                                subtitle: Text(user['email'] ?? ''),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showTeacherDetail(teacher),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}
