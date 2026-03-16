import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/api_service.dart';

class MessageComposeModal extends ConsumerStatefulWidget {
  const MessageComposeModal({super.key});

  @override
  ConsumerState<MessageComposeModal> createState() => _MessageComposeModalState();
}

class _MessageComposeModalState extends ConsumerState<MessageComposeModal> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  List<dynamic> _recipients = [];
  List<int> _selectedRecipients = [];
  bool _isLoading = false;
  bool _loadingRecipients = true;

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    setState(() => _loadingRecipients = true);
    try {
      // Charger les utilisateurs disponibles (enseignants, admins, etc.)
      final response = await ApiService().get(
        '/api/auth/users/school-staff/',
        useCache: false,
      );
      setState(() {
        _recipients = response.data is List
            ? response.data
            : (response.data['results'] ?? []);
        _loadingRecipients = false;
      });
    } catch (e) {
      setState(() => _loadingRecipients = false);
    }
  }

  Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins un destinataire')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ApiService().post(
        '/api/communication/messages/',
        data: {
          'recipients': _selectedRecipients,
          'subject': _subjectController.text.trim(),
          'message': _messageController.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message envoyé avec succès')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      // Afficher un message d'erreur plus lisible pour l'utilisateur
      String message = 'Impossible d\'envoyer le message';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['detail'] is String) {
          message = data['detail'] as String;
        } else if (data is Map && data['non_field_errors'] is List && data['non_field_errors'].isNotEmpty) {
          message = data['non_field_errors'].join('\n');
        } else if (e.message != null) {
          message = e.message!;
        }
      } else {
        message = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // En-tête
              AppBar(
                title: const Text('Nouveau message'),
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
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Objet *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'L\'objet est requis' : null,
                      ),
                      const SizedBox(height: 16),
                      // Destinataires
                      const Text(
                        'Destinataires *',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingRecipients)
                        const Center(child: CircularProgressIndicator())
                      else
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _recipients.length,
                            itemBuilder: (context, index) {
                              final recipient = _recipients[index];
                              final userId = recipient['id'] as int;
                              final name = '${recipient['first_name'] ?? ''} ${recipient['last_name'] ?? ''}'.trim();
                              final isSelected = _selectedRecipients.contains(userId);
                              
                              return CheckboxListTile(
                                title: Text(name.isEmpty ? 'Utilisateur' : name),
                                subtitle: Text(recipient['role'] ?? ''),
                                value: isSelected,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedRecipients.add(userId);
                                    } else {
                                      _selectedRecipients.remove(userId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          labelText: 'Message *',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 10,
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
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendMessage,
                        child: _isLoading
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
