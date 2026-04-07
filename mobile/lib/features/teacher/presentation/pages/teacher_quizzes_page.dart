import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class TeacherQuizzesPage extends ConsumerStatefulWidget {
  const TeacherQuizzesPage({super.key});

  @override
  ConsumerState<TeacherQuizzesPage> createState() => _TeacherQuizzesPageState();
}

class _TeacherQuizzesPageState extends ConsumerState<TeacherQuizzesPage> {
  List<dynamic> _quizzes = [];
  List<dynamic> _filteredQuizzes = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedSubject;
  String? _selectedClass;
  String _statusFilter = 'ALL';
  String _sortBy = 'date_desc';
  List<dynamic> _subjects = [];
  List<dynamic> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final [quizzesRes, subjectsRes, classesRes] = await Future.wait([
        ApiService().get('/api/elearning/quizzes/'),
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/schools/classes/'),
      ]);

      setState(() {
        _quizzes = quizzesRes.data is List
            ? quizzesRes.data
            : (quizzesRes.data['results'] ?? []);
        _subjects = subjectsRes.data is List
            ? subjectsRes.data
            : (subjectsRes.data['results'] ?? []);
        _classes = classesRes.data is List
            ? classesRes.data
            : (classesRes.data['results'] ?? []);
        _applyFilters();
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Impossible de charger les quiz.';
        _isLoading = false;
      });
    }
  }

  static int? _relationId(dynamic field) {
    if (field == null) return null;
    if (field is int) return field;
    if (field is num) return field.toInt();
    if (field is Map) {
      final id = field['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
      return int.tryParse('$id');
    }
    return int.tryParse('$field');
  }

  String _quizSubjectLabel(dynamic quiz) {
    final sub = quiz['subject'];
    if (sub is Map) return '${sub['name'] ?? 'N/A'}';
    final id = _relationId(sub);
    if (id != null) {
      for (final s in _subjects) {
        if (s is Map && _relationId(s['id']) == id) {
          return '${s['name'] ?? 'N/A'}';
        }
      }
      return 'Matière #$id';
    }
    return 'N/A';
  }

  String _quizClassLabel(dynamic quiz) {
    final sc = quiz['school_class'];
    if (sc is Map) return '${sc['name'] ?? 'N/A'}';
    final id = _relationId(sc);
    if (id != null) {
      for (final c in _classes) {
        if (c is Map && _relationId(c['id']) == id) {
          return '${c['name'] ?? 'N/A'}';
        }
      }
      return 'Classe #$id';
    }
    return 'N/A';
  }

  void _applyFilters() {
    final filtered = _quizzes.where((quiz) {
      if (_searchQuery.isNotEmpty) {
        final title = (quiz['title'] ?? '').toString().toLowerCase();
        if (!title.contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_selectedSubject != null) {
        if (_relationId(quiz['subject']) != int.parse(_selectedSubject!)) {
          return false;
        }
      }
      if (_selectedClass != null) {
        if (_relationId(quiz['school_class']) != int.parse(_selectedClass!)) {
          return false;
        }
      }
      if (_statusFilter == 'PUBLISHED' && quiz['is_published'] != true) {
        return false;
      }
      if (_statusFilter == 'DRAFT' && quiz['is_published'] == true) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sortBy == 'title') {
        return (a['title'] ?? '')
            .toString()
            .compareTo((b['title'] ?? '').toString());
      }
      final ad =
          DateTime.tryParse('${a['start_date'] ?? a['created_at'] ?? ''}') ??
              DateTime(1970);
      final bd =
          DateTime.tryParse('${b['start_date'] ?? b['created_at'] ?? ''}') ??
              DateTime(1970);
      return _sortBy == 'date_asc' ? ad.compareTo(bd) : bd.compareTo(ad);
    });

    setState(() => _filteredQuizzes = filtered);
  }

  Future<void> _togglePublished(Map<String, dynamic> quiz) async {
    final id = quiz['id'];
    if (id == null) return;
    final isPublished = quiz['is_published'] == true;
    try {
      await ApiService().patch(
        '/api/elearning/quizzes/$id/',
        data: {'is_published': !isPublished},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(!isPublished ? 'Quiz publié.' : 'Quiz en brouillon.')),
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de mise à jour du statut.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz & Examens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              context.push('/teacher/quizzes/create');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                const SizedBox(width: 14),
                DropdownButton<String>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(
                        value: 'date_desc', child: Text('Date (récent)')),
                    DropdownMenuItem(
                        value: 'date_asc', child: Text('Date (ancien)')),
                    DropdownMenuItem(value: 'title', child: Text('Titre')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    _sortBy = v;
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          SearchFilterBar(
            hintText: 'Rechercher un quiz...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'subject',
                label: 'Matière',
                values: _subjects
                    .map((s) => FilterValue(
                          value: s['id'].toString(),
                          label: s['name'] ?? 'Matière',
                        ))
                    .toList(),
                selectedValue: _selectedSubject,
              ),
              FilterOption(
                key: 'class',
                label: 'Classe',
                values: _classes
                    .map((c) => FilterValue(
                          value: c['id'].toString(),
                          label: c['name'] ?? 'Classe',
                        ))
                    .toList(),
                selectedValue: _selectedClass,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() {
                _selectedSubject = filters['subject'];
                _selectedClass = filters['class'];
              });
              _applyFilters();
            },
            showSort: true,
            sortOptions: [
              SortOption(value: 'date_desc', label: 'Date (récent)'),
              SortOption(value: 'date_asc', label: 'Date (ancien)'),
              SortOption(value: 'title', label: 'Titre'),
            ],
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
                    : _filteredQuizzes.isEmpty
                        ? const Center(child: Text('Aucun quiz'))
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              itemCount: _filteredQuizzes.length,
                              itemBuilder: (context, index) {
                                final quiz = _filteredQuizzes[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: ListTile(
                                    leading: const Icon(Icons.quiz),
                                    title: Text(quiz['title'] ?? 'Quiz'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Classe: ${_quizClassLabel(quiz)}'),
                                        Text('Matière: ${_quizSubjectLabel(quiz)}'),
                                        Text(
                                          'Statut: ${quiz['is_published'] == true ? 'Publié' : 'Brouillon'}',
                                        ),
                                        if (quiz['time_limit'] != null)
                                          Text(
                                              'Durée: ${quiz['time_limit']} min'),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'detail') {
                                          context.push(
                                              '/teacher/quizzes/${quiz['id']}');
                                        } else if (value == 'publish') {
                                          await _togglePublished(
                                              Map<String, dynamic>.from(
                                                  quiz as Map));
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'detail',
                                          child: Text('Ouvrir détails'),
                                        ),
                                        PopupMenuItem(
                                          value: 'publish',
                                          child: Text(
                                            quiz['is_published'] == true
                                                ? 'Passer en brouillon'
                                                : 'Publier',
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      final id = quiz['id'];
                                      if (id == null) {
                                        return;
                                      }
                                      context.push('/teacher/quizzes/$id');
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
