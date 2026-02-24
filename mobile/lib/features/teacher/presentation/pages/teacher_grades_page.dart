import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

class TeacherGradesPage extends ConsumerStatefulWidget {
  const TeacherGradesPage({super.key});

  @override
  ConsumerState<TeacherGradesPage> createState() => _TeacherGradesPageState();
}

class _TeacherGradesPageState extends ConsumerState<TeacherGradesPage> {
  List<dynamic> _classes = [];
  List<dynamic> _subjects = [];
  int? _selectedClassId;
  int? _selectedSubjectId;
  List<dynamic> _grades = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadSubjects();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/schools/classes/');
      setState(() {
        _classes = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSubjects() async {
    try {
      final response = await ApiService().get('/api/schools/subjects/');
      setState(() {
        _subjects = response.data is List ? response.data : (response.data['results'] ?? []);
      });
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _loadGrades() async {
    if (_selectedClassId == null || _selectedSubjectId == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/academics/grades/', queryParameters: {
        'school_class': _selectedClassId.toString(),
        'subject': _selectedSubjectId.toString(),
      });
      setState(() {
        _grades = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Ajouter une note
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtres
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: _selectedClassId,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: _classes.map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'] ?? 'Classe'),
                    )).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value;
                        _grades = [];
                      });
                      _loadGrades();
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(labelText: 'Matière'),
                    items: _subjects.map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name'] ?? 'Matière'),
                    )).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSubjectId = value;
                        _grades = [];
                      });
                      _loadGrades();
                    },
                  ),
                ],
              ),
            ),
          ),
          // Liste des notes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _grades.isEmpty
                    ? const Center(child: Text('Aucune note'))
                    : ListView.builder(
                        itemCount: _grades.length,
                        itemBuilder: (context, index) {
                          final grade = _grades[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(grade['student_name'] ?? 'Élève'),
                              subtitle: Text('Note: ${grade['score'] ?? 'N/A'}/${grade['total_points'] ?? 'N/A'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                // TODO: Modifier la note
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
