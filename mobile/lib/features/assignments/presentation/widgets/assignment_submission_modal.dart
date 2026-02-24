import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';

class AssignmentSubmissionModal extends StatefulWidget {
  final int assignmentId;
  final List<dynamic> questions;
  final Function()? onSubmitted;

  const AssignmentSubmissionModal({
    super.key,
    required this.assignmentId,
    required this.questions,
    this.onSubmitted,
  });

  @override
  State<AssignmentSubmissionModal> createState() => _AssignmentSubmissionModalState();
}

class _AssignmentSubmissionModalState extends State<AssignmentSubmissionModal> {
  final Map<int, String> _answers = {};
  File? _selectedFile;
  bool _isSubmitting = false;
  final TextEditingController _generalAnswerController = TextEditingController();

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la sélection du fichier: $e')),
        );
      }
    }
  }

  Future<void> _submitAssignment() async {
    if (_selectedFile == null && widget.questions.isEmpty && _generalAnswerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez fournir au moins une réponse ou un fichier')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final formData = FormData();

      // Ajouter les réponses aux questions
      if (widget.questions.isNotEmpty) {
        final answersMap = <String, String>{};
        for (var entry in _answers.entries) {
          answersMap[entry.key.toString()] = entry.value;
        }
        formData.fields.add(MapEntry('submission_text', answersMap.toString()));
      } else if (_generalAnswerController.text.isNotEmpty) {
        formData.fields.add(MapEntry('submission_text', _generalAnswerController.text));
      }

      // Ajouter le fichier si sélectionné
      if (_selectedFile != null) {
        formData.files.add(MapEntry(
          'submission_file',
          await MultipartFile.fromFile(_selectedFile!.path),
        ));
      }

      final api = ApiService();
      await api.post(
        '/api/elearning/assignments/${widget.assignmentId}/submit/',
        data: formData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devoir soumis avec succès')),
        );
        widget.onSubmitted?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        String message = 'Erreur lors de la soumission';
        if (e is DioException && e.response?.statusCode == 403) {
          final detail = e.response?.data;
          if (detail is Map && detail['detail'] != null) {
            message = detail['detail'].toString();
          } else {
            message = 'Une seule soumission est autorisée. Demandez à votre enseignant d\'autoriser une nouvelle soumission.';
          }
        } else if (e is DioException && e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map && data['detail'] != null) {
            message = data['detail'].toString();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildQuestionWidget(dynamic question) {
    final questionId = question['id'] as int;
    final questionType = question['question_type'] as String? ?? 'TEXT';
    final questionText = question['question_text'] ?? 'Question';
    final currentAnswer = _answers[questionId] ?? '';

    switch (questionType) {
      case 'SINGLE_CHOICE':
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  questionText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...['A', 'B', 'C', 'D'].map((option) {
                  final optionKey = 'option_${option.toLowerCase()}';
                  final optionValue = question[optionKey];
                  if (optionValue == null || optionValue.toString().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return RadioListTile<String>(
                    title: Text(optionValue),
                    value: option,
                    groupValue: currentAnswer,
                    onChanged: (value) {
                      setState(() {
                        _answers[questionId] = value!;
                      });
                    },
                  );
                }),
              ],
            ),
          ),
        );

      case 'MULTIPLE_CHOICE':
        final selectedAnswers = currentAnswer.split(',').where((a) => a.isNotEmpty).toSet();
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  questionText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...['A', 'B', 'C', 'D'].map((option) {
                  final optionKey = 'option_${option.toLowerCase()}';
                  final optionValue = question[optionKey];
                  if (optionValue == null || optionValue.toString().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return CheckboxListTile(
                    title: Text(optionValue),
                    value: selectedAnswers.contains(option),
                    onChanged: (checked) {
                      setState(() {
                        final newAnswers = selectedAnswers.toSet();
                        if (checked == true) {
                          newAnswers.add(option);
                        } else {
                          newAnswers.remove(option);
                        }
                        _answers[questionId] = newAnswers.join(',');
                      });
                    },
                  );
                }),
              ],
            ),
          ),
        );

      case 'NUMBER':
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  questionText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Entrez un nombre',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: currentAnswer),
                  onChanged: (value) {
                    _answers[questionId] = value;
                  },
                ),
              ],
            ),
          ),
        );

      default: // TEXT, SHORT_ANSWER, ESSAY
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  questionText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLines: questionType == 'ESSAY' ? 10 : 3,
                  decoration: InputDecoration(
                    hintText: questionType == 'ESSAY' 
                        ? 'Rédigez votre réponse...'
                        : 'Entrez votre réponse',
                    border: const OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: currentAnswer),
                  onChanged: (value) {
                    _answers[questionId] = value;
                  },
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    _generalAnswerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          children: [
            // En-tête
            AppBar(
              title: const Text('Soumettre le devoir'),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Questions
                    if (widget.questions.isNotEmpty) ...[
                      const Text(
                        'Répondez aux questions:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ...widget.questions.map((q) => _buildQuestionWidget(q)),
                    ] else ...[
                      // Réponse générale si pas de questions
                      const Text(
                        'Votre réponse:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _generalAnswerController,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          hintText: 'Rédigez votre réponse...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Fichier
                    const Text(
                      'Fichier joint (optionnel):',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: Text(_selectedFile == null 
                                ? 'Sélectionner un fichier'
                                : _selectedFile!.path.split('/').last),
                          ),
                        ),
                        if (_selectedFile != null)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => _selectedFile = null);
                            },
                          ),
                      ],
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
                      onPressed: _isSubmitting ? null : _submitAssignment,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Soumettre'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
