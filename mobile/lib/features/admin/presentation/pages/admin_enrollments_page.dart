import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';

class AdminEnrollmentsPage extends ConsumerStatefulWidget {
  const AdminEnrollmentsPage({super.key});

  @override
  ConsumerState<AdminEnrollmentsPage> createState() => _AdminEnrollmentsPageState();
}

class _AdminEnrollmentsPageState extends ConsumerState<AdminEnrollmentsPage> {
  List<dynamic> _enrollments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEnrollments();
  }

  Future<void> _loadEnrollments() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/enrollment/applications/');
      setState(() {
        _enrollments = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approveEnrollment(int id) async {
    try {
      await ApiService().post('/api/enrollment/applications/$id/approve/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription approuvée')),
        );
        _loadEnrollments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _rejectEnrollment(int id) async {
    try {
      await ApiService().post('/api/enrollment/applications/$id/reject/', data: {
        'notes': 'Rejeté depuis l\'application mobile',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription rejetée')),
        );
        _loadEnrollments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return 'En attente';
      case 'APPROVED':
        return 'Approuvée';
      case 'REJECTED':
        return 'Rejetée';
      case 'COMPLETED':
        return 'Complétée';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.orange;
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      case 'COMPLETED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showEnrollmentDetail(BuildContext context, Map<String, dynamic> enrollment) {
    final name = '${enrollment['first_name'] ?? ''} ${enrollment['last_name'] ?? ''}'.trim();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name.isEmpty ? 'Détail inscription' : name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Classe demandée: ${enrollment['requested_class_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Statut: ${_getStatusLabel(enrollment['status'] ?? '')}'),
              if (enrollment['created_at'] != null) ...[
                const SizedBox(height: 8),
                Text('Date: ${enrollment['created_at']}'),
              ],
              if (enrollment['notes'] != null && '${enrollment['notes']}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Notes: ${enrollment['notes']}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          if (enrollment['status'] == 'PENDING') ...[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _approveEnrollment(enrollment['id'] as int);
              },
              child: const Text('Approuver'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _rejectEnrollment(enrollment['id'] as int);
              },
              child: const Text('Rejeter'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inscriptions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/admin/enrollments/new'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _enrollments.isEmpty
              ? const Center(child: Text('Aucune inscription'))
              : RefreshIndicator(
                  onRefresh: _loadEnrollments,
                  child: ListView.builder(
                    itemCount: _enrollments.length,
                    itemBuilder: (context, index) {
                      final enrollment = _enrollments[index];
                      final status = enrollment['status'] ?? 'PENDING';
                      final name = '${enrollment['first_name'] ?? ''} ${enrollment['last_name'] ?? ''}'.trim();
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getStatusColor(status),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(name.isEmpty ? 'Élève' : name),
                          subtitle: Text('Classe: ${enrollment['requested_class_name'] ?? 'N/A'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(_getStatusLabel(status)),
                                backgroundColor: _getStatusColor(status).withOpacity(0.2),
                                labelStyle: TextStyle(color: _getStatusColor(status)),
                              ),
                              if (status == 'PENDING') ...[
                                IconButton(
                                  icon: const Icon(Icons.check, color: Colors.green),
                                  onPressed: () => _approveEnrollment(enrollment['id']),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () => _rejectEnrollment(enrollment['id']),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _showEnrollmentDetail(context, enrollment),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
