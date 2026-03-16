import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import 'parent_tutoring_page.dart';

class TutoringPage extends ConsumerStatefulWidget {
  const TutoringPage({super.key});

  @override
  ConsumerState<TutoringPage> createState() => _TutoringPageState();
}

class _TutoringPageState extends ConsumerState<TutoringPage> {
  List<dynamic> _tutoringSessions = [];
  List<dynamic> _filteredSessions = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTutoringSessions();
  }

  Future<void> _loadTutoringSessions() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/tutoring/reports/', useCache: false);
      setState(() {
        _tutoringSessions = response.data is List<dynamic> ? response.data : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredSessions = _tutoringSessions.where((session) {
        if (_searchQuery.isNotEmpty) {
          final title = (session['title'] ?? '').toString().toLowerCase();
          final progress = (session['academic_progress'] ?? '').toString().toLowerCase();
          return title.contains(_searchQuery.toLowerCase()) || progress.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  Future<void> _showCreateReport() async {
    List<dynamic> students = [];
    try {
      final s = await ApiService().get('/api/auth/students/', useCache: false);
      students = s.data is List ? s.data : (s.data['results'] ?? []);
    } catch (_) {}

    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final academicProgress = TextEditingController();
    final recommendations = TextEditingController();
    final behaviorObs = TextEditingController();
    int? studentId = students.isNotEmpty ? (students.first['id'] as int) : null;
    DateTime periodStart = DateTime.now();
    DateTime periodEnd = DateTime.now().add(const Duration(days: 30));
    bool isDraft = true;
    bool loading = false;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nouveau rapport d\'encadrement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Titre *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: studentId,
                      decoration: const InputDecoration(labelText: 'Élève *'),
                      items: students.map((s) {
                        final name = s['user_name'] ?? '${s['user']?['first_name'] ?? ''} ${s['user']?['last_name'] ?? ''}'.trim();
                        return DropdownMenuItem<int>(value: s['id'] as int, child: Text(name.isEmpty ? 'Élève' : name));
                      }).toList(),
                      onChanged: (v) => setModalState(() => studentId = v),
                      validator: (v) => v == null ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Début période'),
                      subtitle: Text('${periodStart.day}/${periodStart.month}/${periodStart.year}'),
                      onTap: () async {
                        final d = await showDatePicker(context: ctx, initialDate: periodStart, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (d != null) setModalState(() => periodStart = d);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fin période'),
                      subtitle: Text('${periodEnd.day}/${periodEnd.month}/${periodEnd.year}'),
                      onTap: () async {
                        final d = await showDatePicker(context: ctx, initialDate: periodEnd, firstDate: periodStart, lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (d != null) setModalState(() => periodEnd = d);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: academicProgress,
                      decoration: const InputDecoration(labelText: 'Progrès scolaire *', alignLabelWithHint: true),
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: behaviorObs,
                      decoration: const InputDecoration(labelText: 'Observations comportementales', alignLabelWithHint: true),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: recommendations,
                      decoration: const InputDecoration(labelText: 'Recommandations *', alignLabelWithHint: true),
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Brouillon'),
                      value: isDraft,
                      onChanged: (v) => setModalState(() => isDraft = v),
                    ),
                    const SizedBox(height: 24),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => loading = true);
                                try {
                                  await ApiService().post('/api/tutoring/reports/', data: {
                                    'title': title.text.trim(),
                                    'student': studentId,
                                    'report_period_start': '${periodStart.year}-${periodStart.month.toString().padLeft(2, '0')}-${periodStart.day.toString().padLeft(2, '0')}',
                                    'report_period_end': '${periodEnd.year}-${periodEnd.month.toString().padLeft(2, '0')}-${periodEnd.day.toString().padLeft(2, '0')}',
                                    'academic_progress': academicProgress.text.trim(),
                                    'behavior_observations': behaviorObs.text.trim().isEmpty ? null : behaviorObs.text.trim(),
                                    'recommendations': recommendations.text.trim(),
                                    'is_draft': isDraft,
                                  });
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Rapport enregistré.')));
                                    _loadTutoringSessions();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')));
                                }
                              },
                              child: const Text('Enregistrer'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showReportDetail(dynamic report) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(report['title'] ?? 'Rapport'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (report['student_name'] != null) Text('Élève: ${report['student_name']}'),
              if (report['report_period_start'] != null) Text('Période: ${report['report_period_start']} — ${report['report_period_end'] ?? ''}'),
              const SizedBox(height: 8),
              if (report['academic_progress'] != null) ...[
                const Text('Progrès scolaire', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(report['academic_progress']),
                const SizedBox(height: 8),
              ],
              if (report['recommendations'] != null) ...[
                const Text('Recommandations', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(report['recommendations']),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isParent = user?.isParent ?? false;
    
    // Si parent, utiliser la page dédiée avec messages et rapports
    if (isParent) {
      return const ParentTutoringPage();
    }
    
    // Sinon, page normale pour enseignants
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encadrement Domicile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateReport,
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher une session...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.school_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucune session d\'encadrement',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTutoringSessions,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredSessions.length,
                          itemBuilder: (context, index) {
                            final session = _filteredSessions[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.teal,
                                  child: Icon(Icons.school, color: Colors.white),
                                ),
                                title: Text(session['title'] ?? 'Rapport'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (session['student_name'] != null)
                                      Text('Élève: ${session['student_name']}'),
                                    if (session['report_period_start'] != null)
                                      Text('Période: ${session['report_period_start']} — ${session['report_period_end'] ?? ''}'),
                                    if (session['is_draft'] == true)
                                      const Text('Brouillon', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showReportDetail(session),
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
