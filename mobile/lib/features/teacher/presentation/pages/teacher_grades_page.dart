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
      }, useCache: false);
      setState(() {
        _grades = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddGrade() {
    if (_selectedClassId == null || _selectedSubjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez sélectionner une classe et une matière.')));
      return;
    }
    _showAddOrEditGrade(context: context, classId: _selectedClassId!, subjectId: _selectedSubjectId!, existingGrade: null);
  }

  void _showEditGrade(dynamic grade) {
    _showAddOrEditGrade(
      context: context,
      classId: _selectedClassId,
      subjectId: _selectedSubjectId,
      existingGrade: grade,
    );
  }

  Future<void> _showAddOrEditGrade({required BuildContext context, int? classId, int? subjectId, dynamic existingGrade}) async {
    List<dynamic> students = [];
    String academicYear = '${DateTime.now().year}-${DateTime.now().year + 1}';
    try {
      final ay = await ApiService().get('/api/academics/academic-years/available/', useCache: false);
      if (ay.data is Map && (ay.data as Map)['current'] != null) {
        academicYear = (ay.data as Map)['current'] as String;
      }
      if (classId != null) {
        final s = await ApiService().get('/api/auth/students/', queryParameters: {'school_class': classId.toString()}, useCache: false);
        students = s.data is List ? s.data : (s.data['results'] ?? []);
      }
    } catch (_) {}

    final formKey = GlobalKey<FormState>();
    final continuousCtrl = TextEditingController(text: existingGrade != null ? (existingGrade['continuous_assessment']?.toString() ?? '') : '');
    final examCtrl = TextEditingController(text: existingGrade != null ? (existingGrade['exam_score']?.toString() ?? '') : '');
    int? studentId = existingGrade != null ? (existingGrade['student'] as int?) : (students.isNotEmpty ? (students.first['id'] as int) : null);
    String term = existingGrade?['term'] ?? 'T1';
    String year = existingGrade?['academic_year'] ?? academicYear;
    bool loading = false;
    final isEdit = existingGrade != null;

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
                    Text(isEdit ? 'Modifier la note' : 'Ajouter une note', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (isEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Élève: ${existingGrade['student_name'] ?? ''}', style: Theme.of(context).textTheme.titleSmall),
                      )
                    else
                      DropdownButtonFormField<int>(
                        value: studentId,
                        decoration: const InputDecoration(labelText: 'Élève *'),
                        items: students.map((s) {
                          final name = s['user_name'] ?? '${s['user']?['first_name'] ?? ''} ${s['user']?['last_name'] ?? ''}'.trim();
                          return DropdownMenuItem<int>(value: s['id'] as int, child: Text(name.isEmpty ? 'Élève' : name));
                        }).toList(),
                        onChanged: (v) => setModalState(() => studentId = v),
                        validator: (v) => v == null ? 'Requis' : null,
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: year,
                      decoration: const InputDecoration(labelText: 'Année scolaire'),
                      items: [year, '${DateTime.now().year - 1}-${DateTime.now().year}', '${DateTime.now().year + 1}-${DateTime.now().year + 2}'].toSet().map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                      onChanged: (v) => setModalState(() => year = v ?? year),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: term,
                      decoration: const InputDecoration(labelText: 'Trimestre'),
                      items: const [
                        DropdownMenuItem(value: 'T1', child: Text('Trimestre 1')),
                        DropdownMenuItem(value: 'T2', child: Text('Trimestre 2')),
                        DropdownMenuItem(value: 'T3', child: Text('Trimestre 3')),
                      ],
                      onChanged: (v) => setModalState(() => term = v ?? 'T1'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: continuousCtrl,
                      decoration: const InputDecoration(labelText: 'Contrôle continu (0-20) *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        final n = double.tryParse(v.replaceFirst(',', '.'));
                        if (n == null || n < 0 || n > 20) return 'Entre 0 et 20';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: examCtrl,
                      decoration: const InputDecoration(labelText: 'Note d\'examen (0-20, optionnel)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = double.tryParse(v.replaceFirst(',', '.'));
                        if (n == null || n < 0 || n > 20) return 'Entre 0 et 20';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => loading = true);
                                try {
                                  if (isEdit) {
                                    await ApiService().patch('/api/academics/grades/${existingGrade['id']}/', data: {
                                      'continuous_assessment': double.tryParse(continuousCtrl.text.replaceFirst(',', '.')) ?? 0,
                                      if (examCtrl.text.trim().isNotEmpty) 'exam_score': double.tryParse(examCtrl.text.replaceFirst(',', '.')),
                                    });
                                  } else {
                                    await ApiService().post('/api/academics/grades/', data: {
                                      'student': studentId,
                                      'subject': subjectId!,
                                      'academic_year': year,
                                      'term': term,
                                      'continuous_assessment': double.tryParse(continuousCtrl.text.replaceFirst(',', '.')) ?? 0,
                                      if (examCtrl.text.trim().isNotEmpty) 'exam_score': double.tryParse(examCtrl.text.replaceFirst(',', '.')),
                                    });
                                  }
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(isEdit ? 'Note mise à jour.' : 'Note enregistrée.')));
                                    _loadGrades();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')));
                                }
                              },
                              child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
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
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddGrade,
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
                          final total = grade['total_score'] ?? grade['score'];
                          final totalStr = total != null ? (total is num ? (total as num).toStringAsFixed(1) : total.toString()) : 'N/A';
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(grade['student_name'] ?? 'Élève'),
                              subtitle: Text('Note: $totalStr/20'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showEditGrade(grade),
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
