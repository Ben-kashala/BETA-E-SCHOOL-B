import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class TeacherStudentsPage extends ConsumerStatefulWidget {
  const TeacherStudentsPage({super.key});

  @override
  ConsumerState<TeacherStudentsPage> createState() => _TeacherStudentsPageState();
}

class _TeacherStudentsPageState extends ConsumerState<TeacherStudentsPage> {
  List<dynamic> _students = [];
  List<dynamic> _filteredStudents = [];
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
      final students = response.data is List 
          ? response.data 
          : (response.data['results'] ?? []);
      
      setState(() {
        _students = students;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _studentClassLabel(dynamic student) {
    if (student is! Map) return '';
    final direct = student['class_name'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct';
    final sc = student['school_class'];
    if (sc is Map) {
      final n = sc['name'];
      if (n != null && '$n'.trim().isNotEmpty) return '$n';
    }
    if (sc is int) return 'Classe #$sc';
    if (sc is num) return 'Classe #${sc.toInt()}';
    return '';
  }

  void _applyFilters() {
    setState(() {
      _filteredStudents = _students.where((student) {
        if (_searchQuery.isNotEmpty) {
          final user = student['user'] ?? {};
          final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.toLowerCase();
          final studentId = (student['student_id'] ?? '').toString().toLowerCase();
          if (!name.contains(_searchQuery.toLowerCase()) && 
              !studentId.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes élèves'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un élève...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStudents.isEmpty
                    ? const Center(child: Text('Aucun élève trouvé'))
                    : RefreshIndicator(
                        onRefresh: _loadStudents,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            final user = student['user'] ?? {};
                            final firstName = user['first_name'] ?? '';
                            final lastName = user['last_name'] ?? '';
                            final studentId = student['student_id'] ?? '';
                            final className = _studentClassLabel(student);
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                                  child: Text(
                                    firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                                  ),
                                ),
                                title: Text('$firstName $lastName'.trim()),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (studentId.isNotEmpty) Text('Matricule: $studentId'),
                                    if (className.isNotEmpty) Text('Classe: $className'),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  context.push('/students/${student['id']}');
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
