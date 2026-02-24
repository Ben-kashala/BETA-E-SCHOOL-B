import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';

class TeacherAssignmentsPage extends ConsumerStatefulWidget {
  const TeacherAssignmentsPage({super.key});

  @override
  ConsumerState<TeacherAssignmentsPage> createState() => _TeacherAssignmentsPageState();
}

class _TeacherAssignmentsPageState extends ConsumerState<TeacherAssignmentsPage> {
  List<dynamic> _assignments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  /// school_class peut être un id (int) ou un objet { id, name } selon l'API.
  String _className(dynamic schoolClass) {
    if (schoolClass == null) return 'N/A';
    if (schoolClass is Map && schoolClass['name'] != null) {
      return schoolClass['name'].toString();
    }
    if (schoolClass is num) return 'Classe #$schoolClass';
    return 'N/A';
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/elearning/assignments/');
      setState(() {
        _assignments = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devoirs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Créer un nouveau devoir
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(child: Text('Aucun devoir'))
              : RefreshIndicator(
                  onRefresh: _loadAssignments,
                  child: ListView.builder(
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final assignment = _assignments[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.assignment),
                          title: Text(assignment['title'] ?? 'Devoir'),
                          subtitle: Text('Classe: ${_className(assignment['school_class'])}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            // TODO: Navigation vers détails
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
