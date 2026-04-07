import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';

/// Création ou édition d'un cours e-learning (parcours enseignant, sans sélection d'un autre enseignant).
class TeacherCourseFormPage extends ConsumerStatefulWidget {
  final int? courseId;

  const TeacherCourseFormPage({super.key, this.courseId});

  @override
  ConsumerState<TeacherCourseFormPage> createState() =>
      _TeacherCourseFormPageState();
}

class _TeacherCourseFormPageState extends ConsumerState<TeacherCourseFormPage> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _academicYearCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _contentUrlCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();

  List<dynamic> _classes = [];
  int? _selectedClassId;
  bool _isPublished = false;
  bool _loadingMeta = true;
  bool _loadingCourse = false;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.courseId != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadClasses();
    if (widget.courseId != null) {
      await _loadCourse(widget.courseId!);
    } else if (mounted) {
      setState(() => _loadingMeta = false);
    }
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    return [];
  }

  Future<void> _loadClasses() async {
    try {
      final res = await ApiService().get('/api/schools/classes/');
      if (!mounted) return;
      setState(() {
        _classes = _extractList(res.data);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger les classes.';
        });
      }
    }
  }

  Future<void> _loadCourse(int id) async {
    setState(() {
      _loadingCourse = true;
      _loadingMeta = true;
    });
    try {
      final res = await ApiService().get('/api/elearning/courses/$id/');
      final c = res.data as Map<String, dynamic>;
      if (!mounted) return;
      _titleCtrl.text = '${c['title'] ?? ''}';
      _descriptionCtrl.text = '${c['description'] ?? ''}';
      _academicYearCtrl.text = '${c['academic_year'] ?? ''}';
      _contentCtrl.text = '${c['content'] ?? ''}';
      _contentUrlCtrl.text = '${c['content_url'] ?? ''}';
      _videoUrlCtrl.text = '${c['video_url'] ?? ''}';
      _isPublished = c['is_published'] == true;
      final rawClass = c['school_class'];
      _selectedClassId =
          rawClass is int ? rawClass : int.tryParse('$rawClass');
      setState(() {
        _loadingCourse = false;
        _loadingMeta = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCourse = false;
          _loadingMeta = false;
          _error = 'Cours introuvable ou accès refusé.';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _descriptionCtrl.text.trim().isEmpty ||
        _selectedClassId == null ||
        _academicYearCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez compléter les champs obligatoires.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final payload = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'school_class': _selectedClassId,
      'academic_year': _academicYearCtrl.text.trim(),
      'content': _contentCtrl.text.trim(),
      'content_url': _contentUrlCtrl.text.trim().isEmpty
          ? null
          : _contentUrlCtrl.text.trim(),
      'video_url': _videoUrlCtrl.text.trim().isEmpty
          ? null
          : _videoUrlCtrl.text.trim(),
      'is_published': _isPublished,
    };

    try {
      if (_isEditing) {
        await ApiService().patch(
          '/api/elearning/courses/${widget.courseId}/',
          data: payload,
        );
      } else {
        await ApiService().post('/api/elearning/courses/', data: payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Cours modifié.' : 'Cours créé.',
          ),
        ),
      );
      context.pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enregistrement impossible. Vérifiez les champs.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _academicYearCtrl.dispose();
    _contentCtrl.dispose();
    _contentUrlCtrl.dispose();
    _videoUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier le cours' : 'Nouveau cours'),
      ),
      body: _loadingMeta || _loadingCourse
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _classes.isEmpty && !_isEditing
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _bootstrap();
                          },
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(labelText: 'Titre *'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('class_$_selectedClassId'),
                        initialValue: _selectedClassId,
                        decoration: const InputDecoration(labelText: 'Classe *'),
                        items: _classes
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item['id'] as int?,
                                child: Text('${item['name'] ?? 'Classe'}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedClassId = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _academicYearCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Année scolaire *',
                          hintText: '2025-2026',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _videoUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'URL vidéo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contentUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'URL contenu',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contentCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Contenu (optionnel)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Publié'),
                        value: _isPublished,
                        onChanged: (v) => setState(() => _isPublished = v),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: Text(
                          _submitting
                              ? 'Enregistrement...'
                              : (_isEditing ? 'Enregistrer' : 'Créer'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
