import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Colonnes bulletin RDC (même logique que le web).
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

String _formatBulletinVal(dynamic v) {
  if (v == null || '$v'.trim().isEmpty) return '-';
  final n = double.tryParse('$v');
  return n == null ? '-' : n.toStringAsFixed(2);
}

bool _isBelowBase(dynamic value, int mult, int periodMax) {
  final n = double.tryParse('$value');
  if (n == null) return false;
  final max = mult * (periodMax > 0 ? periodMax : 20);
  return max > 0 && n < max * 0.5;
}

int _classLevelOrder(String name) {
  final s = name.toLowerCase();
  if (RegExp(r'\b1(?:ère|re)').hasMatch(s)) return 1;
  if (RegExp(r'\b2(?:ème|e)\b').hasMatch(s)) return 2;
  if (RegExp(r'\b3(?:ème|e)\b').hasMatch(s)) return 3;
  if (RegExp(r'\b4(?:ème|e)\b').hasMatch(s)) return 4;
  if (RegExp(r'\b5(?:ème|e)\b').hasMatch(s)) return 5;
  if (RegExp(r'\b6(?:ème|e)\b').hasMatch(s)) return 6;
  return 999;
}

List<dynamic> _extractList(dynamic data) {
  if (data is List) return data;
  if (data is Map && data['results'] is List) {
    return data['results'] as List;
  }
  return [];
}

class TeacherMyClassPage extends ConsumerStatefulWidget {
  const TeacherMyClassPage({super.key, this.initialClassId});

  final int? initialClassId;

  @override
  ConsumerState<TeacherMyClassPage> createState() => _TeacherMyClassPageState();
}

class _TeacherMyClassPageState extends ConsumerState<TeacherMyClassPage> {
  List<dynamic> _classes = [];
  int? _selectedClassId;
  String _academicYear = '';
  List<String> _yearStrings = [];
  String? _apiCurrentYear;

  String _searchQuery = '';
  int? _expandedStudentId;

  List<dynamic> _ranking = [];
  String? _rankingSchoolClassName;
  List<dynamic> _bulletins = [];

  bool _loadingInit = true;
  bool _loadingTables = false;
  bool _promoting = false;

  late final TextEditingController _manualYearController;

  @override
  void initState() {
    super.initState();
    final y = DateTime.now().year;
    _academicYear = '$y-${y + 1}';
    _manualYearController = TextEditingController(text: _academicYear);
    _bootstrap();
  }

  @override
  void dispose() {
    _manualYearController.dispose();
    super.dispose();
  }

