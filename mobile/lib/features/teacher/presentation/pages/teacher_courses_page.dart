import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class TeacherCoursesPage extends ConsumerStatefulWidget {
  const TeacherCoursesPage({super.key});

  @override
  ConsumerState<TeacherCoursesPage> createState() => _TeacherCoursesPageState();
}

class _TeacherCoursesPageState extends ConsumerState<TeacherCoursesPage> {
  List<dynamic> _courses = [];
  List<dynamic> _filteredCourses = [];
  bool _isLoading = true;
  String? _loadError;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ApiService().get(
        '/api/elearning/courses/',
        useCache: false,
      );
      final raw = response.data;
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['results'] ?? []) : <dynamic>[]);
      setState(() {
        _courses = List<dynamic>.from(list);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadError =
            'Impossible de charger les cours. Vérifiez la connexion et réessayez.';
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredCourses = _courses.where((course) {
        if (_searchQuery.isNotEmpty) {
          final title = (course['title'] ?? '').toString().toLowerCase();
          return title.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  /// `school_class` peut être un objet `{name}` ou un ID entier renvoyé par l'API.
  String _schoolClassLabel(dynamic course) {
    final sc = course is Map ? course['school_class'] : null;
    if (sc is Map) {
      final n = sc['name'] ?? sc['class_name'];
      if (n != null && '$n'.trim().isNotEmpty) return '$n';
    }
    if (sc is int) return 'Classe #$sc';
    if (sc is num) return 'Classe #${sc.toInt()}';
    if (course is Map) {
      final cn = course['class_name'] ?? course['school_class_name'];
      if (cn != null && '$cn'.trim().isNotEmpty) return '$cn';
    }
    return 'N/A';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Cours'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final changed =
                  await context.push<bool>('/teacher/courses/create');
              if (changed == true && mounted) {
                await _loadCourses();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un cours...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadCourses,
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredCourses.isEmpty
                        ? const Center(child: Text('Aucun cours'))
                        : RefreshIndicator(
                            onRefresh: _loadCourses,
                            child: ListView.builder(
                              itemCount: _filteredCourses.length,
                              itemBuilder: (context, index) {
                                final course = _filteredCourses[index];
                                final id = course['id'];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: ListTile(
                                    leading: const Icon(Icons.book),
                                    title: Text(course['title'] ?? 'Cours'),
                                    subtitle: Text('Classe: ${_schoolClassLabel(course)}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (course['is_published'] == true)
                                          const Icon(Icons.check_circle,
                                              color: Colors.green),
                                        PopupMenuButton<String>(
                                          onSelected: (value) async {
                                            if (id == null) return;
                                            if (value == 'edit') {
                                              final ok = await context.push<bool>(
                                                '/teacher/courses/$id/edit',
                                              );
                                              if (ok == true && mounted) {
                                                await _loadCourses();
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Modifier'),
                                            ),
                                          ],
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                    onTap: () {
                                      if (id == null) return;
                                      context.push('/teacher/courses/$id');
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
