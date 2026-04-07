import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class AdminElearningPage extends ConsumerStatefulWidget {
  const AdminElearningPage({super.key});

  @override
  ConsumerState<AdminElearningPage> createState() => _AdminElearningPageState();
}

class _AdminElearningPageState extends ConsumerState<AdminElearningPage> {
  List<dynamic> _courses = [];
  List<dynamic> _filteredCourses = [];
  List<dynamic> _classes = [];
  List<dynamic> _teachers = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _statusFilter = 'ALL';
  int? _classFilterId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadCourses(), _loadMetadata()]);
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

  Future<void> _loadMetadata() async {
    try {
      final classesRes = await ApiService().get('/api/schools/classes/');
      final teachersRes = await ApiService().get('/api/auth/teachers/');
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = _extractList(classesRes.data);
        _teachers = _extractList(teachersRes.data);
      });
    } catch (_) {
      // Métadonnées facultatives: on garde l'écran utilisable même si une API échoue.
    }
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/elearning/courses/');
      final courses = _extractList(response.data);

      setState(() {
        _courses = courses;
        _errorMessage = null;
        _applyFilters();
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Impossible de charger les cours.';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _courses.where((course) {
      if (q.isNotEmpty) {
        final title = (course['title'] ?? '').toString().toLowerCase();
        final description =
            (course['description'] ?? '').toString().toLowerCase();
        final teacher = (course['teacher_name'] ?? '').toString().toLowerCase();
        if (!title.contains(q) &&
            !description.contains(q) &&
            !teacher.contains(q)) {
          return false;
        }
      }

      if (_statusFilter == 'PUBLISHED' && course['is_published'] != true) {
        return false;
      }
      if (_statusFilter == 'DRAFT' && course['is_published'] == true) {
        return false;
      }

      if (_classFilterId != null) {
        final classId = course['school_class'] is int
            ? course['school_class'] as int
            : int.tryParse('${course['school_class']}');
        if (classId != _classFilterId) {
          return false;
        }
      }
      return true;
    }).toList();

    setState(() {
      _filteredCourses = filtered;
    });
  }

  String _schoolClassLabel(dynamic course) {
    final direct = course['class_name'] ?? course['school_class_name'];
    if (direct != null && '$direct'.trim().isNotEmpty) {
      return '$direct';
    }
    final schoolClass = course['school_class'];
    if (schoolClass is Map && schoolClass['name'] != null) {
      return '${schoolClass['name']}';
    }
    return 'Classe non définie';
  }

  Future<void> _togglePublished(Map<String, dynamic> course) async {
    final id = course['id'];
    if (id == null) {
      return;
    }
    final current = course['is_published'] == true;
    try {
      await ApiService().patch(
        '/api/elearning/courses/$id/',
        data: {'is_published': !current},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(!current ? 'Cours publié.' : 'Cours passé en brouillon.')),
      );
      await _loadCourses();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de mise à jour du statut.')),
      );
    }
  }

  Future<void> _openCourseContent(Map<String, dynamic> course) async {
    final contentUrl = (course['content_url'] ?? '').toString().trim();
    final attachments = (course['attachments'] ?? '').toString().trim();
    final videoUrl = (course['video_url'] ?? '').toString().trim();

    String? url;
    if (contentUrl.isNotEmpty) {
      url = contentUrl;
    } else if (attachments.isNotEmpty) {
      if (attachments.startsWith('http://') ||
          attachments.startsWith('https://')) {
        url = attachments;
      } else {
        url = '${ApiService().baseUrl}$attachments';
      }
    } else if (videoUrl.isNotEmpty) {
      url = videoUrl;
    }

    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun contenu à ouvrir pour ce cours.')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien invalide.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien.')),
      );
    }
  }

  Future<void> _openCourseForm({Map<String, dynamic>? course}) async {
    final user = ref.read(authProvider).user;
    final isAdmin = user?.role == 'ADMIN';
    final isEditing = course != null;

    final titleCtrl = TextEditingController(text: '${course?['title'] ?? ''}');
    final descriptionCtrl =
        TextEditingController(text: '${course?['description'] ?? ''}');
    final academicYearCtrl =
        TextEditingController(text: '${course?['academic_year'] ?? ''}');
    final contentCtrl =
        TextEditingController(text: '${course?['content'] ?? ''}');
    final contentUrlCtrl =
        TextEditingController(text: '${course?['content_url'] ?? ''}');
    final videoUrlCtrl =
        TextEditingController(text: '${course?['video_url'] ?? ''}');

    final rawClassId = course?['school_class'];
    final rawTeacherId = course?['teacher'];
    int? selectedClassId =
        rawClassId is int ? rawClassId : int.tryParse('$rawClassId');
    int? selectedTeacherId =
        rawTeacherId is int ? rawTeacherId : int.tryParse('$rawTeacherId');
    bool isPublished = course?['is_published'] == true;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return Padding(
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
                      isEditing ? 'Modifier le cours' : 'Nouveau cours',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Titre *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          const InputDecoration(labelText: 'Description *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('class_$selectedClassId'),
                      initialValue: selectedClassId,
                      decoration: const InputDecoration(labelText: 'Classe *'),
                      items: _classes
                          .map((item) => DropdownMenuItem<int>(
                                value: item['id'] as int?,
                                child: Text('${item['name'] ?? 'Classe'}'),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setLocalState(() => selectedClassId = value),
                    ),
                    const SizedBox(height: 12),
                    if (isAdmin) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey('teacher_$selectedTeacherId'),
                        initialValue: selectedTeacherId,
                        decoration:
                            const InputDecoration(labelText: 'Enseignant'),
                        items: _teachers
                            .map((item) => DropdownMenuItem<int>(
                                  value: item['id'] as int?,
                                  child: Text(
                                    '${item['user']?['first_name'] ?? ''} ${item['user']?['last_name'] ?? ''}'
                                        .trim(),
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setLocalState(() => selectedTeacherId = value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: academicYearCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Année scolaire *',
                        hintText: '2025-2026',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: videoUrlCtrl,
                      decoration: const InputDecoration(labelText: 'URL vidéo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentUrlCtrl,
                      decoration:
                          const InputDecoration(labelText: 'URL contenu'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                          labelText: 'Contenu (optionnel)'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Publié'),
                      value: isPublished,
                      onChanged: (value) =>
                          setLocalState(() => isPublished = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(ctx).pop(),
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
                                        selectedClassId == null ||
                                        academicYearCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Veuillez compléter les champs obligatoires.'),
                                        ),
                                      );
                                      return;
                                    }

                                    setLocalState(() => isSubmitting = true);

                                    final payload = <String, dynamic>{
                                      'title': titleCtrl.text.trim(),
                                      'description':
                                          descriptionCtrl.text.trim(),
                                      'school_class': selectedClassId,
                                      'academic_year':
                                          academicYearCtrl.text.trim(),
                                      'content': contentCtrl.text.trim(),
                                      'content_url':
                                          contentUrlCtrl.text.trim().isEmpty
                                              ? null
                                              : contentUrlCtrl.text.trim(),
                                      'video_url':
                                          videoUrlCtrl.text.trim().isEmpty
                                              ? null
                                              : videoUrlCtrl.text.trim(),
                                      'is_published': isPublished,
                                    };
                                    if (isAdmin && selectedTeacherId != null) {
                                      payload['teacher'] = selectedTeacherId;
                                    }

                                    try {
                                      if (isEditing) {
                                        await ApiService().patch(
                                          '/api/elearning/courses/${course['id']}/',
                                          data: payload,
                                        );
                                      } else {
                                        await ApiService().post(
                                          '/api/elearning/courses/',
                                          data: payload,
                                        );
                                      }
                                      if (!mounted) {
                                        return;
                                      }
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(isEditing
                                              ? 'Cours modifié avec succès.'
                                              : 'Cours créé avec succès.'),
                                        ),
                                      );
                                      await _loadCourses();
                                    } catch (_) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Enregistrement impossible. Vérifiez les champs.')),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setLocalState(
                                            () => isSubmitting = false);
                                      }
                                    }
                                  },
                            child: Text(isSubmitting
                                ? 'Enregistrement...'
                                : (isEditing ? 'Enregistrer' : 'Créer')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    academicYearCtrl.dispose();
    contentCtrl.dispose();
    contentUrlCtrl.dispose();
    videoUrlCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final publishedCount =
        _courses.where((item) => item['is_published'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-learning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openCourseForm(),
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un cours...',
            onSearchChanged: (value) {
              _searchQuery = value;
              _applyFilters();
            },
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
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
                  value: _classFilterId,
                  hint: const Text('Toutes les classes'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Toutes les classes')),
                    ..._classes.map(
                      (item) => DropdownMenuItem<int?>(
                        value: item['id'] as int?,
                        child: Text('${item['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _classFilterId = value;
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
                          Text(
                            '${_courses.length}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
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
                          Text(
                            '$publishedCount',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
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
                                onPressed: _loadCourses,
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredCourses.isEmpty
                        ? const Center(child: Text('Aucun cours trouvé'))
                        : RefreshIndicator(
                            onRefresh: _loadCourses,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredCourses.length,
                              itemBuilder: (context, index) {
                                final course = Map<String, dynamic>.from(
                                  _filteredCourses[index] as Map,
                                );

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor:
                                          AppTheme.avatarBackgroundColor,
                                      foregroundColor:
                                          AppTheme.onAvatarBackgroundColor,
                                      child: Icon(Icons.book),
                                    ),
                                    title: Text(course['title'] ?? 'Cours'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (course['description'] != null)
                                          Text(
                                            course['description'],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        Text(
                                            'Classe: ${_schoolClassLabel(course)}'),
                                        Text(
                                          course['is_published'] == true
                                              ? 'Statut: Publié'
                                              : 'Statut: Brouillon',
                                        ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          await _openCourseForm(course: course);
                                        } else if (value == 'content') {
                                          await _openCourseContent(course);
                                        } else if (value == 'publish') {
                                          await _togglePublished(course);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Modifier'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'content',
                                          child: Text('Lire le contenu'),
                                        ),
                                        PopupMenuItem(
                                          value: 'publish',
                                          child: Text(
                                            course['is_published'] == true
                                                ? 'Passer en brouillon'
                                                : 'Publier',
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      final role =
                                          ref.read(authProvider).user?.role;
                                      final path = role == 'TEACHER'
                                          ? '/teacher/courses/${course['id']}'
                                          : '/courses/${course['id']}';
                                      context.push(path);
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
