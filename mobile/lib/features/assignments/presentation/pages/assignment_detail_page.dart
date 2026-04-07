import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/database/database_service.dart';
import '../widgets/assignment_submission_modal.dart';

class AssignmentDetailPage extends ConsumerStatefulWidget {
  final int assignmentId;

  const AssignmentDetailPage({super.key, required this.assignmentId});

  @override
  ConsumerState<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends ConsumerState<AssignmentDetailPage> {
  Map<String, dynamic>? _assignment;
  List<dynamic> _questions = [];
  Map<String, dynamic>? _submission;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadAssignment();
  }

  Future<void> _loadAssignment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/elearning/assignments/${widget.assignmentId}/');
      setState(() {
        _assignment = response.data as Map<String, dynamic>;
      });
      
      // Charger les questions si disponibles
      try {
        final questionsResponse = await ApiService().get('/api/elearning/assignments/${widget.assignmentId}/questions/');
        setState(() {
          _questions = questionsResponse.data is List 
              ? questionsResponse.data 
              : (questionsResponse.data['results'] ?? []);
        });
      } catch (e) {
        // Pas de questions ou erreur, continuer
        setState(() {
          _questions = [];
        });
      }
      
      // Charger la soumission de l'élève pour afficher le score
      try {
        final submissionsResponse = await ApiService().get('/api/elearning/submissions/', queryParameters: {
          'assignment': widget.assignmentId,
        });
        final submissions = submissionsResponse.data is List 
            ? submissionsResponse.data 
            : (submissionsResponse.data['results'] ?? []);
        if (submissions.isNotEmpty) {
          setState(() {
            _submission = submissions.first as Map<String, dynamic>;
          });
        }
      } catch (e) {
        // Pas de soumission ou erreur, continuer
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSubmissionModal() {
    showDialog(
      context: context,
      builder: (context) => AssignmentSubmissionModal(
        assignmentId: widget.assignmentId,
        questions: _questions,
        onSubmitted: () {
          _loadAssignment();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails du devoir')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_assignment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails du devoir')),
        body: const Center(child: Text('Devoir non trouvé')),
      );
    }

    final dueDate = _assignment!['due_date'] != null
        ? DateTime.parse(_assignment!['due_date'])
        : null;
    final status = _assignment!['status'] ?? 'pending';
    // Une seule soumission autorisée sauf si l'enseignant a autorisé une nouvelle (allow_resubmit)
    final hasSubmission = _submission != null;
    final allowResubmit = _submission?['allow_resubmit'] == true;
    final canSubmit = (!hasSubmission || allowResubmit) &&
        dueDate != null &&
        DateTime.now().isBefore(dueDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(_assignment!['title'] ?? 'Devoir'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _assignment!['title'] ?? 'Sans titre',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            if (_assignment!['description'] != null)
              Text(
                _assignment!['description'],
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Statut:'),
                        Chip(
                          label: Text(status.toUpperCase()),
                          backgroundColor: status == 'submitted'
                              ? Colors.green
                              : status == 'overdue'
                                  ? Colors.red
                                  : Colors.orange,
                        ),
                      ],
                    ),
                    if (dueDate != null) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Date d\'échéance:'),
                          Text(DateFormat('dd/MM/yyyy HH:mm').format(dueDate)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Questions du devoir
            if (_questions.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Questions:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._questions.asMap().entries.map((entry) {
                final index = entry.key;
                final question = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(question['question_text'] ?? 'Question'),
                    subtitle: Text('Type: ${question['question_type'] ?? 'N/A'}'),
                  ),
                );
              }),
            ],
            // Afficher le score si disponible
            if (_submission != null && _submission!['score'] != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Devoir soumis',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Score:'),
                          Text(
                            '${_submission!['score']} / ${_submission!['total_points'] ?? _assignment!['total_points'] ?? 20}',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                          ),
                        ],
                      ),
                      if (_submission!['best_score'] != null && _submission!['best_score'] != _submission!['score'])
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Meilleure tentative: ${_submission!['best_score']} / ${_submission!['total_points'] ?? _assignment!['total_points'] ?? 20}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (hasSubmission && !allowResubmit) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ce devoir a déjà été soumis. Une seule soumission est autorisée. Pour soumettre à nouveau, votre enseignant doit vous y autoriser.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (canSubmit)
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _showSubmissionModal,
                icon: const Icon(Icons.upload),
                label: Text(_submission != null ? 'Soumettre à nouveau (autorisé)' : 'Soumettre le devoir'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
