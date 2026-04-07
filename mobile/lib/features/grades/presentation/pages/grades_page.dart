import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';

/// Colonnes bulletin RDC (même logique que `frontend` MyClass.tsx / capture 2).
class _BulletinCol {
  final String key;
  final String label;
  final int mult;
  const _BulletinCol(this.key, this.label, this.mult);
}

const _kBulletinCols = <_BulletinCol>[
  _BulletinCol('s1_p1', '1ère P.', 1),
  _BulletinCol('s1_p2', '2ème P.', 1),
  _BulletinCol('s1_exam', 'Exam. S1', 2),
  _BulletinCol('total_s1', 'TOT. S1', 4),
  _BulletinCol('s2_p3', '3ème P.', 1),
  _BulletinCol('s2_p4', '4ème P.', 1),
  _BulletinCol('s2_exam', 'Exam. S2', 2),
  _BulletinCol('total_s2', 'TOT. S2', 4),
  _BulletinCol('total_general', 'T.G.', 8),
];

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
    });

    try {
      if (isParent) {
        await _loadChildren();
      }
      await _loadGrades();

      if (isStudent || isParent) {
        await _loadBulletinReportData();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBulletinReportData() async {
    final user = ref.read(authProvider).user;
    final isParent = user?.isParent ?? false;
    final isStudent = user?.isStudent ?? false;
    if (!isStudent && !isParent) return;

    try {
      final Map<String, dynamic>? studentFilter =
          isParent && _selectedChildId != null ? {'student': _selectedChildId.toString()} : null;

      if (isStudent) {
        final results = await Future.wait([
          ApiService().get<dynamic>(
            '/api/academics/grade-bulletins/',
            useCache: false,
          ),
          ApiService().get<dynamic>(
            '/api/academics/report-cards/',
            useCache: false,
          ),
          ApiService().get<dynamic>('/api/elearning/submissions/'),
          ApiService().get<dynamic>('/api/elearning/quiz-attempts/'),
        ]);
        final bulletinsRes = results[0];
        final reportCardsRes = results[1];
        final submissionsRes = results[2];
        final attemptsRes = results[3];
        if (!mounted) return;
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
      } else {
        final results = await Future.wait([
          ApiService().get<dynamic>(
            '/api/academics/grade-bulletins/',
            queryParameters: studentFilter,
            useCache: false,
          ),
          ApiService().get<dynamic>(
            '/api/academics/report-cards/',
            queryParameters: studentFilter,
            useCache: false,
          ),
        ]);
        if (!mounted) return;
        setState(() {
          _gradeBulletins = results[0].data is List
              ? results[0].data
              : (results[0].data['results'] ?? []);
          _reportCards = results[1].data is List
              ? results[1].data
              : (results[1].data['results'] ?? []);
          _submissions = [];
          _quizAttempts = [];
        });
      }
    } catch (_) {
      // Ignorer
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
            _selectedChildId = _parseIntId(identity['id']);
          } else if (!isParent && _children.isNotEmpty) {
            final first = _children.first;
            _selectedChildId = first is Map ? _parseIntId(first['id']) : null;
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
            final pm = _toDouble(m['subject_period_max']) ?? 20.0;
            return {
              'id': m['id'],
              'student_name': m['student_name'],
              'subject_name': m['subject_name'],
              'term': 'AN',
              'total_score': m['total_general'],
              'subject': {
                'name': m['subject_name'],
              },
              'score': m['total_general'],
              'subject_period_max': m['subject_period_max'],
              'total_points': pm * 8,
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

  /// IDs JSON parfois en double — évite les cast int? invalides sur Dropdown / clés.
  int? _parseIntId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
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

  String _formatBulletinVal(dynamic v) {
    if (v == null || v == '') return '—';
    final n = _toDouble(v);
    if (n == null) return '—';
    return n.toStringAsFixed(2);
  }

  bool _isBelowBaseBulletin(dynamic value, int mult, int periodMax) {
    final n = _toDouble(value);
    if (n == null) return false;
    final max = mult * periodMax;
    return max > 0 && n < max * 0.5;
  }

  double? _columnPct(List<dynamic> bulletins, String key, int mult) {
    double sumPoints = 0;
    double sumMax = 0;
    for (final raw in bulletins) {
      final g = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
      final v = g[key];
      final n = _toDouble(v) ?? 0;
      sumPoints += n;
      final pm = _toDouble(g['subject_period_max']) ?? 20;
      sumMax += mult * pm;
    }
    if (sumMax <= 0) return null;
    return sumPoints / sumMax * 100;
  }

  double? _overallPctFromBulletins(List<dynamic> bulletins) {
    double sumPts = 0;
    double sumMax = 0;
    for (final raw in bulletins) {
      final g = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
      final tg = _toDouble(g['total_general']);
      final pm = _toDouble(g['subject_period_max']) ?? 20;
      if (tg != null) sumPts += tg;
      sumMax += pm * 8;
    }
    if (sumMax <= 0) return null;
    return sumPts / sumMax * 100;
  }

  Map<String, dynamic>? _reportCardForYear(String academicYear) {
    for (final r in _reportCards) {
      if (r is Map && (r['academic_year']?.toString() ?? '') == academicYear) {
        return Map<String, dynamic>.from(r as Map);
      }
    }
    return null;
  }

  String _displayStudentNameForBulletin() {
    final user = ref.read(authProvider).user;
    if (user == null) return 'Élève';
    if (user.isParent && _selectedChildId != null) {
      for (final child in _children) {
        if (child is! Map) continue;
        final c = Map<String, dynamic>.from(child);
        final identity = (c['identity'] as Map?) ?? c;
        final id = _parseIntId(identity['id']);
        if (id == null || id != _selectedChildId) continue;
        final u = identity['user'] as Map?;
        if (u != null) {
          final fn = u['first_name']?.toString() ?? '';
          final ln = u['last_name']?.toString() ?? '';
          final name = '$fn $ln'.trim();
          if (name.isNotEmpty) return name;
        }
        return identity['user_name']?.toString() ?? 'Élève';
      }
    }
    final n = user.fullName.trim();
    return n.isEmpty ? 'Élève' : n;
  }

  Future<Map<String, String>> _pdfAuthHeaders() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    final schoolCode = await storage.read(key: 'school_code');
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (schoolCode != null) 'X-School-Code': schoolCode,
    };
  }

  Future<void> _savePdfBytesAndOpen(List<int> bytes, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads/bulletins');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    final safe = fileName.replaceAll(RegExp(r'[^\w\-\.]'), '_');
    final file = File('${downloadDir.path}/$safe');
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bulletin téléchargé')),
      );
    }
    await OpenFilex.open(file.path);
  }

  Future<void> _downloadOfficialBulletinForStudent(
    int studentId, {
    String? academicYear,
    int? schoolClassId,
  }) async {
    try {
      final api = ApiService();
      final dio = Dio();
      final headers = await _pdfAuthHeaders();

      int? reportCardId;

      final attempts = <Map<String, dynamic>>[
        if (academicYear != null && academicYear.isNotEmpty)
          {
            'student': studentId.toString(),
            'term': 'AN',
            'academic_year': academicYear,
          },
        {'student': studentId.toString(), 'term': 'AN'},
        if (academicYear != null && academicYear.isNotEmpty)
          {
            'student': studentId.toString(),
            'academic_year': academicYear,
          },
        {'student': studentId.toString()},
      ];

      for (final qp in attempts) {
        final res = await ApiService().get<dynamic>(
          '/api/academics/report-cards/',
          queryParameters: qp,
          useCache: false,
        );
        final data = res.data;
        final list = data is List
            ? data
            : (data is Map && data['results'] != null)
                ? (data['results'] as List)
                : <dynamic>[];
        if (list.isEmpty) continue;
        final raw = list.first;
        if (raw is Map) {
          final id = _parseIntId(raw['id']);
          if (id != null) {
            reportCardId = id;
            break;
          }
        }
      }

      if (reportCardId == null &&
          academicYear != null &&
          academicYear.isNotEmpty) {
        try {
          final gen = await ApiService().post<dynamic>(
            '/api/accounts/students/$studentId/generate_annual_bulletin/',
            data: {'academic_year': academicYear},
          );
          final body = gen.data;
          if (body is Map && body['report_card'] is Map) {
            final rc = body['report_card'] as Map;
            reportCardId = _parseIntId(rc['id']);
          }
        } catch (_) {
          // On tente ensuite bulletin_pdf.
        }
      }

      if (reportCardId != null) {
        final response = await dio.get<List<int>>(
          '${api.baseUrl}/api/academics/report-cards/$reportCardId/download_pdf/',
          options: Options(
            headers: headers,
            responseType: ResponseType.bytes,
          ),
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Réponse PDF vide');
        }
        await _savePdfBytesAndOpen(bytes, 'bulletin_$studentId.pdf');
        return;
      }

      if (schoolClassId != null &&
          academicYear != null &&
          academicYear.isNotEmpty) {
        final response = await dio.get<List<int>>(
          '${api.baseUrl}/api/accounts/students/$studentId/bulletin_pdf/',
          queryParameters: {
            'school_class': schoolClassId,
            'academic_year': academicYear,
          },
          options: Options(
            headers: headers,
            responseType: ResponseType.bytes,
          ),
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Réponse PDF vide');
        }
        await _savePdfBytesAndOpen(bytes, 'bulletin_${studentId}_$academicYear.pdf');
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de générer le bulletin : année ou classe manquante.',
            ),
          ),
        );
      }
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

    // Élèves et parents : onglets « Bulletins RDC » (tableau type capture 2) + notes détaillées
    if (isStudent || isParent) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(isParent ? 'Suivi scolaire' : 'Mes notes'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Bulletins RDC', icon: Icon(Icons.description)),
                Tab(text: 'Notes détaillées', icon: Icon(Icons.list)),
              ],
            ),
          ),
          body: Column(
            children: [
              if (isParent && _children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _selectedChildId,
                    decoration: const InputDecoration(
                      labelText: 'Sélectionner un enfant',
                      prefixIcon: Icon(Icons.person),
                    ),
                    items: _children
                        .map<DropdownMenuItem<int>?>((child) {
                          final c = child is Map ? child : <String, dynamic>{};
                          final identity = (c['identity'] as Map?) ?? c;
                          final id = _parseIntId(identity['id']);
                          if (id == null) return null;
                          final name = identity['user_name'] ??
                              '${identity['user']?['first_name'] ?? ''} ${identity['user']?['last_name'] ?? ''}'.trim();
                          final cls = identity['class_name'] ??
                              identity['school_class']?['name'] ??
                              '';
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text('$name${cls.isNotEmpty ? ' - $cls' : ''}'),
                          );
                        })
                        .whereType<DropdownMenuItem<int>>()
                        .toList(),
                    onChanged: (int? value) async {
                      setState(() => _selectedChildId = value);
                      await _loadGrades();
                      await _loadBulletinReportData();
                    },
                  ),
                ),
              if (isParent && _selectedChildId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final sid = _selectedChildId!;
                        String? ay;
                        int? scId;
                        for (final raw in _gradeBulletins) {
                          if (raw is! Map) continue;
                          final m = Map<String, dynamic>.from(raw as Map);
                          if (_parseIntId(m['student']) != sid) continue;
                          ay = m['academic_year']?.toString();
                          scId = _parseIntId(m['school_class']);
                          break;
                        }
                        _downloadOfficialBulletinForStudent(
                          sid,
                          academicYear: ay,
                          schoolClassId: scId,
                        );
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Télécharger le bulletin officiel'),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildBulletinsView(),
                    _buildDetailedGradesView(isParent),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
      ),
      body: Column(
        children: [
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
                          padding: ScrollContentPadding.page(context),
                          itemCount: _filteredGrades.length,
                          itemBuilder: (context, index) {
                            final grade = _filteredGrades[index];
                            final score = _toDouble(grade['score']);
                            final maxScore = _toDouble(grade['max_score'] ?? grade['total_points'] ?? 20);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: _getGradeColor(score, maxScore),
                                  child: Text(
                                    (score != null && maxScore != null && maxScore != 0)
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

  Widget _bulletinTableText(
    String text, {
    required TextStyle style,
    TextAlign align = TextAlign.center,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Tableau large défilant : mêmes colonnes / ligne Pourcentage / seuil rouge que le web (capture 2).
  ///
  /// [pageStorageScope] doit être unique par carte (ex. clé année+classe) pour ne pas partager le
  /// même [PageStorage] que l’[ExpansionTile] parent : sinon le scroll horizontal enregistre un
  /// `double` là où le tile attend un `bool` → cast error au runtime.
  Widget _buildRdcBulletinTable(
    List<dynamic> bulletins, {
    required String pageStorageScope,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = cs.outline.withOpacity(0.35);
    final headerBg = cs.surfaceContainerHighest;
    final footerBg = cs.surfaceContainerHighest.withOpacity(0.9);
    final hdrStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 11,
      color: cs.onSurface,
    );
    final baseStyle = TextStyle(fontSize: 12, color: cs.onSurface);

    final subjectRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: headerBg),
        children: [
          _bulletinTableText('Matière', style: hdrStyle, align: TextAlign.left),
          ..._kBulletinCols.map(
            (c) => _bulletinTableText(c.label, style: hdrStyle, align: TextAlign.center),
          ),
        ],
      ),
    ];

    for (final raw in bulletins) {
      final b = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
      final pm = (_toDouble(b['subject_period_max']) ?? 20).round();
      subjectRows.add(
        TableRow(
          children: [
            _bulletinTableText(
              b['subject_name']?.toString() ?? '—',
              style: baseStyle.copyWith(fontWeight: FontWeight.w500),
              align: TextAlign.left,
            ),
            ..._kBulletinCols.map((c) {
              final v = b[c.key];
              final below = _isBelowBaseBulletin(v, c.mult, pm);
              return _bulletinTableText(
                _formatBulletinVal(v),
                style: baseStyle.copyWith(
                  color: below ? cs.error : cs.onSurface,
                  fontWeight: below ? FontWeight.w600 : FontWeight.normal,
                ),
                align: TextAlign.center,
              );
            }),
          ],
        ),
      );
    }

    final pctCells = <Widget>[
      _bulletinTableText('Pourcentage', style: hdrStyle, align: TextAlign.left),
      ..._kBulletinCols.map((c) {
        final pct = _columnPct(bulletins, c.key, c.mult);
        final label = pct != null ? '${pct.toStringAsFixed(1)} %' : '—';
        final below = pct != null && pct < 50;
        return _bulletinTableText(
          label,
          style: hdrStyle.copyWith(
            color: below ? cs.error : cs.onSurface,
          ),
          align: TextAlign.center,
        );
      }),
    ];
    subjectRows.add(
      TableRow(
        decoration: BoxDecoration(color: footerBg),
        children: pctCells,
      ),
    );

    final colWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(128),
    };
    for (var i = 0; i < _kBulletinCols.length; i++) {
      colWidths[i + 1] = const FixedColumnWidth(54);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minW = math.max(constraints.maxWidth, 640.0);
        return SingleChildScrollView(
          key: PageStorageKey<String>('bulletin_hscroll_$pageStorageScope'),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minW),
            child: Table(
              border: TableBorder.all(color: border, width: 0.5),
              columnWidths: colWidths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: subjectRows,
            ),
          ),
        );
      },
    );
  }

  String? _rankSubtitleForYear(String academicYear, List<dynamic> bulletins) {
    final rc = _reportCardForYear(academicYear);
    final pct = _overallPctFromBulletins(bulletins);
    final parts = <String>[];
    if (rc != null && rc['rank'] != null) {
      final r = rc['rank'];
      final ts = rc['total_students'];
      if (ts != null) {
        parts.add('Rang $r / $ts');
      } else {
        parts.add('Rang $r');
      }
    }
    if (pct != null) {
      parts.add('— ${pct.toStringAsFixed(1)} %');
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  Widget _buildBulletinsView() {
    final Map<String, List<dynamic>> bulletinsByYear = {};
    for (var bulletin in _gradeBulletins) {
      // Séparateur « __ » : l'année peut contenir un tiret (ex. 2025-2026).
      final key = '${bulletin['academic_year']}__${bulletin['school_class']}';
      bulletinsByYear.putIfAbsent(key, () => []).add(bulletin);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (bulletinsByYear.isEmpty && _reportCards.isEmpty) {
      return const Center(child: Text('Aucun bulletin disponible'));
    }

    final studentTitle = _displayStudentNameForBulletin();
    var yearIndex = 0;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadBulletinReportData();
      },
      child: ListView(
        padding: ScrollContentPadding.page(context, horizontal: 12, top: 12),
        children: [
          if (bulletinsByYear.isNotEmpty)
            ...bulletinsByYear.entries.map((entry) {
              final parts = entry.key.split('__');
              final academicYear = parts.isNotEmpty ? parts[0] : '';
              final schoolClassId =
                  parts.length > 1 ? int.tryParse(parts[1]) : null;
              final bulletins = entry.value;
              final rankLine = _rankSubtitleForYear(academicYear, bulletins);
              final idx = yearIndex++;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  key: PageStorageKey<String>('bulletin_tile_${entry.key}'),
                  initiallyExpanded: idx == 0,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                  title: Text(
                    studentTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Année scolaire : $academicYear'),
                      if (rankLine != null)
                        Text(
                          rankLine,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final first = bulletins.isNotEmpty && bulletins.first is Map
                                ? Map<String, dynamic>.from(bulletins.first as Map)
                                : null;
                            final studentId = _parseIntId(first?['student']);
                            final ay =
                                first?['academic_year']?.toString() ?? academicYear;
                            final scId =
                                _parseIntId(first?['school_class']) ?? schoolClassId;
                            if (studentId != null) {
                              _downloadOfficialBulletinForStudent(
                                studentId,
                                academicYear: ay,
                                schoolClassId: scId,
                              );
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                          label: const Text('Télécharger le bulletin officiel'),
                        ),
                      ),
                    ),
                    _buildRdcBulletinTable(
                      bulletins,
                      pageStorageScope: entry.key,
                    ),
                  ],
                ),
              );
            }),
          if (_reportCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Bulletins (décision)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._reportCards.map((card) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${card['academic_year'] ?? ''} — ${card['class_name'] ?? ''}'),
                  subtitle: Text('Décision : ${card['decision'] ?? '—'}'),
                  trailing: card['academic_year'] != null
                      ? IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () {
                            final studentId = _parseIntId(card['student']) ??
                                _parseIntId(card['student_id']);
                            if (studentId != null) {
                              _downloadOfficialBulletinForStudent(
                                studentId,
                                academicYear: card['academic_year']?.toString(),
                                schoolClassId: _parseIntId(card['school_class']),
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
                        padding: ScrollContentPadding.page(context),
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
                                  double? score = _toDouble(data['score']);
                                  double? maxScore =
                                      _toDouble(data['max_score'] ?? data['total_points'] ?? 20);
                                  if (data['total_general'] != null || data['subject_period_max'] != null) {
                                    score = _toDouble(data['total_general']) ?? score;
                                    final pm = _toDouble(data['subject_period_max']) ?? 20;
                                    maxScore = pm * 8;
                                  }
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _getGradeColor(score, maxScore),
                                      child: Text(
                                        (score != null && maxScore != null && maxScore != 0)
                                            ? '${((score / maxScore) * 100).round().clamp(0, 999)}'
                                            : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      data['subject_name']?.toString() ??
                                          data['course']?['name']?.toString() ??
                                          'Note',
                                    ),
                                    subtitle: Text(
                                      score != null && maxScore != null && maxScore != 0
                                          ? '${score.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(2)}'
                                          : '—',
                                    ),
                                  );
                                } else if (type == 'assignment') {
                                  final score = _toDouble(data['score']);
                                  final maxPoints = _toDouble(
                                        data['assignment']?['total_points'] ??
                                        data['total_points'] ??
                                        20,
                                      ) ??
                                      20;
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
