import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/network/api_service.dart';
import '../widgets/attendance_week_chart_widget.dart';
import '../widgets/progress_charts_widget.dart';

class ParentPresencePage extends ConsumerStatefulWidget {
  const ParentPresencePage({super.key});

  @override
  ConsumerState<ParentPresencePage> createState() => _ParentPresencePageState();
}

class _ChildOption {
  final int id;
  final String name;

  const _ChildOption({required this.id, required this.name});
}

class _ParentPresencePageState extends ConsumerState<ParentPresencePage> {
  List<_ChildOption> _children = [];
  int? _selectedStudentId;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _filterDay;
  List<Map<String, dynamic>> _weeks = [];
  Map<String, dynamic>? _dayDetail;
  /// Moyennes du tableau de bord parent (API `parent_dashboard`), par id élève.
  Map<int, double?> _averageScoreByStudentId = {};
  /// Présences par semaine « 4 dernières semaines » (même donnée que l’ancien dashboard parent).
  Map<int, List<Map<String, dynamic>>> _rollingAttendanceByStudentId = {};
  List<Map<String, dynamic>> _grades = [];
  bool _loadingChildren = true;
  bool _loadingChart = false;
  String? _error;

  static const _monthNames = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingChildren = true;
      _error = null;
    });
    try {
      final response = await ApiService().get(
        '/api/auth/students/parent_dashboard/',
        useCache: false,
      );
      final data = response.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] != null
              ? data['results'] as List
              : <dynamic>[]);

      final options = <_ChildOption>[];
      final averages = <int, double?>{};
      final rolling = <int, List<Map<String, dynamic>>>{};
      for (final item in list) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final identity = (row['identity'] as Map?) ?? row;
        final rawId = identity['id'] ?? identity['pk'];
        final int? sid = rawId is int
            ? rawId
            : rawId is num
                ? rawId.toInt()
                : num.tryParse(rawId?.toString().trim() ?? '')?.toInt();
        if (sid == null) continue;
        final userData = identity['user'];
        final userName = userData is Map
            ? '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''} ${userData['middle_name'] ?? ''}'
                .trim()
            : (identity['user_name'] as String? ?? '');
        options.add(_ChildOption(
          id: sid,
          name: userName.isEmpty ? 'Enfant #$sid' : userName,
        ));
        final avgRaw = row['average_score'];
        if (avgRaw is num) {
          averages[sid] = avgRaw.toDouble();
        } else if (avgRaw != null) {
          averages[sid] = double.tryParse(avgRaw.toString());
        } else {
          averages[sid] = null;
        }
        rolling[sid] = _weekMapsFromList(row['attendance_by_week']);
      }

      if (!mounted) return;
      setState(() {
        _children = options;
        _averageScoreByStudentId = averages;
        _rollingAttendanceByStudentId = rolling;
        _selectedStudentId =
            options.isEmpty ? null : (_selectedStudentId ?? options.first.id);
        _loadingChildren = false;
      });
      if (_selectedStudentId != null) {
        await _loadWeekly();
        await _loadGradesForStudent(_selectedStudentId!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingChildren = false;
          _error = 'Impossible de charger les enfants.';
        });
      }
    }
  }

  Future<void> _loadWeekly() async {
    final sid = _selectedStudentId;
    if (sid == null) return;
    setState(() {
      _loadingChart = true;
      _error = null;
    });
    try {
      final qp = <String, dynamic>{
        'student': sid.toString(),
        'year': _focusedMonth.year.toString(),
        'month': _focusedMonth.month.toString(),
      };
      if (_filterDay != null) {
        final d = _filterDay!;
        qp['date'] =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      final response = await ApiService().get(
        '/api/auth/students/parent-presence-weeks/',
        queryParameters: qp,
        useCache: false,
      );
      final data = response.data;
      final rawWeeks = data is Map ? data['weeks'] : null;
      final weeks = rawWeeks is List
          ? rawWeeks.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      Map<String, dynamic>? dayDetail;
      final rd = data is Map ? data['day_detail'] : null;
      if (rd is Map) {
        dayDetail = Map<String, dynamic>.from(rd);
      }
      if (mounted) {
        setState(() {
          _weeks = weeks;
          _dayDetail = dayDetail;
          _loadingChart = false;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      // API peut renvoyer 404 JSON avec weeks: [] (élève non autorisé) — afficher le graphique vide plutôt qu’un écran d’erreur.
      if (data is Map && data['weeks'] is List) {
        final rawWeeks = data['weeks'] as List;
        final weeks = rawWeeks
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        Map<String, dynamic>? dayDetail;
        final rd = data['day_detail'];
        if (rd is Map) {
          dayDetail = Map<String, dynamic>.from(rd);
        }
        setState(() {
          _loadingChart = false;
          _error = null;
          _weeks = weeks;
          _dayDetail = dayDetail;
        });
        return;
      }
      setState(() {
        _loadingChart = false;
        _error = dioErrorMessage(e);
        _weeks = [];
        _dayDetail = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingChart = false;
          _error = 'Impossible de charger les présences.';
          _weeks = [];
          _dayDetail = null;
        });
      }
    }
  }

  Future<void> _loadGradesForStudent(int sid) async {
    try {
      final res = await ApiService().get<dynamic>(
        '/api/academics/grades/',
        queryParameters: {'student': sid.toString()},
        useCache: false,
      );
      final data = res.data;
      final raw = data is List
          ? data
          : (data is Map && data['results'] != null)
              ? data['results']
              : <dynamic>[];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map<String, dynamic>) {
            list.add(e);
          } else if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }
      if (!mounted) return;
      setState(() => _grades = list);
    } catch (_) {
      if (mounted) setState(() => _grades = []);
    }
  }

  String _monthLabel(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.year}';

  String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  List<Map<String, dynamic>> _weekMapsFromList(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(e);
      } else if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _rollingWeeksForSelected() {
    final id = _selectedStudentId;
    if (id == null) return [];
    return _rollingAttendanceByStudentId[id] ?? [];
  }

  String _statusFr(String? code) {
    switch (code) {
      case 'PRESENT':
        return 'Présent';
      case 'ABSENT':
        return 'Absent';
      case 'LATE':
        return 'En retard';
      case 'EXCUSED':
        return 'Excusé';
      default:
        return code ?? '—';
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() {
        _focusedMonth = DateTime(picked.year, picked.month);
      });
      await _loadWeekly();
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDay ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _filterDay = picked);
      await _loadWeekly();
    }
  }

  void _clearDay() {
    setState(() => _filterDay = null);
    _loadWeekly();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Présences'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadChildren();
          if (_selectedStudentId != null) {
            await _loadWeekly();
            await _loadGradesForStudent(_selectedStudentId!);
          }
        },
        child: _loadingChildren
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: ScrollContentPadding.page(context, top: 80, trailing: 16),
                children: const [
                  SizedBox(height: 40),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _children.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: ScrollContentPadding.page(context, horizontal: 24, top: 24),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      if (_error == null)
                        Text(
                          'Aucun enfant inscrit.',
                          style: theme.textTheme.bodyLarge,
                        ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: ScrollContentPadding.page(context, top: 20),
                    children: [
                      Text(
                        'Filtres',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int>(
                                value: _selectedStudentId,
                                decoration: const InputDecoration(
                                  labelText: 'Enfant',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                items: _children
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c.id,
                                        child: Text(c.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  setState(() => _selectedStudentId = v);
                                  await _loadWeekly();
                                  await _loadGradesForStudent(v);
                                },
                              ),
                              const Divider(height: 24),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Mois'),
                                subtitle: Text(_monthLabel(_focusedMonth)),
                                trailing: const Icon(Icons.calendar_month),
                                onTap: _pickMonth,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Jour (optionnel)'),
                                subtitle: Text(
                                  _filterDay != null
                                      ? _dayLabel(_filterDay!)
                                      : 'Toutes les semaines du mois',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_filterDay != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: _clearDay,
                                        tooltip: 'Effacer la date',
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.today_outlined),
                                      onPressed: _pickDay,
                                      tooltip: 'Choisir une date',
                                    ),
                                  ],
                                ),
                                onTap: _pickDay,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Présences et notes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aperçu (4 dernières semaines)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_rollingWeeksForSelected().isNotEmpty)
                        AttendanceWeekChartWidget(
                          attendanceData: _rollingWeeksForSelected(),
                        )
                      else
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Aucune donnée de présence pour cet aperçu.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Présences du mois (${_monthLabel(_focusedMonth)})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingChart)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_weeks.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                _error != null
                                    ? _error!
                                    : 'Aucune semaine à afficher pour ce mois.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _error != null
                                      ? theme.colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          AttendanceWeekChartWidget(attendanceData: _weeks),
                          if (_weeks.every((w) =>
                              ((w['total'] as num?)?.toInt() ?? 0) == 0))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Aucune saisie de présence enregistrée pour les semaines affichées.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Évolution des notes et moyenne',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ProgressChartsWidget(
                        attendanceData: const [],
                        gradesData: _grades,
                        averageScore: _selectedStudentId != null
                            ? _averageScoreByStudentId[_selectedStudentId!]
                            : null,
                      ),
                      if (_filterDay != null && !_loadingChart) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Détail du jour',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_dayDetail != null)
                          _buildDayDetailCard(context, _dayDetail!)
                        else
                          Text(
                            'Sélectionnez une date valide.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _buildDayDetailCard(
    BuildContext context,
    Map<String, dynamic> dd,
  ) {
    final theme = Theme.of(context);
    final records = dd['records'];
    final list = records is List ? records : <dynamic>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dd['date']?.toString() ?? '',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _chip(theme, 'Présents', dd['present'], Colors.green),
                _chip(theme, 'Absents', dd['absent'], Colors.red),
                _chip(theme, 'Retards', dd['late'], Colors.orange),
                _chip(theme, 'Excusés', dd['excused'], Colors.blue),
              ],
            ),
            if (list.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Par enregistrement',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              ...list.map((raw) {
                final r = raw is Map
                    ? Map<String, dynamic>.from(raw)
                    : <String, dynamic>{};
                final subj = r['subject_name']?.toString();
                final cls = r['class_name']?.toString();
                final st = r['status']?.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (subj != null && subj.isNotEmpty) subj,
                            if (cls != null && cls.isNotEmpty) cls,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        _statusFr(st),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(
    ThemeData theme,
    String label,
    dynamic value,
    Color color,
  ) {
    final n = (value is num) ? value.toInt() : int.tryParse('$value') ?? 0;
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
      label: Text('$label : $n'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