  String _errorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final main = data['message'] ?? data['error'] ?? data['detail'];
        final detail = data['detail'];
        if (main != null && '$main'.trim().isNotEmpty) {
          if (detail != null && '$detail'.trim().isNotEmpty && '$detail' != '$main') {
            return '$main\n\n$detail';
          }
          return '$main';
        }
      }
      final code = e.response?.statusCode;
      if (code == 403) return 'Action non autorisée pour votre compte.';
      if (code == 400) {
        return 'Action invalide. Vérifiez la configuration de promotion (classe suivante, année suivante).';
      }
    }
    return e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
  }

  Future<void> _showPopup({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingInit = true;
      _classes = [];
    });
    try {
      await Future.wait([_loadClasses(), _loadAcademicYears()]);
      if (!mounted) return;
      _pickDefaultClass();
      if (_selectedClassId != null && _academicYear.trim().isNotEmpty) {
        await _loadRankingAndBulletins();
      }
    } finally {
      if (mounted) setState(() => _loadingInit = false);
    }
  }

  Future<void> _loadClasses() async {
    final res = await ApiService().get('/api/schools/classes/my_titular/');
    if (!mounted) return;
    setState(() {
      _classes = _extractList(res.data);
    });
  }

  Future<void> _loadAcademicYears() async {
    try {
      final res =
          await ApiService().get('/api/academics/academic-years/available/');
      if (!mounted) return;
      final data = res.data;
      if (data is Map) {
        final years = data['years'];
        _apiCurrentYear = data['current']?.toString();
        if (years is List) {
          _yearStrings = years.map((e) => '$e').toList();
        }
        if (_yearStrings.isNotEmpty) {
          final cur = _apiCurrentYear;
          if (cur != null && _yearStrings.contains(cur)) {
            _academicYear = cur;
          } else if (!_yearStrings.contains(_academicYear)) {
            _academicYear = _yearStrings.first;
          }
        }
        _manualYearController.text = _academicYear;
      }
    } catch (_) {
      /* saisie libre */
    }
  }

  void _pickDefaultClass() {
    if (_classes.isEmpty) return;
    final sorted = List<dynamic>.from(_classes)
      ..sort((a, b) {
        final na = '${a is Map ? a['name'] : ''}';
        final nb = '${b is Map ? b['name'] : ''}';
        return _classLevelOrder(na).compareTo(_classLevelOrder(nb));
      });
    final want = widget.initialClassId;
    if (want != null) {
      for (final c in sorted) {
        if (c is Map && _asInt(c['id']) == want) {
          _selectedClassId = want;
          final ay = c['academic_year']?.toString();
          if (ay != null &&
              ay.isNotEmpty &&
              (_yearStrings.isEmpty || _yearStrings.contains(ay))) {
            _academicYear = ay;
            _manualYearController.text = _academicYear;
          }
          return;
        }
      }
    }
    final first = sorted.first;
    if (first is Map) {
      _selectedClassId = _asInt(first['id']);
      final ay = first['academic_year']?.toString();
      if (ay != null &&
          ay.isNotEmpty &&
          (_yearStrings.isEmpty || _yearStrings.contains(ay))) {
        _academicYear = ay;
        _manualYearController.text = _academicYear;
      }
    }
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  Map<int, Map<int, dynamic>> _bulletinsByStudent() {
    final m = <int, Map<int, dynamic>>{};
    for (final b in _bulletins) {
      if (b is! Map) continue;
      final sid = _asInt(b['student']);
      final subj = _asInt(b['subject']);
      if (sid == null || subj == null) continue;
      m.putIfAbsent(sid, () => {})[subj] = b;
    }
    return m;
  }

  List<dynamic> get _filteredRanking {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return List<dynamic>.from(_ranking);
    return _ranking.where((r) {
      if (r is! Map) return false;
      final n =
          '${r['student_name'] ?? r['user_name'] ?? ''}'.toLowerCase();
      final mat = '${r['matricule'] ?? ''}'.toLowerCase();
      return n.contains(q) || mat.contains(q);
    }).toList();
  }

  Future<void> _loadRankingAndBulletins() async {
    final cid = _selectedClassId;
    final ay = _academicYear.trim();
    if (cid == null || ay.isEmpty) return;

    setState(() => _loadingTables = true);
    try {
      final bulletinsRes = await ApiService().get(
        '/api/academics/grade-bulletins/',
        queryParameters: {
          'school_class': '$cid',
          'academic_year': ay,
          'page_size': '500',
        },
        useCache: false,
      );
      final rankRes = await ApiService().get(
        '/api/academics/grade-bulletins/class_ranking/',
        queryParameters: {
          'school_class': '$cid',
          'academic_year': ay,
        },
        useCache: false,
      );
      if (!mounted) return;
      setState(() {
        _bulletins = _extractList(bulletinsRes.data);
        final rd = rankRes.data;
        if (rd is Map) {
          _rankingSchoolClassName = rd['school_class']?.toString();
          _ranking = rd['results'] is List
              ? List<dynamic>.from(rd['results'] as List)
              : [];
        } else {
          _ranking = [];
          _rankingSchoolClassName = null;
        }
        _loadingTables = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ranking = [];
          _bulletins = [];
          _loadingTables = false;
        });
        await _showPopup(
          title: 'Information',
          message: _errorMessage(e).isEmpty
              ? 'Impossible de charger le classement ou les bulletins.'
              : _errorMessage(e),
          icon: Icons.info_outline,
          color: AppTheme.warningColor,
        );
      }
    }
  }

  Future<void> _promoteAdmitted() async {
    final cid = _selectedClassId;
    if (cid == null) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmer'),
            content: const Text(
              'Lancer la promotion des élèves pour cette classe ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Promouvoir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    setState(() => _promoting = true);
    try {
      final res = await ApiService().post(
        '/api/schools/classes/$cid/promote_admitted/',
      );
      if (!mounted) return;
      final msg = res.data is Map
          ? (res.data['message']?.toString() ??
              '${res.data['promoted'] ?? 0} élève(s) promu(s).')
          : 'Promotion enregistrée.';
      await _showPopup(
        title: 'Succès',
        message: msg,
        icon: Icons.check_circle_outline,
        color: AppTheme.successColor,
      );
      await _loadClasses();
      await _loadRankingAndBulletins();
    } catch (e) {
      await _showPopup(
        title: 'Avertissement',
        message: _errorMessage(e),
        icon: Icons.warning_amber_rounded,
        color: AppTheme.warningColor,
      );
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  Future<void> _downloadBulletin(int studentId) async {
    final cid = _selectedClassId;
    final ay = _academicYear.trim();
    if (cid == null || ay.isEmpty) return;
    try {
      final baseUrl = ApiService().baseUrl;
      final suffix = baseUrl.endsWith('/') ? '' : '/';
      final url =
          '$baseUrl${suffix}api/auth/students/$studentId/bulletin_pdf/?school_class=$cid&academic_year=${Uri.encodeComponent(ay)}';

      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/downloads/bulletins');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeYear = ay.replaceAll(RegExp(r'[^0-9-]'), '_');
      final filePath = '${dir.path}/bulletin_${studentId}_$safeYear.pdf';

      await ApiService().downloadFile(url, filePath);

      if (mounted) {
        await _showPopup(
          title: 'Téléchargement',
          message: 'Bulletin enregistré avec succès.',
          icon: Icons.download_done_outlined,
          color: AppTheme.successColor,
        );
      }
    } catch (e) {
      await _showPopup(
        title: 'Erreur',
        message: _errorMessage(e),
        icon: Icons.error_outline,
        color: AppTheme.errorColor,
      );
    }
  }

  Map<String, dynamic>? _selectedClassMap() {
    for (final c in _classes) {
      if (c is Map && _asInt(c['id']) == _selectedClassId) {
        return Map<String, dynamic>.from(c);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma classe (Titulariat)'),
      ),
      body: _loadingInit
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _bootstrap,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _filtersCard(context),
                  const SizedBox(height: 16),
                  if (_classes.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Vous n\'êtes titulaire d\'aucune classe. '
                          'L\'administrateur peut vous désigner comme titulaire sur la fiche de la classe.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    )
                  else if (_selectedClassId == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Sélectionnez une classe.'),
                      ),
                    )
                  else ...[
                    _rankingCard(context),
                    const SizedBox(height: 16),
                    _studentsBulletinCard(context),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _filtersCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtres',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedClassId,
              decoration: const InputDecoration(
                labelText: 'Classe',
                border: OutlineInputBorder(),
              ),
              items: _classes.map((c) {
                if (c is! Map) return null;
                final id = _asInt(c['id']);
                if (id == null) return null;
                final name = '${c['name'] ?? 'Classe'}';
                final ay = c['academic_year'];
                final label =
                    ay != null && '$ay'.isNotEmpty ? '$name ($ay)' : name;
                return DropdownMenuItem(value: id, child: Text(label));
              }).whereType<DropdownMenuItem<int>>().toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _selectedClassId = id;
                  _expandedStudentId = null;
                  final cm = _selectedClassMap();
                  final ay = cm?['academic_year']?.toString();
                  if (ay != null &&
                      ay.isNotEmpty &&
                      (_yearStrings.isEmpty || _yearStrings.contains(ay))) {
                    _academicYear = ay;
                    _manualYearController.text = _academicYear;
                  }
                });
                _loadRankingAndBulletins();
              },
            ),
            const SizedBox(height: 12),
            if (_yearStrings.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue:
                    _yearStrings.contains(_academicYear) ? _academicYear : null,
                decoration: const InputDecoration(
                  labelText: 'Année scolaire',
                  border: OutlineInputBorder(),
                ),
                items: _yearStrings
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (y) {
                  if (y == null) return;
                  setState(() {
                    _academicYear = y;
                    _manualYearController.text = y;
                    _expandedStudentId = null;
                  });
                  _loadRankingAndBulletins();
                },
              )
            else
              TextField(
                controller: _manualYearController,
                decoration: const InputDecoration(
                  labelText: 'Année scolaire',
                  hintText: 'ex. 2025-2026',
                  border: OutlineInputBorder(),
                ),
                onEditingComplete: () {
                  final v = _manualYearController.text.trim();
                  setState(() => _academicYear = v);
                  _loadRankingAndBulletins();
                },
                onSubmitted: (v) {
                  setState(() => _academicYear = v.trim());
                  _loadRankingAndBulletins();
                },
              ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Recherche élève',
                hintText: 'Nom, prénom, matricule...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankingCard(BuildContext context) {
    final sel = _selectedClassMap();
    final titleClass = _rankingSchoolClassName ??
        (sel != null ? '${sel['name']}' : 'Classe $_selectedClassId');
    final filtered = _filteredRanking;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Classement — $titleClass (${_academicYear.trim()})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      (_promoting || _loadingTables) ? null : _promoteAdmitted,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.moduleButtonColor,
                    foregroundColor: AppTheme.onAvatarBackgroundColor,
                  ),
                  icon: _promoting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.school, size: 18),
                  label: const Text(
                    'Promouvoir les admis (≥50 %)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingTables)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _searchQuery.trim().isEmpty
                      ? 'Aucun élève ou aucune note pour cette classe et cette année.'
                      : 'Aucun élève ne correspond à la recherche.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  columns: const [
                    DataColumn(label: Text('Rang')),
                    DataColumn(label: Text('Élève')),
                    DataColumn(
                      label: Text('Total points'),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Pourcentage'),
                      numeric: true,
                    ),
                  ],
                  rows: filtered.map((r) {
                    if (r is! Map) {
                      return const DataRow(cells: [
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                      ]);
                    }
                    final pts = r['total_points'];
                    final pct = r['percentage'];
                    return DataRow(
                      cells: [
                        DataCell(Text('${r['rank'] ?? ''}')),
                        DataCell(Text(
                          '${r['student_name'] ?? r['user_name'] ?? '—'}',
                        )),
                        DataCell(Text(
                          pts != null
                              ? double.tryParse('$pts')?.toStringAsFixed(2) ??
                                  '$pts'
                              : '-',
                        )),
                        DataCell(Text(
                          pct != null
                              ? '${double.tryParse('$pct')?.toStringAsFixed(2) ?? pct} %'
                              : '-',
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _studentsBulletinCard(BuildContext context) {
    final byStudent = _bulletinsByStudent();
    final filtered = _filteredRanking;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Élèves et évolution des notes sur le bulletin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loadingTables
                      ? null
                      : () => _loadRankingAndBulletins(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingTables)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun élève à afficher.'),
              )
            else
              ...filtered.map((r) {
                if (r is! Map) return const SizedBox.shrink();
                final sid = _asInt(r['student_id']);
                if (sid == null) return const SizedBox.shrink();
                final expanded = _expandedStudentId == sid;
                final name =
                    '${r['student_name'] ?? r['user_name'] ?? 'Élève #$sid'}';
                final rank = r['rank'];
                final pct = r['percentage'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(name),
                        subtitle: rank != null
                            ? Text(
                                'Rang $rank — ${double.tryParse('$pct')?.toStringAsFixed(1) ?? pct} %',
                              )
                            : null,
                        trailing: Icon(
                          expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onTap: () {
                          setState(() {
                            _expandedStudentId = expanded ? null : sid;
                          });
                        },
                      ),
                      if (expanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextButton.icon(
                                onPressed: () => _downloadBulletin(sid),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Télécharger le bulletin PDF'),
                              ),
                              const SizedBox(height: 8),
                              _bulletinDetailTable(context, byStudent[sid] ?? {}),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _bulletinDetailTable(
    BuildContext context,
    Map<int, dynamic> stBulletins,
  ) {
    if (stBulletins.isEmpty) {
      return const Text(
        'Aucune note enregistrée pour cette année.',
        style: TextStyle(fontStyle: FontStyle.italic),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            children: [
              const Padding(
                padding: EdgeInsets.all(6),
                child: Text('Matière', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ..._kBulletinCols.map(
                (c) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    c.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          ...stBulletins.entries.map((e) {
            final g = e.value;
            if (g is! Map) return const TableRow(children: []);
            final pm = _asInt(g['subject_period_max']) ?? 20;
            final subjName =
                '${g['subject_name'] ?? 'Matière #${e.key}'}';
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(subjName, style: const TextStyle(fontSize: 12)),
                ),
                ..._kBulletinCols.map((c) {
                  final below =
                      _isBelowBase(g[c.key], c.mult, pm);
                  final t = _formatBulletinVal(g[c.key]);
                  return Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      t,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: below ? AppTheme.errorColor : null,
                        fontWeight: below ? FontWeight.w600 : null,
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
          TableRow(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
            ),
            children: [
              const Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  'Pourcentage',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              ..._kBulletinCols.map((c) {
                final list = stBulletins.values.whereType<Map>().toList();
                double sumPoints = 0;
                double sumMax = 0;
                for (final g in list) {
                  sumPoints += double.tryParse('${g[c.key]}') ?? 0;
                  final pm = _asInt(g['subject_period_max']) ?? 20;
                  sumMax += c.mult * pm;
                }
                final pctNum = sumMax > 0 ? (sumPoints / sumMax) * 100 : null;
                final txt =
                    pctNum != null ? '${pctNum.toStringAsFixed(1)} %' : '-';
                final below = pctNum != null && pctNum < 50;
                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    txt,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: below ? AppTheme.errorColor : null,
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
