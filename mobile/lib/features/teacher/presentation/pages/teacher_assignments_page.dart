import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';

class TeacherAssignmentsPage extends ConsumerStatefulWidget {
  const TeacherAssignmentsPage({super.key});

  @override
  ConsumerState<TeacherAssignmentsPage> createState() =>
      _TeacherAssignmentsPageState();
}

class _TeacherAssignmentsPageState
    extends ConsumerState<TeacherAssignmentsPage> {
  List<dynamic> _assignments = [];
  List<dynamic> _filteredAssignments = [];
  List<dynamic> _subjects = [];
  List<dynamic> _classes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _subjectFilterId;
  int? _classFilterId;
  String _statusFilter = 'ALL';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) {
      return data;
    }
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    return [];
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        ApiService().get('/api/elearning/assignments/'),
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/schools/classes/'),
      ]);
      setState(() {
        _assignments = _extractList(responses[0].data);
        _subjects = _extractList(responses[1].data);
        _classes = _extractList(responses[2].data);
        _errorMessage = null;
        _applyFilters();
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Impossible de charger les devoirs.';
        _isLoading = false;
      });
    }
  }

  String _className(Map<String, dynamic> assignment) {
    final direct = assignment['class_name'];
    if (direct != null && '$direct'.trim().isNotEmpty) {
      return '$direct';
    }
    final schoolClass = assignment['school_class'];
    if (schoolClass is Map && schoolClass['name'] != null) {
      return '${schoolClass['name']}';
    }
    return 'N/A';
  }

  String _subjectName(Map<String, dynamic> assignment) {
    final direct = assignment['subject_name'];
    if (direct != null && '$direct'.trim().isNotEmpty) {
      return '$direct';
    }
    final subject = assignment['subject'];
    if (subject is Map && subject['name'] != null) {
      return '${subject['name']}';
    }
    return 'N/A';
  }

  int? _schoolClassId(Map<String, dynamic> assignment) {
    final schoolClass = assignment['school_class'];
    if (schoolClass is int) {
      return schoolClass;
    }
    if (schoolClass is Map && schoolClass['id'] is int) {
      return schoolClass['id'] as int;
    }
    return int.tryParse('$schoolClass');
  }

  int? _subjectId(Map<String, dynamic> assignment) {
    final subject = assignment['subject'];
    if (subject is int) {
      return subject;
    }
    if (subject is Map && subject['id'] is int) {
      return subject['id'] as int;
    }
    return int.tryParse('$subject');
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _assignments.where((item) {
      final assignment = Map<String, dynamic>.from(item as Map);
      if (q.isNotEmpty) {
        final title = (assignment['title'] ?? '').toString().toLowerCase();
        final desc = (assignment['description'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !desc.contains(q)) {
          return false;
        }
      }
      if (_subjectFilterId != null &&
          _subjectId(assignment) != _subjectFilterId) {
        return false;
      }
      if (_classFilterId != null &&
          _schoolClassId(assignment) != _classFilterId) {
        return false;
      }
      if (_statusFilter == 'PUBLISHED' && assignment['is_published'] != true) {
        return false;
      }
      if (_statusFilter == 'DRAFT' && assignment['is_published'] == true) {
        return false;
      }
      return true;
    }).toList();

    setState(() {
      _filteredAssignments = filtered;
    });
  }

  Future<void> _togglePublished(Map<String, dynamic> assignment) async {
    final id = assignment['id'];
    if (id == null) {
      return;
    }
    final isPublished = assignment['is_published'] == true;
    try {
      await ApiService().patch(
        '/api/elearning/assignments/$id/',
        data: {'is_published': !isPublished},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              !isPublished ? 'Devoir publié.' : 'Devoir passé en brouillon.'),
        ),
      );
      await _loadData();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de mise à jour du statut.')),
      );
    }
  }

  Future<void> _openAssignmentForm({Map<String, dynamic>? assignment}) async {
    final isEditing = assignment != null;
    final titleCtrl =
        TextEditingController(text: '${assignment?['title'] ?? ''}');
    final descriptionCtrl =
        TextEditingController(text: '${assignment?['description'] ?? ''}');
    final yearCtrl = TextEditingController(
      text:
          '${assignment?['academic_year'] ?? '${DateTime.now().year}-${DateTime.now().year + 1}'}',
    );
    final pointsCtrl = TextEditingController(
      text: '${assignment?['total_points'] ?? '20'}',
    );

    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    if (assignment?['due_date'] != null) {
      dueDate = DateTime.tryParse('${assignment!['due_date']}') ?? dueDate;
    }

    int? subjectId = _subjectId(assignment ?? {});
    int? classId = _schoolClassId(assignment ?? {});
    bool isPublished = assignment?['is_published'] == true;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'Modifier le devoir' : 'Nouveau devoir',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Titre *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('subject_$subjectId'),
                  initialValue: subjectId,
                  decoration: const InputDecoration(labelText: 'Matière *'),
                  items: _subjects
                      .map((s) => DropdownMenuItem<int>(
                            value: s['id'] as int?,
                            child: Text('${s['name'] ?? 'Matière'}'),
                          ))
                      .toList(),
                  onChanged: (v) => setLocalState(() => subjectId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('class_$classId'),
                  initialValue: classId,
                  decoration: const InputDecoration(labelText: 'Classe *'),
                  items: _classes
                      .map((c) => DropdownMenuItem<int>(
                            value: c['id'] as int?,
                            child: Text('${c['name'] ?? 'Classe'}'),
                          ))
                      .toList(),
                  onChanged: (v) => setLocalState(() => classId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Année scolaire *',
                    hintText: '2025-2026',
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: ctx,
                      initialDate: dueDate,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (pickedDate == null || !ctx.mounted) {
                      return;
                    }
                    final pickedTime = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(dueDate),
                    );
                    if (pickedTime == null) {
                      return;
                    }
                    setLocalState(() {
                      dueDate = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  },
                  child: InputDecorator(
                    decoration:
                        const InputDecoration(labelText: 'Date limite *'),
                    child: Text(
                      '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year} ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Points totaux'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPublished,
                  onChanged: (v) => setLocalState(() => isPublished = v),
                  title: const Text('Publier'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            isSubmitting ? null : () => Navigator.of(ctx).pop(),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (titleCtrl.text.trim().isEmpty ||
                                    descriptionCtrl.text.trim().isEmpty ||
                                    subjectId == null ||
                                    classId == null ||
                                    yearCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Champs obligatoires manquants.')),
                                  );
                                  return;
                                }
                                final points =
                                    double.tryParse(pointsCtrl.text.trim()) ??
                                        20.0;
                                final payload = <String, dynamic>{
                                  'title': titleCtrl.text.trim(),
                                  'description': descriptionCtrl.text.trim(),
                                  'subject': subjectId,
                                  'school_class': classId,
                                  'academic_year': yearCtrl.text.trim(),
                                  'due_date': dueDate.toIso8601String(),
                                  'total_points': points,
                                  'is_published': isPublished,
                                };
                                setLocalState(() => isSubmitting = true);
                                try {
                                  if (isEditing) {
                                    await ApiService().patch(
                                      '/api/elearning/assignments/${assignment['id']}/',
                                      data: payload,
                                    );
                                  } else {
                                    await ApiService().post(
                                        '/api/elearning/assignments/',
                                        data: payload);
                                  }
                                  if (!ctx.mounted) {
                                    return;
                                  }
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isEditing
                                            ? 'Devoir modifié avec succès.'
                                            : 'Devoir créé avec succès.',
                                      ),
                                    ),
                                  );
                                  await _loadData();
                                } catch (_) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Impossible d’enregistrer le devoir.')),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setLocalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: Text(
                          isSubmitting
                              ? 'Enregistrement...'
                              : (isEditing ? 'Enregistrer' : 'Créer'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    yearCtrl.dispose();
    pointsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final publishedCount =
        _assignments.where((a) => a['is_published'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devoirs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openAssignmentForm(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un devoir...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: _statusFilter == 'ALL',
                  onSelected: (_) {
                    _statusFilter = 'ALL';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Publiés'),
                  selected: _statusFilter == 'PUBLISHED',
                  onSelected: (_) {
                    _statusFilter = 'PUBLISHED';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Brouillons'),
                  selected: _statusFilter == 'DRAFT',
                  onSelected: (_) {
                    _statusFilter = 'DRAFT';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 16),
                DropdownButton<int?>(
                  value: _subjectFilterId,
                  hint: const Text('Toutes matières'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Toutes matières')),
                    ..._subjects.map(
                      (s) => DropdownMenuItem<int?>(
                        value: s['id'] as int?,
                        child: Text('${s['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    _subjectFilterId = v;
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<int?>(
                  value: _classFilterId,
                  hint: const Text('Toutes classes'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Toutes classes')),
                    ..._classes.map(
                      (c) => DropdownMenuItem<int?>(
                        value: c['id'] as int?,
                        child: Text('${c['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    _classFilterId = v;
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('Total'),
                          const SizedBox(height: 4),
                          Text('${_assignments.length}',
                              style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('Publiés'),
                          const SizedBox(height: 4),
                          Text('$publishedCount',
                              style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_errorMessage!),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _loadData,
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredAssignments.isEmpty
              ? const Center(child: Text('Aucun devoir'))
              : RefreshIndicator(
                            onRefresh: _loadData,
                  child: ListView.builder(
                              itemCount: _filteredAssignments.length,
                    itemBuilder: (context, index) {
                                final assignment = Map<String, dynamic>.from(
                                    _filteredAssignments[index] as Map);
                      return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.assignment),
                                    title:
                                        Text(assignment['title'] ?? 'Devoir'),
                                    subtitle: Text(
                                      'Classe: ${_className(assignment)}\n'
                                      'Matière: ${_subjectName(assignment)}\n'
                                      'Statut: ${assignment['is_published'] == true ? 'Publié' : 'Brouillon'}',
                                    ),
                                    isThreeLine: true,
                          onTap: () {
                                      final id = assignment['id'];
                                      if (id == null) {
                                        return;
                                      }
                                      context.push('/teacher/assignments/$id');
                                    },
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          await _openAssignmentForm(
                                              assignment: assignment);
                                        } else if (value == 'publish') {
                                          await _togglePublished(assignment);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Modifier'),
                                        ),
                                        PopupMenuItem(
                                          value: 'publish',
                                          child: Text(
                                            assignment['is_published'] == true
                                                ? 'Passer en brouillon'
                                                : 'Publier',
                                          ),
                                        ),
                                      ],
                                    ),
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
