import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class TeacherMyClassPage extends ConsumerStatefulWidget {
  const TeacherMyClassPage({super.key});

  @override
  ConsumerState<TeacherMyClassPage> createState() => _TeacherMyClassPageState();
}

class _TeacherMyClassPageState extends ConsumerState<TeacherMyClassPage> {
  Map<String, dynamic>? _homeroomClass;
  List<dynamic> _students = [];
  List<dynamic> _filteredStudents = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Charger la classe titulaire de l'enseignant
      final classResponse = await ApiService().get('/api/schools/classes/my_titular/');
      final classData = classResponse.data;
      
      if (classData != null) {
        setState(() {
          _homeroomClass = classData is Map ? Map<String, dynamic>.from(classData as Map) : null;
        });
        
        // Charger les élèves de la classe
        if (_homeroomClass != null) {
          await _loadStudents(_homeroomClass!['id']);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStudents(int classId) async {
    try {
      final response = await ApiService().get(
        '/api/accounts/students/',
        queryParameters: {'school_class': classId.toString()},
      );
      final students = response.data is List 
          ? response.data 
          : (response.data['results'] ?? []);
      
      setState(() {
        _students = students;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredStudents = _students.where((student) {
        if (_searchQuery.isNotEmpty) {
          final name = '${student['user']?['first_name'] ?? ''} ${student['user']?['last_name'] ?? ''}'.toLowerCase();
          final studentId = (student['student_id'] ?? '').toString().toLowerCase();
          if (!name.contains(_searchQuery.toLowerCase()) && 
              !studentId.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Future<void> _downloadBulletin(int studentId, int? schoolClassId, String? academicYear) async {
    if (schoolClassId == null || academicYear == null) return;

    try {
      final baseUrl = ApiService().baseUrl;
      final suffix = baseUrl.endsWith('/') ? '' : '/';
      final url = '$baseUrl${suffix}api/auth/students/$studentId/bulletin_pdf/?school_class=$schoolClassId&academic_year=${Uri.encodeComponent(academicYear)}';

      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/downloads/bulletins');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeYear = academicYear.replaceAll(RegExp(r'[^0-9-]'), '_');
      final filePath = '${dir.path}/bulletin_${studentId}_$safeYear.pdf';

      await ApiService().downloadFile(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulletin enregistré: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma classe')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_homeroomClass == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma classe')),
        body: const Center(
          child: Text('Vous n\'êtes pas titulaire d\'une classe'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Ma classe: ${_homeroomClass!['name'] ?? ''}'),
      ),
      body: Column(
        children: [
          // Informations de la classe
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Classe: ${_homeroomClass!['name'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_homeroomClass!['academic_year'] != null)
                    Text('Année scolaire: ${_homeroomClass!['academic_year']}'),
                  if (_homeroomClass!['level'] != null)
                    Text('Niveau: ${_homeroomClass!['level']}'),
                  Text('Nombre d\'élèves: ${_students.length}'),
                ],
              ),
            ),
          ),
          // Barre de recherche
          SearchFilterBar(
            hintText: 'Rechercher un élève...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          // Liste des élèves
          Expanded(
            child: _filteredStudents.isEmpty
                ? const Center(child: Text('Aucun élève trouvé'))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final user = student['user'] ?? {};
                        final firstName = user['first_name'] ?? '';
                        final lastName = user['last_name'] ?? '';
                        final studentId = student['student_id'] ?? '';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                              ),
                            ),
                            title: Text('$firstName $lastName'.trim()),
                            subtitle: Text('Matricule: $studentId'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              context.push('/students/${student['id']}');
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
