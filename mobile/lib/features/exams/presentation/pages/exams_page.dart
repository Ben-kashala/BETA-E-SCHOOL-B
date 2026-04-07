import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  List<dynamic> _exams = [];
  List<dynamic> _filteredExams = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/elearning/quizzes/');
      setState(() {
        _exams = response.data is List<dynamic>
            ? response.data
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredExams = _exams.where((exam) {
        if (_searchQuery.isNotEmpty) {
          final title = (exam['title'] ?? '').toString().toLowerCase();
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
        title: const Text('Mes Examens'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un examen...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredExams.isEmpty
                    ? const Center(child: Text('Aucun examen disponible'))
                    : RefreshIndicator(
                        onRefresh: _loadExams,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredExams.length,
                          itemBuilder: (context, index) {
                            final exam = _filteredExams[index];
                      final startDate = exam['start_date'] != null
                          ? DateTime.parse(exam['start_date'])
                          : null;
                      final endDate = exam['end_date'] != null
                          ? DateTime.parse(exam['end_date'])
                          : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.avatarBackgroundColor,
                            foregroundColor: AppTheme.onAvatarBackgroundColor,
                            child: Icon(Icons.quiz),
                          ),
                          title: Text(exam['title'] ?? 'Sans titre'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (exam['description'] != null)
                                Text(
                                  exam['description'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 8),
                              if (startDate != null)
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16),
                                    const SizedBox(width: 4),
                                    Text(DateFormat('dd/MM/yyyy HH:mm').format(startDate)),
                                  ],
                                ),
                              if (exam['duration'] != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.timer, size: 16),
                                    const SizedBox(width: 4),
                                    Text('Durée: ${exam['duration']} min'),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            context.push('/exams/${exam['id']}');
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
