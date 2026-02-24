import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

class TutoringMessageFormModal extends ConsumerStatefulWidget {
  final List<dynamic> children;
  final Function()? onSubmitted;

  const TutoringMessageFormModal({
    super.key,
    required this.children,
    this.onSubmitted,
  });

  @override
  ConsumerState<TutoringMessageFormModal> createState() => _TutoringMessageFormModalState();
}

class _TutoringMessageFormModalState extends ConsumerState<TutoringMessageFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  int? _selectedStudentId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitMessage() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un enfant')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService().post('/api/tutoring/messages/', data: {
        'student': _selectedStudentId,
        'message': _messageController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message envoyé avec succès')),
        );
        widget.onSubmitted?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  String _getChildName(dynamic child) {
    final identity = child['identity'] ?? child;
    final user = identity['user'] ?? {};
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final studentId = identity['student_id'] ?? '';
    return '${firstName} ${lastName}'.trim() + (studentId.isNotEmpty ? ' - $studentId' : '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // En-tête
              AppBar(
                title: const Text('Envoyer un message'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              // Contenu
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Enfant
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Enfant *',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedStudentId,
                        items: widget.children.map((child) {
                          final identity = child['identity'] ?? child;
                          final studentId = identity['id'];
                          return DropdownMenuItem<int>(
                            value: studentId as int,
                            child: Text(_getChildName(child)),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedStudentId = value),
                        validator: (value) => value == null ? 'Ce champ est requis' : null,
                      ),
                      const SizedBox(height: 16),
                      // Message
                      TextFormField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          labelText: 'Message *',
                          border: OutlineInputBorder(),
                          hintText: 'Votre message...',
                        ),
                        maxLines: 8,
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Le message est requis' : null,
                      ),
                    ],
                  ),
                ),
              ),
              // Boutons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitMessage,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Envoyer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
