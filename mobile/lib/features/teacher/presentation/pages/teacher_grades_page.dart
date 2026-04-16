import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../../../../core/network/api_service.dart';

class TeacherGradesPage extends ConsumerStatefulWidget {
  const TeacherGradesPage({super.key});

  @override
  ConsumerState<TeacherGradesPage> createState() => _TeacherGradesPageState();
}

class _TeacherGradesPageState extends ConsumerState<TeacherGradesPage> {
  List<dynamic> _classes = [];
  List<dynamic> _subjects = [];
  List<dynamic> _students = [];
  List<dynamic> _grades = [];
  List<String> _academicYears = [];
  int? _selectedClassId;
  int? _selectedSubjectId;
  String _searchQuery = '';
  String _selectedSemester = 'Premier semestre';
  String _selectedPeriod = '1ère P. (Interrogation)';
  String? _selectedAcademicYear;
  String _selectedTerm = 'T1';
  bool _isLoading = false;
  final Map<int, TextEditingController> _scoreCtrls = {};
  final Map<int, FocusNode> _scoreFocusNodes = {};
  final Set<int> _savingStudentIds = {};
  final Map<int, Timer> _saveDebounceTimers = {};
  final Map<int, ({double obtained, double base})> _subjectTotalsByStudent = {};

  static const _semesters = ['Premier semestre', 'Deuxième semestre'];
  static const _periods = [
    '1ère P. (Interrogation)',
    '2ème P. (Interrogation)',
    'Examen',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    for (final t in _saveDebounceTimers.values) {
      t.cancel();
    }
    for (final c in _scoreCtrls.values) {
      c.dispose();
    }
    for (final f in _scoreFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/api/schools/classes/'),
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/academics/academic-years/available/', useCache: false),
      ]);
      final classes = _extractList(results[0].data);
      final subjects = _extractList(results[1].data);
      final ayData = results[2].data;
      String? currentYear;
      final years = <String>[];
      if (ayData is Map) {
        final cy = '${ayData['current'] ?? ''}'.trim();
        currentYear = cy.isEmpty ? null : cy;
        final raw = ayData['available'];
        if (raw is List) {
          years.addAll(raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty));
        }
      }
      // Valeurs uniques (l’API peut renvoyer des doublons → crash DropdownButton).
      final seenY = <String>{};
      final dedupedYears = years.where((y) => seenY.add(y)).toList();
      years
        ..clear()
        ..addAll(dedupedYears);
      if (currentYear != null && currentYear.isNotEmpty && !years.contains(currentYear)) {
        years.insert(0, currentYear);
      }
      if (years.isEmpty) {
        final now = DateTime.now().year;
        years.addAll(['$now-${now + 1}', '${now - 1}-$now']);
      }
      setState(() {
        _classes = classes;
        _subjects = subjects;
        _academicYears = years;
        _selectedAcademicYear =
            (currentYear != null && years.contains(currentYear)) ? currentYear : years.first;
        _selectedClassId = classes.isNotEmpty ? classes.first['id'] as int? : null;
        _isLoading = false;
      });
      await _loadStudentsAndGrades();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _studentName(dynamic s) {
    final direct = '${s['user_name'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final u = s['user'] ?? {};
    final full = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    return full.isEmpty ? 'Élève' : full;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  String _extractApiError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final m = data['message'] ?? data['error'] ?? data['detail'];
        if (m != null && '$m'.trim().isNotEmpty) return '$m';
      }
      if (e.response?.statusCode == 400) {
        return 'Données invalides. Vérifiez la note et réessayez.';
      }
    }
    return e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '');
  }

  Future<void> _showPopup({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadStudentsAndGrades() async {
    if (_selectedClassId == null) {
      setState(() {
        _students = [];
        _grades = [];
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final studentsRes = await ApiService().get(
        '/api/auth/students/',
        queryParameters: {'school_class': _selectedClassId.toString()},
        useCache: false,
      );
      final students = _extractList(studentsRes.data);
      setState(() => _students = students);
      await _loadGrades();
      await _loadSubjectTotals();
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSubjectTotals() async {
    if (_selectedClassId == null ||
        _selectedAcademicYear == null ||
        _selectedSubjectId == null) {
      if (mounted) {
        setState(() => _subjectTotalsByStudent.clear());
      }
      return;
    }
    try {
      // Certaines implémentations backend exigent `term`.
      // On agrège donc T1/T2/T3 pour la matière courante.
      final responses = await Future.wait([
        ApiService().get(
          '/api/academics/grades/',
          queryParameters: {
            'school_class': _selectedClassId.toString(),
            'subject': _selectedSubjectId.toString(),
            'academic_year': _selectedAcademicYear!,
            'term': 'T1',
          },
          useCache: false,
        ),
        ApiService().get(
          '/api/academics/grades/',
          queryParameters: {
            'school_class': _selectedClassId.toString(),
            'subject': _selectedSubjectId.toString(),
            'academic_year': _selectedAcademicYear!,
            'term': 'T2',
          },
          useCache: false,
        ),
        ApiService().get(
          '/api/academics/grades/',
          queryParameters: {
            'school_class': _selectedClassId.toString(),
            'subject': _selectedSubjectId.toString(),
            'academic_year': _selectedAcademicYear!,
            'term': 'T3',
          },
          useCache: false,
        ),
      ]);
      final rows = <dynamic>[
        ..._extractList(responses[0].data),
        ..._extractList(responses[1].data),
        ..._extractList(responses[2].data),
      ];
      final map = <int, ({double obtained, double base})>{};
      for (final r in rows) {
        final sid = _asInt(r['student']);
        if (sid != null) {
          final current = map[sid] ?? (obtained: 0.0, base: 0.0);
          final score =
              ((r['total_score'] ?? r['continuous_assessment']) as num?)
                      ?.toDouble() ??
                  0.0;
          map[sid] = (
            obtained: current.obtained + score,
            base: current.base + 20.0,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _subjectTotalsByStudent
          ..clear()
          ..addAll(map);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _subjectTotalsByStudent.clear());
    }
  }

  Future<void> _loadGrades() async {
    if (_selectedClassId == null || _selectedSubjectId == null || _selectedAcademicYear == null) {
      setState(() {
        _grades = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/api/academics/grades/',
        queryParameters: {
          'school_class': _selectedClassId.toString(),
          'subject': _selectedSubjectId.toString(),
          'academic_year': _selectedAcademicYear!,
          'term': _selectedTerm,
        },
        useCache: false,
      );
      final grades = _extractList(response.data);
      final next = <int, TextEditingController>{};
      for (final s in _students) {
        final sid = _asInt(s['id']);
        if (sid == null) continue;
        final grade = grades.firstWhere(
          (g) => _asInt(g['student']) == sid,
          orElse: () => null,
        );
        final value = grade == null
            ? ''
            : '${grade['continuous_assessment'] ?? grade['score'] ?? ''}'.trim();
        final old = _scoreCtrls[sid];
        if (old != null) {
          old.text = value;
          next[sid] = old;
        } else {
          next[sid] = TextEditingController(text: value);
        }
      }
      for (final entry in _scoreCtrls.entries) {
        if (!next.containsKey(entry.key)) {
          entry.value.dispose();
        }
      }
      setState(() {
        _grades = grades;
        _scoreCtrls
          ..clear()
          ..addAll(next);
        _isLoading = false;
      });
      await _loadSubjectTotals();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStudentGrade(int studentId, {bool silent = true}) async {
    if (_savingStudentIds.contains(studentId)) return;
    if (_selectedSubjectId == null || _selectedAcademicYear == null) return;
    final ctrl = _scoreCtrls[studentId];
    if (ctrl == null) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) {
      if (!silent) {
        await _showPopup(
          title: 'Information',
          message: 'Entrez une note avant d\'enregistrer.',
          icon: Icons.info_outline,
          color: Colors.blue,
        );
      }
      return;
    }
    final value = double.tryParse(text.replaceFirst(',', '.'));
    if (value == null || value < 0 || value > 20) {
      if (!silent) {
        await _showPopup(
          title: 'Avertissement',
          message: 'La note doit être entre 0 et 20.',
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
        );
      }
      return;
    }
    setState(() => _savingStudentIds.add(studentId));
    try {
      final existing = _grades.firstWhere(
        (g) => _asInt(g['student']) == studentId,
        orElse: () => null,
      );
      dynamic saved;
      if (existing == null) {
        final created = await ApiService().post('/api/academics/grades/', data: {
          'student': studentId,
          'subject': _selectedSubjectId!,
          'academic_year': _selectedAcademicYear!,
          'term': _selectedTerm,
          'continuous_assessment': value,
        });
        saved = created.data;
      } else {
        final updated =
            await ApiService().patch('/api/academics/grades/${existing['id']}/', data: {
          'continuous_assessment': value,
        });
        saved = updated.data;
      }
      if (!mounted) return;
      if (saved is Map) {
        final sid = _asInt(saved['student']);
        if (sid != null) {
          final idx = _grades.indexWhere((g) => _asInt(g['student']) == sid);
          setState(() {
            if (idx >= 0) {
              _grades[idx] = saved;
            } else {
              _grades.add(saved);
            }
          });
        }
      }
      await _loadSubjectTotals();
      if (!mounted) return;
      if (!silent) {
        await _showPopup(
          title: 'Succès',
          message: 'Note enregistrée.',
          icon: Icons.check_circle_outline,
          color: Colors.green,
        );
      }
    } catch (e) {
      if (!mounted) return;
      await _showPopup(
        title: 'Erreur',
        message: _extractApiError(e),
        icon: Icons.error_outline,
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _savingStudentIds.remove(studentId));
      }
    }
  }

  void _scheduleAutoSave(int studentId) {
    _saveDebounceTimers[studentId]?.cancel();
    _saveDebounceTimers[studentId] = Timer(
      const Duration(milliseconds: 700),
      () => _saveStudentGrade(studentId, silent: true),
    );
  }

  void _saveOnSubmit(int studentId) {
    _saveDebounceTimers[studentId]?.cancel();
    _saveStudentGrade(studentId, silent: true);
  }

  void _focusNextStudent(List<dynamic> filteredStudents, int currentStudentId) {
    final idx = filteredStudents.indexWhere((s) => _asInt(s['id']) == currentStudentId);
    if (idx < 0 || idx + 1 >= filteredStudents.length) return;
    final nextId = _asInt(filteredStudents[idx + 1]['id']);
    if (nextId == null) return;
    final nextFocus = _scoreFocusNodes[nextId];
    if (nextFocus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        nextFocus.requestFocus();
      }
    });
  }

  String _totalLabelForStudent(int studentId) {
    final row = _subjectTotalsByStudent[studentId];
    if (row == null) return '-';
    final points = row.obtained;
    final max = row.base;
    if (max <= 0) {
      return '-';
    }
    return '${points.toStringAsFixed(1)}/${max.toStringAsFixed(1)}';
  }

  String _noteLabel() {
    return 'Note ($_selectedPeriod) /20';
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _students.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final name = _studentName(s).toLowerCase();
      final matricule = '${s['student_id'] ?? ''}'.toLowerCase();
      return name.contains(q) || matricule.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Notes'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_selectedClassId == null || _selectedSubjectId == null)
              ? Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<int>(
                              value: _selectedClassId,
                              decoration: const InputDecoration(labelText: 'Classe *'),
                              items: _classes.map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int,
                                child: Text(c['name'] ?? 'Classe'),
                              )).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedClassId = value;
                                });
                                _loadStudentsAndGrades();
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Recherche élève',
                                hintText: 'Nom, prénom, matricule',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedSemester,
                              decoration: const InputDecoration(labelText: 'Semestre'),
                              items: _semesters
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _selectedSemester = v;
                                  _selectedTerm = v == 'Premier semestre' ? 'T1' : 'T2';
                                });
                                _loadGrades();
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedPeriod,
                              decoration: const InputDecoration(labelText: 'Période'),
                              items: _periods
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedPeriod = v ?? _selectedPeriod),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedAcademicYear,
                              decoration: const InputDecoration(labelText: 'Année scolaire'),
                              items: _academicYears
                                  .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _selectedAcademicYear = v);
                                _loadGrades();
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              value: _selectedSubjectId,
                              decoration: const InputDecoration(labelText: 'Matière *'),
                              items: _subjects.map((s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text(s['name'] ?? 'Matière'),
                              )).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedSubjectId = value;
                                });
                                _loadGrades();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text('Sélectionnez la classe et la matière pour saisir les notes.'),
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Card(
                        margin: const EdgeInsets.all(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                  DropdownButtonFormField<int>(
                    value: _selectedClassId,
                    decoration: const InputDecoration(labelText: 'Classe *'),
                    items: _classes.map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'] ?? 'Classe'),
                    )).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value;
                      });
                      _loadStudentsAndGrades();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Recherche élève',
                      hintText: 'Nom, prénom, matricule',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSemester,
                    decoration: const InputDecoration(labelText: 'Semestre'),
                    items: _semesters
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedSemester = v;
                        _selectedTerm = v == 'Premier semestre' ? 'T1' : 'T2';
                      });
                      _loadGrades();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedPeriod,
                    decoration: const InputDecoration(labelText: 'Période'),
                    items: _periods
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPeriod = v ?? _selectedPeriod),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedAcademicYear,
                    decoration: const InputDecoration(labelText: 'Année scolaire'),
                    items: _academicYears
                        .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedAcademicYear = v);
                      _loadGrades();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(labelText: 'Matière *'),
                    items: _subjects.map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name'] ?? 'Matière'),
                    )).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSubjectId = value;
                      });
                      _loadGrades();
                    },
                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (filteredStudents.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('Aucun élève')),
                      )
                    else
                      SliverList.builder(
                        itemCount: filteredStudents.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Row(
                                children: [
                                  const Expanded(
                                    flex: 6,
                                    child: Text(
                                      'ÉLÈVE',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      _noteLabel().toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ),
                                  const Expanded(
                                    flex: 4,
                                    child: Text(
                                      'TOTAL',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final student = filteredStudents[index - 1];
                          final studentId = _asInt(student['id']);
                          if (studentId == null) return const SizedBox.shrink();
                          final ctrl = _scoreCtrls[studentId] ?? TextEditingController();
                          _scoreCtrls[studentId] = ctrl;
                          final focusNode =
                              _scoreFocusNodes.putIfAbsent(studentId, FocusNode.new);
                          final isSaving = _savingStudentIds.contains(studentId);
                          return Card(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _studentName(student),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        if ('${student['student_id'] ?? ''}'.isNotEmpty)
                                          Text(
                                            '${student['student_id']}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 5,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: ctrl,
                                            focusNode: focusNode,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              hintText: '/20',
                                            ),
                                            onChanged: (_) => _scheduleAutoSave(studentId),
                                            onSubmitted: (_) {
                                              _saveOnSubmit(studentId);
                                              _focusNextStudent(
                                                filteredStudents,
                                                studentId,
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        if (isSaving)
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else
                                          const Icon(Icons.check_circle_outline, size: 18),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      _totalLabelForStudent(studentId),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
    );
  }
}
