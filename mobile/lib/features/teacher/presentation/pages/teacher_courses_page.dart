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
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/elearning/courses/');
      setState(() {
        _courses = response.data is List 
            ? response.data 
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Cours'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              context.push('/teacher/courses/create');
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
                : _filteredCourses.isEmpty
                    ? const Center(child: Text('Aucun cours'))
                    : RefreshIndicator(
                        onRefresh: _loadCourses,
                        child: ListView.builder(
                          itemCount: _filteredCourses.length,
                          itemBuilder: (context, index) {
                            final course = _filteredCourses[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: const Icon(Icons.book),
                                title: Text(course['title'] ?? 'Cours'),
                                subtitle: Text('Classe: ${course['school_class']?['name'] ?? 'N/A'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (course['is_published'] == true)
                                      const Icon(Icons.check_circle, color: Colors.green),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () {
                                  context.push('/teacher/courses/${course['id']}');
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
