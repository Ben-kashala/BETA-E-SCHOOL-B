import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class AdminStudentsPage extends ConsumerStatefulWidget {
  const AdminStudentsPage({super.key});

  @override
  ConsumerState<AdminStudentsPage> createState() => _AdminStudentsPageState();
}

class _AdminStudentsPageState extends ConsumerState<AdminStudentsPage> {
  List<dynamic> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/accounts/students/');
      setState(() {
        _students = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    final query = _searchQuery.toLowerCase();
    return _students.where((student) {
      final name = '${student['user']?['first_name'] ?? ''} ${student['user']?['last_name'] ?? ''}'.toLowerCase();
      final studentId = student['student_id']?.toString().toLowerCase() ?? '';
      return name.contains(query) || studentId.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Élèves'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/admin/enrollments'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un élève...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          // Liste des élèves
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStudents.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? 'Aucun élève' : 'Aucun résultat',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredStudents.length,
                        itemBuilder: (context, index) {
                          final student = _filteredStudents[index];
                          final user = student['user'] ?? {};
                          final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppTheme.avatarBackgroundColor,
                                foregroundColor: AppTheme.onAvatarBackgroundColor,
                                child: Icon(Icons.person),
                              ),
                              title: Text(name.isEmpty ? 'Élève' : name),
                              subtitle: Text('ID: ${student['student_id'] ?? 'N/A'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                final id = student['id'];
                                if (id != null) {
                                  context.push('/students/$id');
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
