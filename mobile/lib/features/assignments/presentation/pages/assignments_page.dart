import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../students/presentation/widgets/student_bottom_nav.dart';

class AssignmentsPage extends ConsumerStatefulWidget {
  const AssignmentsPage({super.key});

  @override
  ConsumerState<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends ConsumerState<AssignmentsPage> {
  List<dynamic> _assignments = [];
  List<dynamic> _filteredAssignments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/elearning/assignments/');
      setState(() {
        _assignments = response.data is List<dynamic>
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
      _filteredAssignments = _assignments.where((assignment) {
        // Recherche
        if (_searchQuery.isNotEmpty) {
          final title = (assignment['title'] ?? '').toString().toLowerCase();
          if (!title.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Filtre statut
        if (_selectedStatus != null) {
          if ((assignment['status'] ?? 'pending') != _selectedStatus) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'submitted':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'overdue':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).user?.role;
    final path = GoRouterState.of(context).uri.path;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Devoirs'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un devoir...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'status',
                label: 'Statut',
                values: [
                  FilterValue(value: 'pending', label: 'En attente'),
                  FilterValue(value: 'submitted', label: 'Soumis'),
                  FilterValue(value: 'overdue', label: 'En retard'),
                ],
                selectedValue: _selectedStatus,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() => _selectedStatus = filters['status']);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAssignments.isEmpty
                    ? const Center(child: Text('Aucun devoir disponible'))
                    : RefreshIndicator(
                        onRefresh: _loadAssignments,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAssignments.length,
                          itemBuilder: (context, index) {
                            final assignment = _filteredAssignments[index];
                      final dueDate = assignment['due_date'] != null
                          ? DateTime.parse(assignment['due_date'])
                          : null;
                      final status = assignment['status'] ?? 'pending';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: _getStatusColor(status),
                            child: const Icon(Icons.assignment, color: Colors.white),
                          ),
                          title: Text(assignment['title'] ?? 'Sans titre'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (assignment['description'] != null)
                                Text(
                                  assignment['description'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 8),
                              if (dueDate != null)
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Échéance: ${DateFormat('dd/MM/yyyy').format(dueDate)}',
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            context.push('/assignments/${assignment['id']}');
                          },
                        ),
                      );
                            },
                          ),
                        ),
                      ),
        ],
      ),
      bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
          ? const StudentBottomNav()
          : null,
    );
  }
}
