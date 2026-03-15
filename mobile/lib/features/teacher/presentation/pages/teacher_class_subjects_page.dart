import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class TeacherClassSubjectsPage extends ConsumerStatefulWidget {
  const TeacherClassSubjectsPage({super.key, this.initialClassId});

  final int? initialClassId;

  @override
  ConsumerState<TeacherClassSubjectsPage> createState() => _TeacherClassSubjectsPageState();
}

class _TeacherClassSubjectsPageState extends ConsumerState<TeacherClassSubjectsPage> {
  List<dynamic> _classes = [];
  int? _selectedClassId;
  List<dynamic> _classSubjects = [];
  List<dynamic> _allSubjects = [];
  List<dynamic> _teachers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final [classesRes, subjectsRes, teachersRes] = await Future.wait([
        ApiService().get('/api/schools/classes/my_titular/'),
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/accounts/teachers/', queryParameters: {'page_size': '200'}),
      ]);

      final classes = classesRes.data is List 
          ? classesRes.data 
          : (classesRes.data['results'] ?? []);
      
      int? classToSelect = widget.initialClassId;
      final classIds = classes.map((c) => c['id'] as int?).toSet();
      if (classToSelect == null || !classIds.contains(classToSelect)) {
        classToSelect = classes.isNotEmpty ? classes.first['id'] as int? : null;
      }
      setState(() {
        _classes = classes;
        _allSubjects = subjectsRes.data is List 
            ? subjectsRes.data 
            : (subjectsRes.data['results'] ?? []);
        _teachers = teachersRes.data is List 
            ? teachersRes.data 
            : (teachersRes.data['results'] ?? []);
        _selectedClassId = classToSelect;
        _isLoading = false;
      });
      if (classToSelect != null) {
        await _loadClassSubjects(classToSelect);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClassSubjects(int classId) async {
    try {
      final response = await ApiService().get('/api/schools/class-subjects/', queryParameters: {
        'school_class': classId.toString(),
      });
      
      setState(() {
        _classSubjects = response.data is List 
            ? response.data 
            : (response.data['results'] ?? []);
      });
    } catch (e) {
      setState(() => _classSubjects = []);
    }
  }

  Future<void> _addSubject(int subjectId, int periodMax, int? teacherId) async {
    if (_selectedClassId == null) return;
    
    try {
      await ApiService().post('/api/schools/class-subjects/', data: {
        'school_class': _selectedClassId,
        'subject': subjectId,
        'period_max': periodMax,
        if (teacherId != null) 'teacher': teacherId,
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matière ajoutée à la classe')),
      );
      await _loadClassSubjects(_selectedClassId!);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _updateSubject(int id, {int? periodMax, int? teacherId}) async {
    try {
      final data = <String, dynamic>{};
      if (periodMax != null) data['period_max'] = periodMax;
      if (teacherId != null) data['teacher'] = teacherId;
      
      await ApiService().patch('/api/schools/class-subjects/$id/', data: data);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mise à jour enregistrée')),
      );
      await _loadClassSubjects(_selectedClassId!);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _deleteSubject(int id) async {
    try {
      await ApiService().delete('/api/schools/class-subjects/$id/');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matière retirée de la classe')),
      );
      await _loadClassSubjects(_selectedClassId!);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  void _showAddSubjectDialog() {
    int? selectedSubjectId;
    int periodMax = 20;
    int? selectedTeacherId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter une matière'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Matière *'),
                  items: _allSubjects.where((s) {
                    final assignedIds = _classSubjects.map((cs) => cs['subject']).toSet();
                    return !assignedIds.contains(s['id']);
                  }).map((s) {
                    return DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name'] ?? 'Matière'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedSubjectId = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Note max période'),
                  value: periodMax,
                  items: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].map((v) {
                    return DropdownMenuItem(value: v, child: Text('$v'));
                  }).toList(),
                  onChanged: (value) => setDialogState(() => periodMax = value ?? 20),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Enseignant (optionnel)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucun')),
                    ..._teachers.map((t) {
                      return DropdownMenuItem<int>(
                        value: t['id'] as int,
                        child: Text('${t['user']?['first_name'] ?? ''} ${t['user']?['last_name'] ?? ''}'.trim()),
                      );
                    }),
                  ],
                  onChanged: (value) => setDialogState(() => selectedTeacherId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: selectedSubjectId == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _addSubject(selectedSubjectId!, periodMax, selectedTeacherId);
                    },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Matières par classe')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Matières par classe')),
        body: const Center(
          child: Text('Vous n\'êtes pas titulaire d\'une classe'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matières par classe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddSubjectDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Sélecteur de classe
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Classe',
                border: OutlineInputBorder(),
              ),
              value: _selectedClassId,
              items: _classes.map((c) {
                return DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text('${c['name'] ?? ''} ${c['academic_year'] != null ? '(${c['academic_year']})' : ''}'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedClassId = value);
                if (value != null) {
                  _loadClassSubjects(value);
                }
              },
            ),
          ),
          // Liste des matières
          Expanded(
            child: _classSubjects.isEmpty
                ? const Center(child: Text('Aucune matière assignée'))
                : RefreshIndicator(
                    onRefresh: () => _loadClassSubjects(_selectedClassId!),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _classSubjects.length,
                      itemBuilder: (context, index) {
                        final cs = _classSubjects[index];
                        final subject = cs['subject'] ?? {};
                        final teacher = cs['teacher'] ?? {};
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            title: Text(subject['name'] ?? 'Matière'),
                            subtitle: Text('Note max: ${cs['period_max'] ?? 20}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Note max période:'),
                                        DropdownButton<int>(
                                          value: cs['period_max'] ?? 20,
                                          items: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].map((v) {
                                            return DropdownMenuItem(value: v, child: Text('$v'));
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              _updateSubject(cs['id'], periodMax: value);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Enseignant:'),
                                        DropdownButton<int?>(
                                          value: cs['teacher'] != null ? cs['teacher'] : null,
                                          items: [
                                            const DropdownMenuItem(value: null, child: Text('Aucun')),
                                            ..._teachers.map((t) {
                                              return DropdownMenuItem(
                                                value: t['id'],
                                                child: Text('${t['user']?['first_name'] ?? ''} ${t['user']?['last_name'] ?? ''}'.trim()),
                                              );
                                            }),
                                          ],
                                          onChanged: (value) {
                                            _updateSubject(cs['id'], teacherId: value);
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        _deleteSubject(cs['id']);
                                      },
                                      icon: const Icon(Icons.delete),
                                      label: const Text('Retirer de la classe'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
