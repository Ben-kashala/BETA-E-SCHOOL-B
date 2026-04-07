import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

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

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    return [];
  }

  Future<void> _reloadSubjectsOnly() async {
    try {
      final subjectsRes = await ApiService().get('/api/schools/subjects/');
      if (!mounted) return;
      setState(() {
        _allSubjects = _extractList(subjectsRes.data);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de recharger la liste des matières.')),
        );
      }
    }
  }

  /// Code court pour l'API (unique par école), dérivé du nom si besoin.
  static String suggestSubjectCode(String name) {
    var s = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty) {
      return 'MAT_${DateTime.now().millisecondsSinceEpoch % 100000}';
    }
    return s.length > 20 ? s.substring(0, 20) : s;
  }

  Future<int?> _showCreateSubjectDialog() {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => _CreateSubjectDialog(
        suggestCode: suggestSubjectCode,
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final [classesRes, subjectsRes, teachersRes] = await Future.wait([
        ApiService().get('/api/schools/classes/my_titular/'),
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/accounts/teachers/', queryParameters: {'page_size': '200'}),
      ]);

      final classes = _extractList(classesRes.data);
      
      int? classToSelect = widget.initialClassId;
      final classIds = classes.map((c) => c['id'] as int?).toSet();
      if (classToSelect == null || !classIds.contains(classToSelect)) {
        classToSelect = classes.isNotEmpty ? classes.first['id'] as int? : null;
      }
      setState(() {
        _classes = classes;
        _allSubjects = _extractList(subjectsRes.data);
        _teachers = _extractList(teachersRes.data);
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

  /// L'API peut renvoyer `subject` / `teacher` comme ID (int) ou comme objet.
  static int? _asIntId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is Map) {
      final id = v['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
      return int.tryParse('$id');
    }
    return int.tryParse('$v');
  }

  String _subjectLabel(dynamic subjectField) {
    if (subjectField is Map) {
      return '${subjectField['name'] ?? 'Matière'}';
    }
    final id = _asIntId(subjectField);
    if (id != null) {
      for (final s in _allSubjects) {
        if (s is Map && _asIntId(s['id']) == id) {
          return '${s['name'] ?? 'Matière'}';
        }
      }
      return 'Matière #$id';
    }
    return 'Matière';
  }

  int? _teacherIdField(dynamic teacherField) => _asIntId(teacherField);

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey(_allSubjects.length),
                  decoration: const InputDecoration(labelText: 'Matière *'),
                  items: _allSubjects.where((s) {
                    final sid = _asIntId(s['id']);
                    final assignedIds = _classSubjects
                        .map((cs) => _asIntId(cs['subject']))
                        .whereType<int>()
                        .toSet();
                    return sid != null && !assignedIds.contains(sid);
                  }).map((s) {
                    return DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(s['name'] ?? 'Matière'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedSubjectId = value),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Créer une matière'),
                  onPressed: () async {
                    final newId = await _showCreateSubjectDialog();
                    if (!context.mounted) return;
                    if (newId != null) {
                      await _reloadSubjectsOnly();
                      setDialogState(() => selectedSubjectId = newId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Matière créée. Sélectionnez « Ajouter » pour l\'associer à la classe.',
                            ),
                          ),
                        );
                      }
                    }
                  },
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
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            title: Text(_subjectLabel(cs['subject'])),
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
                                          value: _teacherIdField(cs['teacher']),
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

class _CreateSubjectDialog extends StatefulWidget {
  const _CreateSubjectDialog({required this.suggestCode});

  final String Function(String name) suggestCode;

  @override
  State<_CreateSubjectDialog> createState() => _CreateSubjectDialogState();
}

class _CreateSubjectDialogState extends State<_CreateSubjectDialog> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _periodMax = 20;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorText = null);
    final name = _nameCtrl.text.trim();
    var code = _codeCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Le nom de la matière est obligatoire.');
      return;
    }
    if (code.isEmpty) {
      code = widget.suggestCode(name);
      _codeCtrl.text = code;
    }

    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
        '/api/schools/subjects/',
        data: {
          'name': name,
          'code': code,
          'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'period_max': _periodMax,
          'is_active': true,
        },
      );
      if (!mounted) return;
      final rawId = res.data is Map ? res.data['id'] : null;
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      setState(() => _errorText = 'Création impossible : ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer une matière'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom de la matière *',
                hintText: 'ex. Physique',
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_codeCtrl.text.isEmpty) {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code *',
                hintText: 'ex. PHYS (unique dans l\'école)',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  _codeCtrl.text = widget.suggestCode(_nameCtrl.text);
                  setState(() {});
                },
                child: const Text('Générer le code à partir du nom'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Note max par période',
              ),
              initialValue: _periodMax,
              items: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _periodMax = v ?? 20),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}
