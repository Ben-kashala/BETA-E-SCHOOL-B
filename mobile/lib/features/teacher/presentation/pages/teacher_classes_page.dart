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
  List<dynamic> _students = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    return [];
  }

  int? _parseClassId(dynamic classItem) {
    if (classItem is! Map) return null;
    final v = classItem['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  int _studentCountForClass(int classId) {
    int n = 0;
    for (final s in _students) {
      if (s is! Map) continue;
      final sc = s['school_class'];
      final sid = sc is int
          ? sc
          : sc is num
              ? sc.toInt()
              : sc is Map
                  ? _parseClassId(sc)
                  : int.tryParse('$sc');
      if (sid == classId) n++;
    }
    return n;
  }

  String _subtitleLine(Map<String, dynamic> c) {
    final level = '${c['level'] ?? ''}'.trim();
    final name = '${c['name'] ?? ''}'.trim();
    final section = '${c['section_name'] ?? ''}'.trim();
    final parts = <String>[];
    if (level.isNotEmpty) parts.add(level);
    if (name.isNotEmpty) parts.add(name);
    if (section.isNotEmpty) parts.add('Section $section');
    return parts.join(' - ');
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/api/schools/classes/'),
        ApiService().get(
          '/api/accounts/students/',
          queryParameters: {'page_size': '500'},
          useCache: false,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = _extractList(results[0].data);
        _students = _extractList(results[1].data);
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

  void _openClass(Map<String, dynamic> classItem) {
    final cid = _parseClassId(classItem);
    if (cid == null) return;
    context.push('/teacher/my-class', extra: cid);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.12);
    final borderColor = Colors.white.withValues(alpha: 0.35);
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    );
    final mutedStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.78),
      fontSize: 12,
      height: 1.35,
    );
    final rowStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.9),
      fontSize: 13,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Text(
                    'Aucune classe disponible.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final crossCount =
                          w >= 900 ? 3 : (w >= 520 ? 2 : 1);
                      return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: crossCount >= 3 ? 1.05 : 0.92,
                    ),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final raw = _classes[index];
                      if (raw is! Map) {
                        return const SizedBox.shrink();
                      }
                      final c = Map<String, dynamic>.from(raw);
                      final id = _parseClassId(c);
                      final count =
                          id != null ? _studentCountForClass(id) : 0;
                      final capacity = c['capacity'];
                      final capStr = capacity is num
                          ? capacity.toInt().toString()
                          : '${capacity ?? '—'}';
                      final year = '${c['academic_year'] ?? '—'}';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openClass(c),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor, width: 1),
                            ),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${c['name'] ?? 'Classe'}',
                                        style: titleStyle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.menu_book_outlined,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      size: 22,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Text(
                                    _subtitleLine(c),
                                    style: mutedStyle,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 16,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$count élève${count != 1 ? 's' : ''}',
                                        style: rowStyle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Capacité: $capStr',
                                  style: rowStyle,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Année: $year',
                                  style: rowStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                    },
                  ),
                ),
    );
  }
}
