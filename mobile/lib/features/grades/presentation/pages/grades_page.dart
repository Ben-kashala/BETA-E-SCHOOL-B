import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  List<dynamic> _children = [];
  int? _selectedChildId;
  List<dynamic> _grades = [];
  List<dynamic> _filteredGrades = [];
  List<dynamic> _gradeBulletins = [];
  List<dynamic> _reportCards = [];
  List<dynamic> _submissions = [];
  List<dynamic> _quizAttempts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedSubject;
  List<dynamic> _subjects = [];
  bool _isStudent = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = ref.read(authProvider).user;
    final isParent = user?.isParent ?? false;
    final isStudent = user?.isStudent ?? false;

    setState(() {
      _isLoading = true;
      _isStudent = isStudent ?? false;
    });

    try {
      if (isParent) {
        // Pour les parents : charger les enfants d'abord
        await _loadChildren();
        if (_children.isNotEmpty && _selectedChildId == null) {
          _selectedChildId = _children.first['id'];
        }
      }
      await _loadGrades();
      
      // Pour les élèves : charger aussi les bulletins et rapports
      if (isStudent) {
        await _loadStudentGradeData();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStudentGradeData() async {
    try {
      final [bulletinsRes, reportCardsRes, submissionsRes, attemptsRes] = await Future.wait([
        ApiService().get('/api/academics/grade-bulletins/'),
        ApiService().get('/api/academics/report-cards/'),
        ApiService().get('/api/elearning/submissions/'),
        ApiService().get('/api/elearning/quiz-attempts/'),
      ]);

      setState(() {
        _gradeBulletins = bulletinsRes.data is List 
            ? bulletinsRes.data 
            : (bulletinsRes.data['results'] ?? []);
        _reportCards = reportCardsRes.data is List 
            ? reportCardsRes.data 
            : (reportCardsRes.data['results'] ?? []);
        _submissions = submissionsRes.data is List 
            ? submissionsRes.data 
            : (submissionsRes.data['results'] ?? []);
        _quizAttempts = attemptsRes.data is List 
            ? attemptsRes.data 
            : (attemptsRes.data['results'] ?? []);
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _loadChildren() async {
    try {
      final user = ref.read(authProvider).user;
      final isParent = user?.isParent ?? false;

      // Pour les parents, on utilise le même endpoint que le dashboard et les paiements
      // afin de récupérer uniquement leurs enfants avec les bons champs.
      final path = isParent
          ? '/api/auth/students/parent_dashboard/'
          : '/api/auth/students/';

      final response = await ApiService().get<dynamic>(
        path,
        useCache: false,
      );
      final data = response.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] != null)
              ? (data['results'] as List)
              : <dynamic>[];
      final children = list is List<dynamic> ? list : List<dynamic>.from(list);

      if (mounted) {
        setState(() {
          _children = children;

          // Initialiser l'enfant sélectionné pour les parents
          if (isParent && _children.isNotEmpty) {
            final first = _children.first;
            final identity = first is Map
                ? (first['identity'] as Map?) ?? first
                : <String, dynamic>{};
            _selectedChildId = identity['id'] as int?;
          } else if (!isParent && _children.isNotEmpty) {
            final first = _children.first;
            _selectedChildId = first is Map ? first['id'] as int? : null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _children = []);
    }
  }

  Future<void> _loadGrades() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = ref.read(authProvider).user;
      final isParent = user?.isParent ?? false;
      
      Map<String, dynamic>? queryParams;
      if (isParent && _selectedChildId != null) {
        queryParams = {'student': _selectedChildId};
      }

      final api = ApiService();

      // 1) Essayer les notes classiques (comme le web)
      final response = await api.get<dynamic>(
        '/api/academics/grades/',
        queryParameters: queryParams,
        useCache: false,
      );
      final data = response.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] != null)
              ? (data['results'] as List)
              : <dynamic>[];
      List<dynamic> grades = list is List<dynamic> ? list : List<dynamic>.from(list);

      // 2) Fallback parent : si aucune note trouvée pour l'enfant sélectionné,
      //    mapper les bulletins RDC en "notes", comme pour le web.
      if (isParent && (_selectedChildId != null) && grades.isEmpty) {
        try {
          final bRes = await api.get<dynamic>(
            '/api/academics/grade-bulletins/',
            queryParameters: {'student': _selectedChildId.toString()},
            useCache: false,
          );
          final bData = bRes.data;
          final bulletins = bData is List
              ? bData
              : (bData is Map && bData['results'] != null)
                  ? (bData['results'] as List)
                  : <dynamic>[];

          grades = bulletins.map((b) {
            final m = b as Map? ?? {};
            return {
              'id': m['id'],
              'student_name': m['student_name'],
              'subject_name': m['subject_name'],
              'term': 'AN',
              'total_score': m['total_general'],
              // Champs utilisés par l’UI mobile
              'subject': {
                'name': m['subject_name'],
              },
              'score': m['total_general'],
              'total_points': 20,
            };
          }).toList();
        } catch (_) {
          // En cas d'erreur, on garde simplement la liste vide de grades.
        }
      }
      // Charger les matières pour les filtres
      try {
        final subjectsResponse = await ApiService().get('/api/schools/subjects/');
        setState(() {
          _subjects = subjectsResponse.data is List
              ? subjectsResponse.data
              : (subjectsResponse.data['results'] ?? []);
        });
      } catch (e) {
        // Ignore
      }
      
      if (mounted) {
        setState(() {
          _grades = grades;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredGrades = _grades.where((grade) {
        // Recherche
        if (_searchQuery.isNotEmpty) {
          final courseName = (grade['course']?['name'] ?? '').toString().toLowerCase();
          final assignmentTitle = (grade['assignment']?['title'] ?? '').toString().toLowerCase();
          final examTitle = (grade['exam']?['title'] ?? '').toString().toLowerCase();
          if (!courseName.contains(_searchQuery.toLowerCase()) &&
              !assignmentTitle.contains(_searchQuery.toLowerCase()) &&
              !examTitle.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Filtre matière
        if (_selectedSubject != null) {
          if (grade['subject']?['id']?.toString() != _selectedSubject) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return double.tryParse(v.toString());
  }

  Color _getGradeColor(dynamic score, dynamic maxScore) {
    final s = _toDouble(score);
    final m = _toDouble(maxScore);
    if (s == null || m == null || m == 0) return Colors.grey;
    final percentage = (s / m) * 100;
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.orange;
    return Colors.red;
  }

  Future<void> _openReportCardPdf(int reportCardId) async {
    try {
      final user = ref.read(authProvider).user;
      final studentId = user?.id;
      if (studentId == null) return; // Sécurité minimale
      
      final api = ApiService();
      final baseUrl = api.baseUrl;
      final url = '$baseUrl/api/academics/report-cards/$reportCardId/download_pdf/';
      
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _downloadOfficialBulletinForStudent(int studentId, {String? academicYear}) async {
    try {
      final params = <String, dynamic>{
        'student': studentId.toString(),
        'term': 'AN',
        'is_published': 'true',
      };
      if (academicYear != null && academicYear.isNotEmpty) {
        params['academic_year'] = academicYear;
      }

      final res = await ApiService().get<dynamic>(
        '/api/academics/report-cards/',
        queryParameters: params,
        useCache: false,
      );
      final data = res.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] != null)
              ? (data['results'] as List)
              : <dynamic>[];
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun bulletin officiel trouvé pour cette année.')),
          );
        }
        return;
      }
      final first = list.first as Map<dynamic, dynamic>;
      final reportCardId = first['id'] as int?;
      if (reportCardId == null) return;
      await _openReportCardPdf(reportCardId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement du bulletin: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isParent = user?.isParent ?? false;
    final isStudent = user?.isStudent ?? false;

    // Vue spéciale pour les élèves avec bulletins RDC
    if (isStudent) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mes Notes'),
          bottom: TabBar(
            tabs: const [
            Tab(text: 'Bulletins RDC', icon: Icon(Icons.description)),
              Tab(text: 'Notes détaillées', icon: Icon(Icons.list)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Vue bulletins RDC
            _buildBulletinsView(),
            // Vue notes détaillées
            _buildDetailedGradesView(isParent),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isParent ? 'Suivi Scolaire' : 'Mes Notes'),
      ),
      body: Column(
        children: [
          // Sélecteur d'enfant pour les parents
          if (isParent && _children.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Sélectionner un enfant',
                  prefixIcon: Icon(Icons.person),
                ),
                items: _children.map<DropdownMenuItem<int>>((child) {
                  final c = child is Map ? child : <String, dynamic>{};
                  final identity = (c['identity'] as Map?) ?? c;
                  final id = identity['id'] as int?;
                  final name = identity['user_name'] ??
                      '${identity['user']?['first_name'] ?? ''} ${identity['user']?['last_name'] ?? ''}'.trim();
                  final cls = identity['class_name'] ??
                      identity['school_class']?['name'] ??
                      '';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('$name${cls.isNotEmpty ? ' - $cls' : ''}'),
                  );
                }).toList(),
                onChanged: (int? value) {
                  setState(() {
                    _selectedChildId = value;
                  });
                  _loadGrades();
                },
              ),
            ),
          // Bouton bulletin officiel pour l'enfant sélectionné (parents)
          if (isParent && _selectedChildId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _downloadOfficialBulletinForStudent(_selectedChildId!),
                  icon: const Icon(Icons.download),
                  label: const Text('Télécharger le bulletin officiel'),
                ),
              ),
            ),
          // Barre de recherche et filtres
          SearchFilterBar(
            hintText: 'Rechercher une note...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'subject',
                label: 'Matière',
                values: _subjects.map((s) => FilterValue(
                  value: s['id'].toString(),
                  label: s['name'] ?? 'Matière',
                )).toList(),
                selectedValue: _selectedSubject,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() => _selectedSubject = filters['subject']);
              _applyFilters();
            },
          ),
          // Liste des notes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGrades.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isParent ? Icons.school_outlined : Icons.grade_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isParent
                                  ? 'Aucune note disponible pour cet enfant'
                                  : 'Aucune note disponible',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadGrades,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredGrades.length,
                          itemBuilder: (context, index) {
                            final grade = _filteredGrades[index];
                            final score = grade['score']?.toDouble();
                            final maxScore = grade['max_score']?.toDouble();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: _getGradeColor(score, maxScore),
                                  child: Text(
                                    score != null && maxScore != null
                                        ? '${((score / maxScore) * 100).toInt()}'
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(grade['course']?['name'] ?? 'Cours'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isParent && grade['student'] != null)
                                      Text('Élève: ${grade['student']['name'] ?? ''}'),
                                    if (grade['assignment'] != null)
                                      Text('Devoir: ${grade['assignment']['title']}'),
                                    if (grade['exam'] != null)
                                      Text('Examen: ${grade['exam']['title']}'),
                                    if (score != null && maxScore != null)
                                      Text('${score.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(2)}'),
                                    if (grade['comment'] != null)
                                      Text(grade['comment']),
                                  ],
                                ),
                                trailing: grade['created_at'] != null
                                    ? Text(
                                        DateFormat('dd/MM/yyyy').format(
                                          DateTime.parse(grade['created_at']),
                                        ),
                                      )
                                    : null,
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

  Widget _buildBulletinsView() {
    // Grouper les bulletins par année/classe
    final Map<String, List<dynamic>> bulletinsByYear = {};
    for (var bulletin in _gradeBulletins) {
      final key = '${bulletin['academic_year']}-${bulletin['school_class']}';
      if (!bulletinsByYear.containsKey(key)) {
        bulletinsByYear[key] = [];
      }
      bulletinsByYear[key]!.add(bulletin);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (bulletinsByYear.isEmpty && _reportCards.isEmpty) {
      return const Center(child: Text('Aucun bulletin disponible'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bulletins RDC par matière
          if (bulletinsByYear.isNotEmpty) ...[
            ...bulletinsByYear.entries.map((entry) {
              final yearClass = entry.key.split('-');
              final academicYear = yearClass[0];
              final schoolClassId = yearClass.length > 1 ? int.tryParse(yearClass[1]) : null;
              final bulletins = entry.value;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Année: $academicYear',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              final first = bulletins.isNotEmpty && bulletins.first is Map
                                  ? bulletins.first as Map
                                  : null;
                              final int? studentId = first != null ? first['student'] as int? : null;
                              if (studentId != null) {
                                _downloadOfficialBulletinForStudent(studentId, academicYear: academicYear);
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: const Text('Télécharger bulletin officiel'),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Matière')),
                          DataColumn(label: Text('1ère P.'), numeric: true),
                          DataColumn(label: Text('2ème P.'), numeric: true),
                          DataColumn(label: Text('Exam. S1'), numeric: true),
                          DataColumn(label: Text('TOT. S1'), numeric: true),
                          DataColumn(label: Text('3ème P.'), numeric: true),
                          DataColumn(label: Text('4ème P.'), numeric: true),
                          DataColumn(label: Text('Exam. S2'), numeric: true),
                          DataColumn(label: Text('TOT. S2'), numeric: true),
                          DataColumn(label: Text('T.G.'), numeric: true),
                        ],
                        rows: bulletins.map((b) {
                          return DataRow(
                            cells: [
                              DataCell(Text(b['subject_name'] ?? '-')),
                              DataCell(Text(b['s1_p1']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['s1_p2']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['s1_exam']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['total_s1']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['s2_p3']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['s2_p4']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['s2_exam']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(b['total_s2']?.toStringAsFixed(1) ?? '-')),
                              DataCell(Text(
                                b['total_general']?.toStringAsFixed(1) ?? '-',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
          // Bulletins (décision)
          if (_reportCards.isNotEmpty) ...[
            Text(
              'Bulletins (décision)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ..._reportCards.map((card) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${card['academic_year'] ?? ''} - ${card['class_name'] ?? ''}'),
                  subtitle: Text('Décision: ${card['decision'] ?? '-'}'),
                  trailing: card['academic_year'] != null
                      ? IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () {
                            final int? studentId =
                                (card['student'] as int?) ?? (card['student_id'] as int?) ?? null;
                            if (studentId != null) {
                              _downloadOfficialBulletinForStudent(
                                studentId,
                                academicYear: card['academic_year'] as String?,
                              );
                            }
                          },
                        )
                      : null,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedGradesView(bool isParent) {
    // Vue agrégée par matière avec notes e-learning
    final Map<String, List<dynamic>> gradesBySubject = {};
    
    // Ajouter les notes générales
    for (var grade in _grades) {
      final subject = grade['subject']?['name'] ?? grade['course']?['name'] ?? 'Autre';
      if (!gradesBySubject.containsKey(subject)) {
        gradesBySubject[subject] = [];
      }
      gradesBySubject[subject]!.add({'type': 'general', 'data': grade});
    }
    
    // Ajouter les soumissions (devoirs)
    for (var submission in _submissions) {
      if (submission['score'] == null) continue;
      final subject = submission['assignment_subject_name'] ?? submission['assignment_title'] ?? 'Autre';
      if (!gradesBySubject.containsKey(subject)) {
        gradesBySubject[subject] = [];
      }
      gradesBySubject[subject]!.add({'type': 'assignment', 'data': submission});
    }
    
    // Ajouter les tentatives de quiz (examens)
    for (var attempt in _quizAttempts) {
      if (attempt['score'] == null) continue;
      final subject = attempt['quiz_subject_name'] ?? attempt['quiz_title'] ?? 'Autre';
      if (!gradesBySubject.containsKey(subject)) {
        gradesBySubject[subject] = [];
      }
      gradesBySubject[subject]!.add({'type': 'quiz', 'data': attempt});
    }

    return Column(
      children: [
        SearchFilterBar(
          hintText: 'Rechercher une note...',
          onSearchChanged: (value) {
            setState(() => _searchQuery = value);
            _applyFilters();
          },
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : gradesBySubject.isEmpty
                  ? const Center(child: Text('Aucune note disponible'))
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: gradesBySubject.length,
                        itemBuilder: (context, index) {
                          final entry = gradesBySubject.entries.elementAt(index);
                          final subject = entry.key;
                          final items = entry.value;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: ExpansionTile(
                              title: Text(subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${items.length} note(s)'),
                              children: items.map((item) {
                                final data = item['data'];
                                final type = item['type'];
                                
                                if (type == 'general') {
                                  final score = data['score']?.toDouble();
                                  final maxScore = data['max_score']?.toDouble();
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _getGradeColor(score, maxScore),
                                      child: Text(
                                        score != null && maxScore != null
                                            ? '${((score / maxScore) * 100).toInt()}'
                                            : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(data['course']?['name'] ?? 'Note'),
                                    subtitle: Text(
                                      score != null && maxScore != null
                                          ? '${score.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(2)}'
                                          : '-',
                                    ),
                                  );
                                } else if (type == 'assignment') {
                                  final score = data['score']?.toDouble();
                                  final maxPoints = data['assignment']?['total_points']?.toDouble() ?? data['total_points']?.toDouble() ?? 20;
                                  return ListTile(
                                    leading: const Icon(Icons.assignment),
                                    title: Text(data['assignment_title'] ?? 'Devoir'),
                                    subtitle: Text('${score?.toStringAsFixed(2) ?? '-'} / $maxPoints'),
                                  );
                                } else if (type == 'quiz') {
                                  final score = data['score']?.toDouble();
                                  final maxPoints = data['quiz']?['total_points']?.toDouble() ?? data['total_points']?.toDouble() ?? 20;
                                  return ListTile(
                                    leading: const Icon(Icons.quiz),
                                    title: Text(data['quiz_title'] ?? 'Examen'),
                                    subtitle: Text('${score?.toStringAsFixed(2) ?? '-'} / $maxPoints'),
                                  );
                                }
                                return const SizedBox.shrink();
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
