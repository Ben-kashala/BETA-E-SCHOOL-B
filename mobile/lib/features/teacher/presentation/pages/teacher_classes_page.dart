import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';

class TeacherClassesPage extends ConsumerStatefulWidget {
  const TeacherClassesPage({super.key});

  @override
  ConsumerState<TeacherClassesPage> createState() => _TeacherClassesPageState();
}

class _TeacherClassesPageState extends ConsumerState<TeacherClassesPage> {
  List<dynamic> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/schools/classes/my_titular/');
      setState(() {
        _classes = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Classes'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? const Center(child: Text('Aucune classe assignée'))
              : RefreshIndicator(
                  onRefresh: _loadClasses,
                  child: ListView.builder(
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final classItem = _classes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.class_),
                          title: Text(classItem['name'] ?? 'Classe'),
                          subtitle: Text('Niveau: ${classItem['level'] ?? 'N/A'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            context.push('/teacher/class-subjects', extra: classItem['id'] as int?);
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
